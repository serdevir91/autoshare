import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/device_node.dart';
import 'storage_service.dart';

class DiscoveryService extends ChangeNotifier {
  final StorageService _storageService;
  static const int udpPort = 53842;
  
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  Timer? _pingTimer;
  
  final Map<String, DeviceNode> _activeDevices = {};
  bool _isScanning = false;

  DiscoveryService(this._storageService);

  bool get isScanning => _isScanning;
  
  List<DeviceNode> get discoveredDevices {
    final pairedIds = _storageService.getPairedDevices().map((d) => d.id).toSet();
    return _activeDevices.values.map((device) {
      final isPaired = pairedIds.contains(device.id);
      final pairedDevice = isPaired ? _storageService.getPairedDevice(device.id) : null;
      return device.copyWith(
        isPaired: isPaired,
        pairToken: pairedDevice?.pairToken,
      );
    }).toList();
  }

  // Get active local IPv4 address
  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          // Exclude virtual interfaces if possible and prefer common local range
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            return ip;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return null;
  }

  Future<void> start() async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket!.broadcastEnabled = true;
      _socket!.multicastLoopback = false;

      _socket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleIncomingPacket(datagram);
          }
        }
      });

      // Start periodic broadcasts
      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) => broadcastPresence());
      // Start cleaning up offline devices
      _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) => _cleanupOfflineDevices());
      // Start TCP ping for paired devices (fallback when UDP is blocked)
      _pingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pingPairedDevices());

      // Send initial presence broadcast immediately
      await broadcastPresence();
    } catch (e) {
      debugPrint('UDP Socket initialization error: $e');
      stop();
    }
  }

  Future<void> broadcastPresence() async {
    if (_socket == null) return;
    
    final ip = await getLocalIp();
    if (ip == null) return;

    final myPresence = {
      'id': _storageService.deviceId,
      'name': _storageService.deviceName,
      'ip': ip,
      'port': _storageService.devicePort,
      'type': Platform.isWindows ? 'pc' : 'mobile',
    };

    final message = jsonEncode(myPresence);
    final bytes = utf8.encode(message);

    try {
      // 1. Global broadcast
      _socket!.send(bytes, InternetAddress('255.255.255.255'), udpPort);

      // 2. Subnet-specific broadcast (e.g., 192.168.43.255)
      //    Crucial for mobile hotspots that block global broadcast
      final parts = ip.split('.');
      if (parts.length == 4) {
        final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
        _socket!.send(bytes, InternetAddress(subnetBroadcast), udpPort);
      }
    } catch (e) {
      debugPrint('Error sending broadcast: $e');
    }
  }

  void _handleIncomingPacket(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message) as Map<String, dynamic>;

      final id = json['id'] as String;
      // Ignore broadcasts from this device itself
      if (id == _storageService.deviceId) return;

      final name = json['name'] as String;
      final ip = datagram.address.address; // Use actual packet source IP
      final port = json['port'] as int;
      final type = json['type'] as String;

      final device = DeviceNode(
        id: id,
        name: name,
        ip: ip,
        port: port,
        type: type,
        lastSeen: DateTime.now(),
      );

      _activeDevices[id] = device;
      notifyListeners();
    } catch (e) {
      // Silently catch invalid JSON packets
    }
  }

  void _cleanupOfflineDevices() {
    final now = DateTime.now();
    bool changed = false;

    _activeDevices.removeWhere((id, device) {
      final isOffline = now.difference(device.lastSeen) > const Duration(seconds: 8);
      if (isOffline) {
        changed = true;
      }
      return isOffline;
    });

    if (changed) {
      notifyListeners();
    }
  }

  Future<void> _pingPairedDevices() async {
    final paired = _storageService.getPairedDevices();
    if (paired.isEmpty) return;

    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 1500);

    // Get current local IP to derive subnet
    final localIp = await getLocalIp();

    // Build list of (ip, port) targets to probe
    final targets = <({String ip, int port})>{};

    // 1. Add each paired device's stored IP + port
    for (final peer in paired) {
      if (peer.ip.isNotEmpty) {
        targets.add((ip: peer.ip, port: peer.port));
      }
    }

    // 2. Add gateway IP (.1) with each paired device's port
    if (localIp != null) {
      final parts = localIp.split('.');
      if (parts.length == 4) {
        final gatewayIp = '${parts[0]}.${parts[1]}.${parts[2]}.1';
        for (final peer in paired) {
          targets.add((ip: gatewayIp, port: peer.port));
        }
      }
    }

    Future<void> probe(String ip, int port) async {
      try {
        final uri = Uri.parse('http://$ip:$port/api/status');
        final request = await client.getUrl(uri);
        final response = await request.close();

        if (response.statusCode == HttpStatus.ok) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final id = json['id'] as String;
          final name = json['name'] as String;
          final type = json['type'] as String? ?? 'mobile';

          // Ignore our own device
          if (id == _storageService.deviceId) return;

          DeviceNode? matchingPeer;
          try {
            matchingPeer = paired.firstWhere((p) => p.id == id);
          } catch (_) {
            matchingPeer = null;
          }

          if (matchingPeer != null) {
            final updatedDevice = DeviceNode(
              id: id,
              name: name,
              ip: ip,
              port: port,
              type: type,
              lastSeen: DateTime.now(),
            );

            _activeDevices[id] = updatedDevice;

            // If the stored IP changed, update in SharedPreferences
            if (matchingPeer.ip != ip || matchingPeer.name != name || matchingPeer.type != type) {
              final newPairedNode = matchingPeer.copyWith(ip: ip, name: name, type: type);
              await _storageService.addPairedDevice(newPairedNode);
            }
          }
        }
      } catch (_) {
        // Ping failed, ignore
      }
    }

    await Future.wait(targets.map((t) => probe(t.ip, t.port)));
    notifyListeners();
    client.close();
  }

  void stop() {
    _isScanning = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _socket?.close();
    _socket = null;
    _activeDevices.clear();
    notifyListeners();
  }
}
