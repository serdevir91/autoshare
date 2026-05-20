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

  void stop() {
    _isScanning = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _socket?.close();
    _socket = null;
    _activeDevices.clear();
    notifyListeners();
  }
}
