import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/shared_file.dart';
import '../models/device_node.dart';
import '../services/storage_service.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';

enum FileCategory { all, image, video, audio, document }

class FileManagerScreen extends StatefulWidget {
  final StorageService storageService;
  final String? highlightFilePath;
  final DiscoveryService? discoveryService;
  final TransferService? transferService;
  final bool isPickerMode;

  const FileManagerScreen({
    super.key,
    required this.storageService,
    this.highlightFilePath,
    this.discoveryService,
    this.transferService,
    this.isPickerMode = false,
  });

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  static const MethodChannel _fileOpsChannel = MethodChannel(
    'com.autoshare.app/file_ops',
  );
  late String _currentPath;
  List<SharedFile> _files = [];
  String? _highlightedFile;
  final Set<SharedFile> _selectedFiles = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  FileCategory _selectedCategory = FileCategory.all;
  bool _isRecursiveSearch = false;
  bool _isSearchingProgress = false;
  List<SharedFile> _recursiveSearchResults = [];

  final List<String> _backHistory = [];
  final List<String> _forwardHistory = [];
  bool _isCategorySystemWide = true;
  bool _isPathEditing = false;
  final TextEditingController _pathEditController = TextEditingController();

  bool get _isSelectionMode => _selectedFiles.isNotEmpty;

  @override
  void initState() {
    super.initState();

    // If a specific file path is highlighted, start in its directory
    if (widget.highlightFilePath != null) {
      final file = File(widget.highlightFilePath!);
      if (file.existsSync()) {
        _currentPath = file.parent.path;
        _highlightedFile = widget.highlightFilePath;

        // Remove highlight after a delay so it fades out
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _highlightedFile = null;
            });
          }
        });
      } else {
        _currentPath = widget.storageService.rootPath;
      }
    } else {
      _currentPath = widget.storageService.rootPath;
    }

    _refreshFiles();
    _refreshRootIfNeeded();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pathEditController.dispose();
    super.dispose();
  }

  Future<void> _refreshRootIfNeeded() async {
    if (!Platform.isAndroid) return;

    final previousRootPath = widget.storageService.rootPath;
    await widget.storageService.refreshRootDirectory();
    if (!mounted) return;

    final nextRootPath = widget.storageService.rootPath;
    if (nextRootPath != previousRootPath && _currentPath == previousRootPath) {
      setState(() {
        _currentPath = nextRootPath;
      });
      _refreshFiles();
    }
  }

  void _refreshFiles() {
    if (_selectedCategory != FileCategory.all) {
      _loadCategoryFiles();
    } else if (_isRecursiveSearch && _searchQuery.isNotEmpty) {
      _performRecursiveSearch(_searchQuery);
    } else {
      setState(() {
        _isSearchingProgress = false;
        if (Platform.isWindows && _currentPath == 'Computer') {
          _files = widget.storageService.getWindowsDrives();
        } else {
          _files = widget.storageService.listFiles(_currentPath);
        }
      });
    }
  }

  bool _isAtRoot() {
    if (Platform.isWindows) {
      return _currentPath == 'Computer';
    }
    return _currentPath == widget.storageService.rootPath;
  }

  void _goHistoryBack() {
    if (_backHistory.isEmpty) return;
    setState(() {
      _forwardHistory.add(_currentPath);
      _currentPath = _backHistory.removeLast();
      _selectedFiles.clear();
      _highlightedFile = null;
      _isPathEditing = false;
    });
    _refreshFiles();
  }

  void _goHistoryForward() {
    if (_forwardHistory.isEmpty) return;
    setState(() {
      _backHistory.add(_currentPath);
      _currentPath = _forwardHistory.removeLast();
      _selectedFiles.clear();
      _highlightedFile = null;
      _isPathEditing = false;
    });
    _refreshFiles();
  }

  void _navigateUpToParent() {
    if (_isAtRoot()) return;
    
    final nextPath = Platform.isWindows
        ? (_currentPath == 'Computer' ? 'Computer' : (Directory(_currentPath).parent.path == _currentPath ? 'Computer' : Directory(_currentPath).parent.path))
        : (Directory(_currentPath).parent.path);
        
    setState(() {
      _backHistory.add(_currentPath);
      _forwardHistory.clear();
      _currentPath = nextPath;
      _selectedFiles.clear();
      _highlightedFile = null;
      _isPathEditing = false;
    });
    _refreshFiles();
  }

  void _navigateInto(String folderPath) {
    if (folderPath == _currentPath) return;
    setState(() {
      _backHistory.add(_currentPath);
      _forwardHistory.clear(); // Clear forward history on new navigation
      _currentPath = folderPath;
      _highlightedFile = null; // Clear highlight on navigation
      _selectedFiles.clear(); // Clear selection on navigation
      _searchController.clear();
      _searchQuery = '';
      _recursiveSearchResults.clear();
      _isSearchingProgress = false;
      _isPathEditing = false;
    });
    _refreshFiles();
  }


  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
    });
    _refreshFiles();
  }

  void _toggleRecursiveSearch() {
    setState(() {
      _isRecursiveSearch = !_isRecursiveSearch;
    });
    _refreshFiles();
  }

  bool _shouldSkipDirectory(String name, String parentPath) {
    final lowerName = name.toLowerCase();
    
    // Skip hidden folders
    if (name.startsWith('.')) return true;
    
    // Windows system/program folders at the root level of drive
    if (Platform.isWindows) {
      final isDriveRoot = parentPath.endsWith(':\\') || parentPath.endsWith(':/') || parentPath == 'Computer';
      if (isDriveRoot) {
        const winSystemDirs = {
          'windows',
          'program files',
          'program files (x86)',
          'programdata',
          '\$recycle.bin',
          'system volume information',
        };
        if (winSystemDirs.contains(lowerName)) {
          return true;
        }
      }
      
      // Also skip AppData inside user profiles to prevent scanning deep local cache/config files
      if (lowerName == 'appdata') {
        return true;
      }
    }
    
    // Android system folders
    if (Platform.isAndroid) {
      if (lowerName == 'android') {
        if (parentPath == '/storage/emulated/0' || parentPath == '/storage/emulated/0/') {
          return true;
        }
      }
    }
    
    return false;
  }

  List<String> _resolveCategoryRoots() {
    if (!_isCategorySystemWide) {
      return [_currentPath];
    }
    final List<String> roots = [];
    
    if (Platform.isWindows) {
      // Add user profile folders
      final home = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        roots.addAll([
          p.join(home, 'Downloads'),
          p.join(home, 'Documents'),
          p.join(home, 'Pictures'),
          p.join(home, 'Videos'),
          p.join(home, 'Music'),
          p.join(home, 'Desktop'),
        ]);
      }
      
      // Also get all windows drives and add any drive that is not C:\
      final drives = widget.storageService.getWindowsDrives();
      for (final drive in drives) {
        final drivePath = drive.path; // e.g. "D:\"
        final isCDrive = drivePath.toUpperCase().startsWith('C:');
        if (!isCDrive) {
          roots.add(drivePath);
        }
      }
    } else if (Platform.isAndroid) {
      roots.addAll([
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Music',
      ]);
      
      // Also check for external SD card paths in Android (/storage/XXXX-XXXX)
      try {
        final storageDir = Directory('/storage');
        if (storageDir.existsSync()) {
          final list = storageDir.listSync();
          for (final entity in list) {
            if (entity is Directory) {
              final name = p.basename(entity.path);
              if (name != 'emulated' && name != 'self' && !name.startsWith('.')) {
                roots.add(entity.path);
              }
            }
          }
        }
      } catch (_) {}
    } else {
      roots.add(widget.storageService.rootPath);
    }
    
    // Return unique existing folders
    return roots
        .where((path) => Directory(path).existsSync())
        .toSet()
        .toList();
  }

  Stream<FileSystemEntity> _listDirectoriesRecursive(List<String> paths) async* {
    final List<Directory> dirsToScan = [];
    for (final path in paths) {
      final d = Directory(path);
      if (d.existsSync()) {
        dirsToScan.add(d);
      }
    }

    while (dirsToScan.isNotEmpty) {
      final currentDir = dirsToScan.removeAt(0);
      Stream<FileSystemEntity> stream;
      try {
        stream = currentDir.list(recursive: false, followLinks: false);
      } catch (e) {
        continue;
      }

      List<FileSystemEntity> entities = [];
      try {
        entities = await stream.toList();
      } catch (e) {
        continue;
      }

      for (final entity in entities) {
        final name = p.basename(entity.path);
        
        if (_shouldSkipDirectory(name, currentDir.path)) {
          continue;
        }

        if (entity is Directory) {
          dirsToScan.add(entity);
        }
        yield entity;
      }
    }
  }

  Future<void> _performRecursiveSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _recursiveSearchResults = [];
        _isSearchingProgress = false;
      });
      return;
    }

    setState(() {
      _isSearchingProgress = true;
      _recursiveSearchResults = [];
    });

    try {
      List<String> roots = [];
      if (_currentPath == 'Computer') {
        roots = widget.storageService.getWindowsDrives().map((f) => f.path).toList();
      } else {
        roots = [_currentPath];
      }

      final List<SharedFile> results = [];
      int lastUpdate = DateTime.now().millisecondsSinceEpoch;

      await for (final entity in _listDirectoriesRecursive(roots)) {
        if (_searchQuery != query) {
          return;
        }

        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.toLowerCase().contains(query.toLowerCase())) {
            // Also check category filter if active
            if (_selectedCategory != FileCategory.all) {
              final ext = p.extension(entity.path).toLowerCase();
              bool matchesCategory = false;
              switch (_selectedCategory) {
                case FileCategory.image:
                  matchesCategory = const ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic', '.heif', '.tiff', '.tif', '.svg', '.jfif', '.ico'].contains(ext);
                  break;
                case FileCategory.video:
                  matchesCategory = const ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.3gp', '.wmv', '.mpeg', '.mpg', '.m4v', '.ts', '.mts', '.f4v'].contains(ext);
                  break;
                case FileCategory.audio:
                  matchesCategory = const ['.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac', '.wma', '.opus', '.mid', '.midi', '.m4p'].contains(ext);
                  break;
                case FileCategory.document:
                  matchesCategory = const ['.pdf', '.txt', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.csv', '.epub', '.rtf', '.html', '.xml', '.odt', '.ods', '.odp', '.pages', '.key', '.numbers'].contains(ext);
                  break;
                default:
                  matchesCategory = true;
              }
              if (!matchesCategory) continue;
            }

            results.add(SharedFile.fromFileSystemEntity(entity));
            
            // Progressive UI update
            final now = DateTime.now().millisecondsSinceEpoch;
            if (results.length <= 10 || now - lastUpdate > 300) {
              lastUpdate = now;
              if (mounted && _searchQuery == query) {
                setState(() {
                  _recursiveSearchResults = List.from(results);
                });
              }
            }

            if (results.length >= 10000) {
              break;
            }
          }
        }
      }

      if (mounted && _searchQuery == query) {
        setState(() {
          _recursiveSearchResults = results;
          _isSearchingProgress = false;
        });
      }
    } catch (e) {
      debugPrint('Recursive search error: $e');
      if (mounted) {
        setState(() {
          _isSearchingProgress = false;
        });
      }
    }
  }

  Future<void> _loadCategoryFiles() async {
    final query = _searchQuery;
    final category = _selectedCategory;
    final path = _currentPath;

    setState(() {
      _isSearchingProgress = true;
      _files = [];
    });

    try {
      final roots = _resolveCategoryRoots();
      final List<SharedFile> results = [];
      int lastUpdate = DateTime.now().millisecondsSinceEpoch;

      await for (final entity in _listDirectoriesRecursive(roots)) {
        if (_selectedCategory != category || _searchQuery != query || _currentPath != path) {
          return;
        }

        if (entity is File) {
          final name = p.basename(entity.path);
          final ext = p.extension(entity.path).toLowerCase();

          if (query.isNotEmpty && !name.toLowerCase().contains(query.toLowerCase())) {
            continue;
          }

          bool matches = false;
          switch (category) {
            case FileCategory.image:
              matches = const ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic', '.heif', '.tiff', '.tif', '.svg', '.jfif', '.ico'].contains(ext);
              break;
            case FileCategory.video:
              matches = const ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.3gp', '.wmv', '.mpeg', '.mpg', '.m4v', '.ts', '.mts', '.f4v'].contains(ext);
              break;
            case FileCategory.audio:
              matches = const ['.mp3', '.wav', '.ogg', '.m4a', '.flac', '.aac', '.wma', '.opus', '.mid', '.midi', '.m4p'].contains(ext);
              break;
            case FileCategory.document:
              matches = const ['.pdf', '.txt', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.csv', '.epub', '.rtf', '.html', '.xml', '.odt', '.ods', '.odp', '.pages', '.key', '.numbers'].contains(ext);
              break;
            default:
              matches = true;
          }

          if (matches) {
            results.add(SharedFile.fromFileSystemEntity(entity));
            
            // Progressive UI update
            final now = DateTime.now().millisecondsSinceEpoch;
            if (results.length <= 10 || now - lastUpdate > 300) {
              lastUpdate = now;
              if (mounted && _selectedCategory == category && _searchQuery == query && _currentPath == path) {
                setState(() {
                  _files = List.from(results);
                });
              }
            }

            if (results.length >= 10000) {
              break;
            }
          }
        }
      }

      if (mounted && _selectedCategory == category && _searchQuery == query && _currentPath == path) {
        setState(() {
          _files = results;
          _isSearchingProgress = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading category files: $e');
      if (mounted) {
        setState(() {
          _isSearchingProgress = false;
        });
      }
    }
  }

  List<SharedFile> get _filteredFiles {
    if (_selectedCategory != FileCategory.all) {
      return _files;
    }
    if (_isRecursiveSearch && _searchQuery.isNotEmpty) {
      return _recursiveSearchResults;
    }

    List<SharedFile> list = _files;

    // Apply search query filter if local search is active
    if (_searchQuery.isNotEmpty) {
      list = list.where((file) {
        return file.name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return list;
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Create New Folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Folder name',
              border: UnderlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final folderName = controller.text.trim();
                if (folderName.isNotEmpty) {
                  Navigator.pop(context);
                  await widget.storageService.createFolder(
                    _currentPath,
                    folderName,
                  );
                  _refreshFiles();
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFileLeading(SharedFile file, ThemeData theme) {
    if (Platform.isWindows && file.path.endsWith(':\\')) {
      return Icon(Icons.storage_rounded, color: theme.colorScheme.primary, size: 28);
    }
    if (file.isDirectory) {
      return Icon(Icons.folder_rounded, color: Colors.amber.shade700, size: 28);
    }

    final ext = p.extension(file.path).toLowerCase();
    final isImage = const ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext);
    
    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(file.path),
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          cacheWidth: 80,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.image_rounded,
              color: Colors.blue.shade600,
              size: 28,
            );
          },
        ),
      );
    }

    return Icon(
      _getFileIcon(file),
      color: _getIconColor(file, theme),
      size: 28,
    );
  }

  IconData _getFileIcon(SharedFile file) {
    if (Platform.isWindows && file.path.endsWith(':\\')) {
      return Icons.storage_rounded;
    }
    if (file.isDirectory) return Icons.folder_rounded;

    final ext = p.extension(file.path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.webp':
        return Icons.image_rounded;
      case '.mp4':
      case '.mkv':
      case '.avi':
      case '.mov':
      case '.webm':
        return Icons.movie_creation_rounded;
      case '.mp3':
      case '.wav':
      case '.ogg':
      case '.m4a':
      case '.flac':
        return Icons.music_note_rounded;
      case '.pdf':
        return Icons.picture_as_pdf_rounded;
      case '.zip':
      case '.rar':
      case '.tar':
      case '.gz':
      case '.7z':
        return Icons.archive_rounded;
      case '.txt':
      case '.doc':
      case '.docx':
      case '.xls':
      case '.xlsx':
      case '.ppt':
      case '.pptx':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getIconColor(SharedFile file, ThemeData theme) {
    if (Platform.isWindows && file.path.endsWith(':\\')) {
      return theme.colorScheme.primary;
    }
    if (file.isDirectory) return Colors.amber.shade700;

    final ext = p.extension(file.path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
        return Colors.blue.shade600;
      case '.mp4':
      case '.mkv':
      case '.avi':
        return Colors.deepOrange.shade600;
      case '.mp3':
      case '.wav':
        return Colors.purple.shade600;
      case '.pdf':
        return Colors.red.shade600;
      case '.zip':
      case '.rar':
        return Colors.teal.shade600;
      case '.txt':
      case '.docx':
      case '.xlsx':
        return Colors.green.shade600;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  Future<void> _openFile(SharedFile file) async {
    if (file.isDirectory) {
      _navigateInto(file.path);
      return;
    }

    final ext = p.extension(file.path).toLowerCase();
    if (Platform.isAndroid && ext == '.apk') {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final status = await _fileOpsChannel.invokeMethod<String>(
          'installApk',
          {'path': file.path},
        );
        if (!mounted) return;

        if (status == 'unknown_sources_settings_opened') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Bu uygulamadan yüklemeye izin ver ekranı açıldı. İzin verip APK\'ye tekrar dokun.',
              ),
            ),
          );
        }
      } on PlatformException catch (e) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('APK install failed: ${e.message ?? e.code}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    await OpenFilex.open(file.path);
  }

  void _shareFile(SharedFile file) {
    if (file.isDirectory) return;
    Share.shareXFiles([XFile(file.path)], text: file.name);
  }

  void _deleteFile(SharedFile file) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(file.isDirectory ? 'Delete Folder' : 'Delete File'),
          content: Text('${file.name} will be deleted. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await widget.storageService.deleteEntity(file.path);
                _refreshFiles();
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  void _moveFile(SharedFile file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _FolderPickerBottomSheet(
          storageService: widget.storageService,
          excludePaths: {file.path},
          onFolderSelected: (destPath) async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            try {
              await widget.storageService.moveEntity(file.path, destPath);
              _refreshFiles();
              messenger.showSnackBar(
                SnackBar(content: Text('${file.name} moved successfully.')),
              );
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Move failed: $e'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          },
        );
      },
    );
  }

  void _showFileActions(SharedFile file) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _getFileIcon(file),
                      color: _getIconColor(file, theme),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            file.isDirectory
                                ? 'Folder'
                                : '${file.sizeFormatted} • ${file.dateFormatted}',
                            style: TextStyle(
                              color: theme.colorScheme.outline,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: Text(file.isDirectory ? 'Open' : 'Open File'),
                onTap: () {
                  Navigator.pop(context);
                  _openFile(file);
                },
              ),
              if (!file.isDirectory) ...[
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('Share'),
                  onTap: () {
                    Navigator.pop(context);
                    _shareFile(file);
                  },
                ),
                if (widget.transferService != null && widget.discoveryService != null)
                  ListTile(
                    leading: const Icon(Icons.send_rounded),
                    title: const Text('Send to Device'),
                    onTap: () {
                      Navigator.pop(context);
                      _selectDeviceAndSend([File(file.path)]);
                    },
                  ),
              ],
              ListTile(
                leading: const Icon(Icons.drive_file_move_rounded),
                title: const Text('Move to Folder'),
                onTap: () {
                  Navigator.pop(context);
                  _moveFile(file);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFile(file);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectDeviceAndSend(List<File> filesToSend) async {
    if (widget.transferService == null || widget.discoveryService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer service is not initialized.')),
      );
      return;
    }

    final paired = widget.storageService.getPairedDevices();
    if (paired.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('No Paired Devices'),
          content: const Text(
            'You have not paired with any devices yet. Please pair with a device from the home screen first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final discovered = widget.discoveryService!.discoveredDevices;
    final activePairedIds = discovered
        .where((d) => d.isPaired)
        .map((d) => d.id)
        .toSet();

    final selectedDevice = await showModalBottomSheet<DeviceNode>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Send ${filesToSend.length} file(s) to:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const Divider(height: 1),
              ...paired.map((peer) {
                final isOnline = activePairedIds.contains(peer.id);
                final freshPeer = discovered.firstWhere(
                  (d) => d.id == peer.id,
                  orElse: () => peer,
                );

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isOnline
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      peer.type == 'pc' ? Icons.computer : Icons.phone_android,
                      color: isOnline ? theme.colorScheme.primary : Colors.grey,
                    ),
                  ),
                  title: Text(
                    peer.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOnline ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    isOnline ? 'Online (${freshPeer.ip})' : 'Offline',
                    style: TextStyle(color: isOnline ? null : Colors.grey),
                  ),
                  trailing: isOnline
                      ? const Icon(Icons.chevron_right_rounded)
                      : null,
                  enabled: isOnline,
                  onTap: isOnline
                      ? () => Navigator.pop(context, freshPeer)
                      : null,
                );
              }),
            ],
          ),
        );
      },
    );

    if (selectedDevice == null) return;

    // Send the files sequentially
    _sendFilesSequentially(selectedDevice, filesToSend);
  }

  Future<void> _sendFilesSequentially(DeviceNode target, List<File> files) async {
    final messenger = ScaffoldMessenger.of(context);
    final batchResult = await widget.transferService!.sendFiles(target, files);

    if (mounted) {
      // Clear selection after transfer initiates
      setState(() {
        _selectedFiles.clear();
      });

      if (batchResult.failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('All ${batchResult.successCount} files sent successfully to ${target.name}!'),
          ),
        );
      } else if (batchResult.successCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to send ${batchResult.failCount} files to ${target.name}.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Sent ${batchResult.successCount} files. Failed to send ${batchResult.failCount} files to ${target.name}.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _deleteSelectedFiles() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Selected Items'),
          content: Text('Are you sure you want to delete ${_selectedFiles.length} item(s)?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                try {
                  for (final file in _selectedFiles) {
                    await widget.storageService.deleteEntity(file.path);
                  }
                  setState(() {
                    _selectedFiles.clear();
                  });
                  _refreshFiles();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Selected items deleted successfully.')),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Delete failed: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  void _moveSelectedFiles() {
    final excludePaths = _selectedFiles.map((f) => f.path).toSet();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _FolderPickerBottomSheet(
          storageService: widget.storageService,
          excludePaths: excludePaths,
          onFolderSelected: (destPath) async {
            final messenger = ScaffoldMessenger.of(context);
            Navigator.pop(context);
            try {
              for (final file in _selectedFiles) {
                await widget.storageService.moveEntity(file.path, destPath);
              }
              setState(() {
                _selectedFiles.clear();
              });
              _refreshFiles();
              messenger.showSnackBar(
                const SnackBar(content: Text('Selected items moved successfully.')),
              );
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Move failed: $e'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          },
        );
      },
    );
  }

  // Helper to format breadcrumb path items
  List<Widget> _buildBreadcrumbs(ThemeData theme) {
    if (Platform.isWindows) {
      if (_currentPath == 'Computer') {
        return [
          Text(
            'This PC',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ];
      }

      final parts = _currentPath.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();
      final drive = _currentPath.startsWith(RegExp(r'^[a-zA-Z]:')) 
          ? _currentPath.substring(0, 2) + Platform.pathSeparator
          : Platform.pathSeparator;

      final isDriveLast = parts.isEmpty || (parts.length == 1 && parts[0].endsWith(':'));

      List<Widget> crumbs = [
        GestureDetector(
          onTap: () => _navigateInto('Computer'),
          child: Text(
            'This PC',
            style: TextStyle(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const Icon(Icons.chevron_right_rounded, size: 16),
        GestureDetector(
          onTap: isDriveLast ? null : () => _navigateInto(drive),
          child: Text(
            drive.replaceAll(Platform.pathSeparator, ''),
            style: TextStyle(
              color: isDriveLast ? theme.colorScheme.onSurface : theme.colorScheme.primary,
              fontWeight: isDriveLast ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ];

      var accumPath = drive;
      for (int i = 0; i < parts.length; i++) {
        if (i == 0 && parts[i].endsWith(':')) continue;
        crumbs.add(const Icon(Icons.chevron_right_rounded, size: 16));
        accumPath = p.join(accumPath, parts[i]);
        final currentAccumPath = accumPath;
        final isLast = i == parts.length - 1;

        crumbs.add(
          Flexible(
            child: GestureDetector(
              onTap: isLast ? null : () => _navigateInto(currentAccumPath),
              child: Text(
                parts[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                  color: isLast ? theme.colorScheme.onSurface : theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        );
      }
      return crumbs;
    }

    final root = widget.storageService.rootPath;
    if (_currentPath == root) {
      return [
        GestureDetector(
          onTap: () => _navigateInto(root),
          child: Text(
            'AutoShare Root',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ];
    }

    final relative = _currentPath.replaceFirst(root, '');
    final parts = relative
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();

    List<Widget> crumbs = [
      GestureDetector(
        onTap: () => _navigateInto(root),
        child: Text('Root', style: TextStyle(color: theme.colorScheme.primary)),
      ),
    ];

    var accumPath = root;
    for (int i = 0; i < parts.length; i++) {
      crumbs.add(const Icon(Icons.chevron_right_rounded, size: 16));
      accumPath = p.join(accumPath, parts[i]);
      final currentAccumPath = accumPath;
      final isLast = i == parts.length - 1;

      crumbs.add(
        Flexible(
          child: GestureDetector(
            onTap: isLast ? null : () => _navigateInto(currentAccumPath),
            child: Text(
              parts[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                color: isLast
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }

    return crumbs;
  }

  Widget _buildCategoryChip(
    FileCategory category,
    String label,
    IconData icon,
    Color activeColor,
    ThemeData theme,
  ) {
    final isSelected = _selectedCategory == category;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      label: Text(label),
      avatar: Icon(
        icon,
        size: 16,
        color: isSelected ? Colors.white : activeColor,
      ),
      onSelected: (selected) {
        setState(() {
          _selectedCategory = category;
        });
        if (_isRecursiveSearch && _searchQuery.isNotEmpty) {
          _performRecursiveSearch(_searchQuery);
        } else {
          _refreshFiles();
        }
      },
      selectedColor: theme.colorScheme.primary,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _selectedFiles.clear();
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isSelectionMode
              ? '${_selectedFiles.length} selected'
              : (widget.isPickerMode ? 'Select Files' : 'File Manager')),
          leading: IconButton(
            icon: Icon(_isSelectionMode ? Icons.close_rounded : Icons.arrow_back_rounded),
            onPressed: _isSelectionMode
                ? () {
                    setState(() {
                      _selectedFiles.clear();
                    });
                  }
                : () => Navigator.of(context).pop(),
          ),
          actions: _isSelectionMode
              ? [
                  if (widget.isPickerMode)
                    IconButton(
                      icon: const Icon(Icons.check_rounded),
                      tooltip: 'Select Files',
                      onPressed: () {
                        final files = _selectedFiles.map((f) => File(f.path)).toList();
                        Navigator.of(context).pop(files);
                      },
                    )
                  else ...[
                    if (widget.transferService != null && widget.discoveryService != null)
                      IconButton(
                        icon: const Icon(Icons.send_rounded),
                        tooltip: 'Send to Device',
                        onPressed: () {
                          if (_selectedFiles.any((f) => f.isDirectory)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cannot send folders. Please select files only.'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }
                          final files = _selectedFiles.map((f) => File(f.path)).toList();
                          _selectDeviceAndSend(files);
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.drive_file_move_rounded),
                      tooltip: 'Move Selected',
                      onPressed: _moveSelectedFiles,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_rounded),
                      tooltip: 'Delete Selected',
                      onPressed: _deleteSelectedFiles,
                    ),
                  ]
                ]
              : [
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_rounded),
                    tooltip: 'New Folder',
                    onPressed: _createFolder,
                  ),
                ],
        ),
        floatingActionButton: (widget.isPickerMode && _isSelectionMode)
            ? FloatingActionButton.extended(
                onPressed: () {
                  final files = _selectedFiles.map((f) => File(f.path)).toList();
                  Navigator.of(context).pop(files);
                },
                icon: const Icon(Icons.send_rounded),
                label: Text('Send Selected (${_selectedFiles.length})'),
              )
            : null,
        body: Column(
          children: [
            // Breadcrumbs Bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    tooltip: 'Back',
                    visualDensity: VisualDensity.compact,
                    onPressed: _backHistory.isEmpty ? null : _goHistoryBack,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    tooltip: 'Forward',
                    visualDensity: VisualDensity.compact,
                    onPressed: _forwardHistory.isEmpty ? null : _goHistoryForward,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    tooltip: 'Up to Parent',
                    visualDensity: VisualDensity.compact,
                    onPressed: _isAtRoot() ? null : _navigateUpToParent,
                  ),
                  const SizedBox(width: 4),
                  const SizedBox(
                    height: 24,
                    child: VerticalDivider(width: 1, thickness: 1),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _isPathEditing
                        ? TextField(
                            controller: _pathEditController,
                            autofocus: true,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              hintText: 'Enter directory path...',
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _isPathEditing = false;
                                  });
                                },
                              ),
                            ),
                            onSubmitted: (val) {
                              final trimmed = val.trim();
                              if (trimmed.isNotEmpty) {
                                if (trimmed == 'Computer') {
                                  _navigateInto('Computer');
                                } else {
                                  final dir = Directory(trimmed);
                                  if (dir.existsSync()) {
                                    _navigateInto(dir.path);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Directory does not exist.'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                }
                              }
                              setState(() {
                                _isPathEditing = false;
                              });
                            },
                          )
                        : GestureDetector(
                            onTap: () {
                              setState(() {
                                _isPathEditing = true;
                                _pathEditController.text = _currentPath;
                              });
                            },
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: _buildBreadcrumbs(theme),
                              ),
                            ),
                          ),
                  ),
                  if (!_isPathEditing)
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      tooltip: 'Edit Path',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _isPathEditing = true;
                          _pathEditController.text = _currentPath;
                        });
                      },
                    ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: _isRecursiveSearch ? 'Search recursively...' : 'Search in current folder...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHigh,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    isSelected: _isRecursiveSearch,
                    icon: const Icon(Icons.travel_explore_rounded),
                    selectedIcon: const Icon(Icons.travel_explore_rounded),
                    tooltip: 'Recursive Search',
                    onPressed: _toggleRecursiveSearch,
                  ),
                ],
              ),
            ),

            // Category Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isCategorySystemWide ? Icons.lan_rounded : Icons.folder_open_rounded,
                      color: _isCategorySystemWide ? theme.colorScheme.primary : Colors.grey,
                      size: 20,
                    ),
                    tooltip: _isCategorySystemWide ? 'Scope: System Wide' : 'Scope: Current Folder',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _isCategorySystemWide = !_isCategorySystemWide;
                      });
                      _refreshFiles();
                    },
                  ),
                  const SizedBox(width: 4),
                  const SizedBox(
                    height: 24,
                    child: VerticalDivider(width: 1, thickness: 1),
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    FileCategory.all,
                    'All',
                    Icons.all_inclusive_rounded,
                    Colors.grey,
                    theme,
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    FileCategory.image,
                    'Images',
                    Icons.image_rounded,
                    Colors.blue,
                    theme,
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    FileCategory.video,
                    'Videos',
                    Icons.movie_creation_rounded,
                    Colors.deepOrange,
                    theme,
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    FileCategory.audio,
                    'Audio',
                    Icons.music_note_rounded,
                    Colors.purple,
                    theme,
                  ),
                  const SizedBox(width: 8),
                  _buildCategoryChip(
                    FileCategory.document,
                    'Documents',
                    Icons.description_rounded,
                    Colors.green,
                    theme,
                  ),
                ],
              ),
            ),

            // File List
            Expanded(
              child: (_isSearchingProgress && _filteredFiles.isEmpty)
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _filteredFiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open_outlined,
                                size: 64,
                                color: theme.colorScheme.outline.withAlpha(100),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No files match your search.'
                                    : 'This folder is empty.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Stack(
                          children: [
                            ListView.builder(
                              itemCount: _filteredFiles.length,
                              itemBuilder: (context, index) {
                                final file = _filteredFiles[index];
                                final isHighlighted =
                                    _highlightedFile != null &&
                                    _highlightedFile == file.path;
                                final isSelected = _selectedFiles.contains(file);

                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  color: isSelected
                                      ? theme.colorScheme.primary.withAlpha(25)
                                      : isHighlighted
                                          ? theme.colorScheme.primary.withAlpha(40)
                                          : Colors.transparent,
                                  child: ListTile(
                                    selected: isSelected,
                                    onTap: () {
                                      if (file.isDirectory) {
                                        _navigateInto(file.path);
                                      } else {
                                        if (widget.isPickerMode || _isSelectionMode) {
                                          setState(() {
                                            if (isSelected) {
                                              _selectedFiles.remove(file);
                                            } else {
                                              _selectedFiles.add(file);
                                            }
                                          });
                                        } else {
                                          _openFile(file);
                                        }
                                      }
                                    },
                                    onLongPress: file.isDirectory
                                        ? null
                                        : () {
                                            HapticFeedback.mediumImpact();
                                            setState(() {
                                              if (isSelected) {
                                                _selectedFiles.remove(file);
                                              } else {
                                                _selectedFiles.add(file);
                                              }
                                            });
                                          },
                                    leading: _buildFileLeading(file, theme),
                                    title: Text(
                                      file.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      file.isDirectory
                                          ? 'Klasör'
                                          : '${file.sizeFormatted} • ${file.dateFormatted}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: (widget.isPickerMode || _isSelectionMode)
                                        ? Checkbox(
                                            value: isSelected,
                                            onChanged: (val) {
                                              setState(() {
                                                if (val == true) {
                                                  _selectedFiles.add(file);
                                                } else {
                                                  _selectedFiles.remove(file);
                                                }
                                              });
                                            },
                                          )
                                        : IconButton(
                                            icon: const Icon(Icons.more_vert_rounded),
                                            onPressed: () => _showFileActions(file),
                                          ),
                                  ),
                                );
                              },
                            ),
                            if (_isSearchingProgress)
                              const Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// Folder Tree Selector Modal for Moving Files
class _FolderPickerBottomSheet extends StatefulWidget {
  final StorageService storageService;
  final Set<String> excludePaths;
  final void Function(String folderPath) onFolderSelected;

  const _FolderPickerBottomSheet({
    required this.storageService,
    required this.excludePaths,
    required this.onFolderSelected,
  });

  @override
  State<_FolderPickerBottomSheet> createState() =>
      _FolderPickerBottomSheetState();
}

class _FolderPickerBottomSheetState extends State<_FolderPickerBottomSheet> {
  late String _currentPath;
  List<SharedFile> _subdirs = [];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.storageService.rootPath;
    _refreshDirs();
  }

  void _refreshDirs() {
    setState(() {
      if (Platform.isWindows && _currentPath == 'Computer') {
        _subdirs = widget.storageService
            .getWindowsDrives()
            .where((f) => !widget.excludePaths.contains(f.path))
            .toList();
      } else {
        _subdirs = widget.storageService
            .listFiles(_currentPath)
            .where((f) => f.isDirectory && !widget.excludePaths.contains(f.path))
            .toList();
      }
    });
  }

  void _navigateInto(String path) {
    setState(() {
      _currentPath = path;
    });
    _refreshDirs();
  }

  void _navigateUp() {
    if (Platform.isWindows) {
      if (_currentPath == 'Computer') return;
      final parentDir = Directory(_currentPath).parent;
      if (parentDir.path == _currentPath) {
        setState(() {
          _currentPath = 'Computer';
        });
        _refreshDirs();
        return;
      }
      setState(() {
        _currentPath = parentDir.path;
      });
      _refreshDirs();
      return;
    }

    if (_currentPath == widget.storageService.rootPath) return;
    setState(() {
      _currentPath = Directory(_currentPath).parent.path;
    });
    _refreshDirs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRoot = Platform.isWindows 
        ? _currentPath == 'Computer'
        : _currentPath == widget.storageService.rootPath;
    final folderName = isRoot 
        ? (Platform.isWindows ? 'This PC' : 'Root') 
        : p.basename(_currentPath);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Folder',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Current Folder bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                if (!isRoot)
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                    ),
                    onPressed: _navigateUp,
                  ),
                const Icon(Icons.folder_open_rounded, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folderName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Directories List
          Expanded(
            child: _subdirs.isEmpty
                ? const Center(
                    child: Text(
                      'No subfolders found.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _subdirs.length,
                    itemBuilder: (context, index) {
                      final dir = _subdirs[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.folder_rounded,
                          color: Colors.amber,
                        ),
                        title: Text(dir.name),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _navigateInto(dir.path),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _currentPath == 'Computer'
                        ? null
                        : () => widget.onFolderSelected(_currentPath),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Move Here'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
