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
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyBackgroundMode = 'background_mode';
  static const String _keyRateReviewCompleted = 'rate_review_completed';
  static const String _keyRateReviewNeverShow = 'rate_review_never_show';
  static const String _keyRateReviewTransferCount = 'rate_review_transfer_count';
  static const String _keyRateReviewLastPromptCount = 'rate_review_last_prompt_count';

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
  String get rootPath {
    final customPath = _prefs.getString('download_path');
    if (customPath != null && customPath.isNotEmpty) {
      final dir = Directory(customPath);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return dir.path;
    }
    return _rootDir.path;
  }

  Future<void> setDownloadPath(String path) async {
    await _prefs.setString('download_path', path);
  }

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

  List<SharedFile> getWindowsDrives() {
    List<SharedFile> drives = [];
    if (!Platform.isWindows) return drives;
    for (var letter = 65; letter <= 90; letter++) {
      final drivePath = '${String.fromCharCode(letter)}:\\';
      final dir = Directory(drivePath);
      try {
        if (dir.existsSync()) {
          drives.add(SharedFile(
            name: 'Local Disk (${String.fromCharCode(letter)}:)',
            path: drivePath,
            isDirectory: true,
            size: 0,
            dateModified: DateTime.now(),
          ));
        }
      } catch (_) {}
    }
    return drives;
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
    final targetPath = p.join(rootPath, safeFilename);
    if (!File(targetPath).existsSync()) {
      return targetPath;
    }

    final ext = p.extension(safeFilename);
    final base = p.basenameWithoutExtension(safeFilename);
    var counter = 1;
    while (true) {
      final checkPath = p.join(rootPath, '$base ($counter)$ext');
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

  // Theme Mode
  String get themeMode => _prefs.getString(_keyThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_keyThemeMode, mode);
  }

  // Background Mode (amoled vs default)
  String get backgroundMode => _prefs.getString(_keyBackgroundMode) ?? 'default';
  Future<void> setBackgroundMode(String mode) async {
    await _prefs.setString(_keyBackgroundMode, mode);
  }

  // Rate & Review
  bool get isRateReviewCompleted => _prefs.getBool(_keyRateReviewCompleted) ?? false;
  Future<void> setRateReviewCompleted(bool val) async {
    await _prefs.setBool(_keyRateReviewCompleted, val);
  }

  bool get neverShowRateReview => _prefs.getBool(_keyRateReviewNeverShow) ?? false;
  Future<void> setNeverShowRateReview(bool val) async {
    await _prefs.setBool(_keyRateReviewNeverShow, val);
  }

  int get rateReviewTransferCount => _prefs.getInt(_keyRateReviewTransferCount) ?? 0;
  Future<void> setRateReviewTransferCount(int val) async {
    await _prefs.setInt(_keyRateReviewTransferCount, val);
  }

  int get rateReviewLastPromptCount => _prefs.getInt(_keyRateReviewLastPromptCount) ?? 0;
  Future<void> setRateReviewLastPromptCount(int val) async {
    await _prefs.setInt(_keyRateReviewLastPromptCount, val);
  }
}
