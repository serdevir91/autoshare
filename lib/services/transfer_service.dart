import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/device_node.dart';
import 'storage_service.dart';
import 'notification_service.dart';

enum TransferState { idle, running, completed, failed }

class TransferStatus {
  final String fileName;
  final int fileSize;
  final int bytesTransferred;
  final bool isIncoming;
  final String senderName;
  final TransferState status;
  final String? filePath;

  TransferStatus({
    required this.fileName,
    required this.fileSize,
    required this.bytesTransferred,
    required this.isIncoming,
    required this.senderName,
    required this.status,
    this.filePath,
  });

  double get progress => fileSize > 0 ? bytesTransferred / fileSize : 0.0;
  
  String get speedFormatted {
    // Simple transfer rate helper if needed
    return '';
  }
}

class PairRequestEvent {
  final DeviceNode sender;
  final void Function(bool accept) callback;

  PairRequestEvent(this.sender, this.callback);
}

class TransferService extends ChangeNotifier {
  final StorageService _storageService;
  final NotificationService _notificationService = NotificationService();

  HttpServer? _server;
  bool _isServerRunning = false;

  final StreamController<PairRequestEvent> _pairRequestStreamController = StreamController<PairRequestEvent>.broadcast();
  Stream<PairRequestEvent> get onPairRequest => _pairRequestStreamController.stream;

  final StreamController<TransferStatus> _transferStatusStreamController = StreamController<TransferStatus>.broadcast();
  Stream<TransferStatus> get onTransferStatus => _transferStatusStreamController.stream;

  TransferStatus? _currentTransfer;
  TransferStatus? get currentTransfer => _currentTransfer;

  TransferService(this._storageService) {
    onTransferStatus.listen((status) {
      _currentTransfer = status;
      notifyListeners();
    });
  }

  bool get isServerRunning => _isServerRunning;

  Future<void> startServer() async {
    if (_isServerRunning) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _storageService.devicePort);
      _isServerRunning = true;
      notifyListeners();

      _server!.listen((HttpRequest request) async {
        try {
          if (request.method == 'GET' && request.uri.path == '/api/status') {
            _handleStatusRequest(request);
          } else if (request.method == 'POST' && request.uri.path == '/api/pair') {
            await _handlePairRequest(request);
          } else if (request.method == 'POST' && request.uri.path == '/api/transfer') {
            await _handleTransferRequest(request);
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(jsonEncode({'status': 'not_found'}));
            await request.response.close();
          }
        } catch (e) {
          debugPrint('Error handling request: $e');
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('Failed to start server: $e');
      _isServerRunning = false;
      notifyListeners();
    }
  }

  void _handleStatusRequest(HttpRequest request) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'status': 'ok',
      'id': _storageService.deviceId,
      'name': _storageService.deviceName,
      'type': Platform.isWindows ? 'pc' : 'mobile',
    }));
    request.response.close();
  }

  Future<void> _handlePairRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;

    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final id = json['id'] as String;
      final name = json['name'] as String;
      final ip = request.connectionInfo?.remoteAddress.address ?? json['ip'] as String;
      final port = json['port'] as int;
      final type = json['type'] as String;
      final action = json['action'] as String;

      final senderDevice = DeviceNode(
        id: id,
        name: name,
        ip: ip,
        port: port,
        type: type,
        lastSeen: DateTime.now(),
      );

      if (action == 'request') {
        final completer = Completer<bool>();
        
        _pairRequestStreamController.add(PairRequestEvent(senderDevice, (accept) {
          completer.complete(accept);
        }));

        final accepted = await completer.future;

        if (accepted) {
          final token = const Uuid().v4();
          final pairedNode = senderDevice.copyWith(isPaired: true, pairToken: token);
          await _storageService.addPairedDevice(pairedNode);

          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'status': 'accepted',
            'token': token,
            'id': _storageService.deviceId,
            'name': _storageService.deviceName,
          }));
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({'status': 'declined'}));
        }
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'status': 'bad_request', 'message': 'Unknown action'}));
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'status': 'error', 'message': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> _handleTransferRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;

    final senderId = request.headers.value('x-sender-id') ?? '';
    final token = request.headers.value('x-pair-token') ?? '';
    final fileNameComponent = request.headers.value('x-file-name') ?? 'unnamed_file';
    final fileName = Uri.decodeComponent(fileNameComponent);
    final fileSizeStr = request.headers.value('x-file-size') ?? '0';
    final fileSize = int.tryParse(fileSizeStr) ?? 0;

    // Verify pairing security
    final isPaired = _storageService.isDevicePaired(senderId);
    final pairedDevice = _storageService.getPairedDevice(senderId);

    if (!isPaired || pairedDevice == null || pairedDevice.pairToken != token) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write(jsonEncode({'status': 'forbidden', 'message': 'Security token mismatch'}));
      await request.response.close();
      return;
    }

    // Auto-accept transfer and start streaming file bytes to disk
    final targetPath = _storageService.getUniqueFilePath(fileName);
    final targetFile = File(targetPath);
    final ioSink = targetFile.openWrite();

    _transferStatusStreamController.add(TransferStatus(
      fileName: fileName,
      fileSize: fileSize,
      bytesTransferred: 0,
      isIncoming: true,
      senderName: pairedDevice.name,
      status: TransferState.running,
    ));

    int bytesRead = 0;
    int lastNotificationProgress = 0;
    final notificationId = 100 + DateTime.now().millisecondsSinceEpoch % 10000;

    try {
      await request.forEach((chunk) {
        ioSink.add(chunk);
        bytesRead += chunk.length;
        
        final progress = fileSize > 0 ? (bytesRead * 100 ~/ fileSize) : 0;
        
        _transferStatusStreamController.add(TransferStatus(
          fileName: fileName,
          fileSize: fileSize,
          bytesTransferred: bytesRead,
          isIncoming: true,
          senderName: pairedDevice.name,
          status: TransferState.running,
        ));

        // Update progress notification (throttle updates to every 5%)
        if (progress - lastNotificationProgress >= 5) {
          lastNotificationProgress = progress;
          _notificationService.showTransferProgress(
            id: notificationId,
            fileName: fileName,
            progress: progress,
          );
        }
      });

      await ioSink.flush();
      await ioSink.close();

      _transferStatusStreamController.add(TransferStatus(
        fileName: fileName,
        fileSize: fileSize,
        bytesTransferred: fileSize,
        isIncoming: true,
        senderName: pairedDevice.name,
        status: TransferState.completed,
        filePath: targetPath,
      ));

      await _notificationService.cancelNotification(notificationId);
      await _notificationService.showTransferComplete(
        id: notificationId + 1,
        fileName: fileName,
        filePath: targetPath,
      );

      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'status': 'success', 'path': targetPath}));
    } catch (e) {
      await ioSink.close();
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await _notificationService.cancelNotification(notificationId);

      _transferStatusStreamController.add(TransferStatus(
        fileName: fileName,
        fileSize: fileSize,
        bytesTransferred: bytesRead,
        isIncoming: true,
        senderName: pairedDevice.name,
        status: TransferState.failed,
      ));

      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'status': 'failed', 'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  // CLIENT METHOD: Send Pair request to a discovered peer
  Future<bool> pairWithDevice(DeviceNode target) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    try {
      final request = await client.post(target.ip, target.port, '/api/pair');
      request.headers.contentType = ContentType.json;

      final myDetails = {
        'id': _storageService.deviceId,
        'name': _storageService.deviceName,
        'ip': '', // IP is resolved dynamically by receiver
        'port': _storageService.devicePort,
        'type': Platform.isWindows ? 'pc' : 'mobile',
        'action': 'request',
      };

      request.write(jsonEncode(myDetails));
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        if (json['status'] == 'accepted') {
          final token = json['token'] as String;
          final remoteId = json['id'] as String;
          final remoteName = json['name'] as String;

          final pairedDevice = target.copyWith(
            id: remoteId,
            name: remoteName,
            isPaired: true,
            pairToken: token,
          );

          await _storageService.addPairedDevice(pairedDevice);
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Pairing request error: $e');
    } finally {
      client.close();
    }
    return false;
  }

  // CLIENT METHOD: Send file to a paired peer
  Future<void> sendFile(DeviceNode target, File file) async {
    if (target.pairToken == null) {
      throw Exception('Device is not paired or missing pair token');
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    final fileName = p.basename(file.path);
    final fileSize = await file.length();

    _transferStatusStreamController.add(TransferStatus(
      fileName: fileName,
      fileSize: fileSize,
      bytesTransferred: 0,
      isIncoming: false,
      senderName: target.name,
      status: TransferState.running,
    ));

    try {
      final request = await client.post(target.ip, target.port, '/api/transfer');
      
      request.headers.add('x-sender-id', _storageService.deviceId);
      request.headers.add('x-pair-token', target.pairToken!);
      request.headers.add('x-file-name', Uri.encodeComponent(fileName));
      request.headers.add('x-file-size', fileSize.toString());

      final fileStream = file.openRead();
      int bytesSent = 0;

      final progressStream = fileStream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            bytesSent += data.length;
            _transferStatusStreamController.add(TransferStatus(
              fileName: fileName,
              fileSize: fileSize,
              bytesTransferred: bytesSent,
              isIncoming: false,
              senderName: target.name,
              status: TransferState.running,
            ));
            sink.add(data);
          },
        ),
      );

      await request.addStream(progressStream);
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        _transferStatusStreamController.add(TransferStatus(
          fileName: fileName,
          fileSize: fileSize,
          bytesTransferred: fileSize,
          isIncoming: false,
          senderName: target.name,
          status: TransferState.completed,
        ));
      } else {
        throw Exception('Server rejected transfer: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('File sending error: $e');
      _transferStatusStreamController.add(TransferStatus(
        fileName: fileName,
        fileSize: fileSize,
        bytesTransferred: 0,
        isIncoming: false,
        senderName: target.name,
        status: TransferState.failed,
      ));
      rethrow;
    } finally {
      client.close();
    }
  }

  void stopServer() {
    _server?.close(force: true);
    _server = null;
    _isServerRunning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopServer();
    _pairRequestStreamController.close();
    _transferStatusStreamController.close();
    super.dispose();
  }
}
