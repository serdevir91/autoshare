import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_node.dart';
import '../models/shared_file.dart';

class StorageService {
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceName = 'device_name';
  static const String _keyDevicePort = 'device_port';
  static const String _keyPairedDevices = 'paired_devices';
  static const String _keyShowWindowsBanner = 'show_windows_banner';

  late SharedPreferences _prefs;
  late Directory _rootDir;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _rootDir = await _resolveRootDirectory();
    if (!_rootDir.existsSync()) {
      _rootDir.createSync(recursive: true);
    }
  }

  Future<void> refreshRootDirectory() async {
    final nextRoot = await _resolveRootDirectory();
    if (nextRoot.path != _rootDir.path) {
      _rootDir = nextRoot;
      if (!_rootDir.existsSync()) {
        _rootDir.createSync(recursive: true);
      }
    }
  }

  Future<Directory> _resolveRootDirectory() async {
    if (Platform.isAndroid) {
      final hasAllFilesAccess =
          await Permission.manageExternalStorage.isGranted;
      if (hasAllFilesAccess) {
        const sharedStoragePath = '/storage/emulated/0';
        final sharedStorageDir = Directory(sharedStoragePath);
        if (sharedStorageDir.existsSync()) {
          return sharedStorageDir;
        }
      }
    }

    // Fallback to app-local storage
    final appDocsDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDocsDir.path, 'AutoShare'));
  }

  // File explorer root directory path
  String get rootPath => _rootDir.path;

  // Preferences accessors
  String get deviceId {
    String? id = _prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      _prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  String get deviceName {
    String? name = _prefs.getString(_keyDeviceName);
    if (name == null) {
      if (Platform.isWindows) {
        name = 'PC-${Platform.localHostname}';
      } else if (Platform.isAndroid) {
        name = 'Android-${Platform.operatingSystemVersion.split(' ').first}';
      } else {
        name = 'Device-${Platform.operatingSystem}';
      }
      _prefs.setString(_keyDeviceName, name);
    }
    return name;
  }

  Future<void> setDeviceName(String name) async {
    await _prefs.setString(_keyDeviceName, name);
  }

  int get devicePort {
    return _prefs.getInt(_keyDevicePort) ?? 53843;
  }

  Future<void> setDevicePort(int port) async {
    await _prefs.setInt(_keyDevicePort, port);
  }

  // Paired devices management
  List<DeviceNode> getPairedDevices() {
    final list = _prefs.getStringList(_keyPairedDevices) ?? [];
    return list
        .map(
          (item) =>
              DeviceNode.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> savePairedDevices(List<DeviceNode> devices) async {
    final list = devices.map((d) => jsonEncode(d.toJson())).toList();
    await _prefs.setStringList(_keyPairedDevices, list);
  }

  Future<void> addPairedDevice(DeviceNode device) async {
    final devices = getPairedDevices();
    devices.removeWhere((d) => d.id == device.id);
    devices.add(device);
    await savePairedDevices(devices);
  }

  Future<void> removePairedDevice(String deviceId) async {
    final devices = getPairedDevices();
    devices.removeWhere((d) => d.id == deviceId);
    await savePairedDevices(devices);
  }

  bool isDevicePaired(String deviceId) {
    return getPairedDevices().any((d) => d.id == deviceId);
  }

  DeviceNode? getPairedDevice(String deviceId) {
    try {
      return getPairedDevices().firstWhere((d) => d.id == deviceId);
    } catch (_) {
      return null;
    }
  }

  // File explorer logic
  List<SharedFile> listFiles(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    try {
      return dir
          .listSync()
          .map((entity) => SharedFile.fromFileSystemEntity(entity))
          .toList()
        ..sort((a, b) {
          // Directories first, then alphabetical
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    } catch (e) {
      debugPrint('Error listing files: $e');
      return [];
    }
  }

  Future<Directory> createFolder(String parentPath, String folderName) async {
    final newDir = Directory(p.join(parentPath, folderName));
    if (!newDir.existsSync()) {
      await newDir.create(recursive: true);
    }
    return newDir;
  }

  Future<void> deleteEntity(String path) async {
    if (path == rootPath) return; // Prevent deleting root
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<FileSystemEntity> moveEntity(
    String srcPath,
    String destDirPath,
  ) async {
    final name = p.basename(srcPath);
    final targetPath = p.join(destDirPath, name);

    // If target already exists, append timestamp to make it unique
    String finalTargetPath = targetPath;
    if (await File(targetPath).exists() ||
        await Directory(targetPath).exists()) {
      final ext = p.extension(name);
      final base = p.basenameWithoutExtension(name);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newName = '$base-$timestamp$ext';
      finalTargetPath = p.join(destDirPath, newName);
    }

    final file = File(srcPath);
    if (await file.exists()) {
      return await file.rename(finalTargetPath);
    }

    final dir = Directory(srcPath);
    if (await dir.exists()) {
      return await dir.rename(finalTargetPath);
    }

    throw FileSystemException('Source does not exist', srcPath);
  }

  // Generate target received file path, ensuring uniqueness
  String getUniqueFilePath(String filename) {
    // Sanitize filename to prevent directory traversal
    final safeFilename = p.basename(filename);
    final targetPath = p.join(_rootDir.path, safeFilename);
    if (!File(targetPath).existsSync()) {
      return targetPath;
    }

    final ext = p.extension(safeFilename);
    final base = p.basenameWithoutExtension(safeFilename);
    var counter = 1;
    while (true) {
      final checkPath = p.join(_rootDir.path, '$base ($counter)$ext');
      if (!File(checkPath).existsSync()) {
        return checkPath;
      }
      counter++;
    }
  }

  // Windows download banner visibility state
  bool get showWindowsBanner {
    return _prefs.getBool(_keyShowWindowsBanner) ?? true;
  }

  Future<void> setShowWindowsBanner(bool show) async {
    await _prefs.setBool(_keyShowWindowsBanner, show);
  }
}
