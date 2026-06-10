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

class FileManagerScreen extends StatefulWidget {
  final StorageService storageService;
  final String? highlightFilePath;
  final DiscoveryService? discoveryService;
  final TransferService? transferService;

  const FileManagerScreen({
    super.key,
    required this.storageService,
    this.highlightFilePath,
    this.discoveryService,
    this.transferService,
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
    setState(() {
      if (Platform.isWindows && _currentPath == 'Computer') {
        _files = widget.storageService.getWindowsDrives();
      } else {
        _files = widget.storageService.listFiles(_currentPath);
      }
    });
  }

  void _navigateInto(String folderPath) {
    setState(() {
      _currentPath = folderPath;
      _highlightedFile = null; // Clear highlight on navigation
      _selectedFiles.clear(); // Clear selection on navigation
    });
    _refreshFiles();
  }

  void _navigateUp() {
    if (Platform.isWindows) {
      if (_currentPath == 'Computer') {
        Navigator.of(context).pop();
        return;
      }
      final parentDir = Directory(_currentPath).parent;
      if (parentDir.path == _currentPath) {
        // We reached the absolute root (e.g. C:\)
        setState(() {
          _currentPath = 'Computer';
          _highlightedFile = null;
        });
        _refreshFiles();
        return;
      }
      setState(() {
        _currentPath = parentDir.path;
        _highlightedFile = null;
      });
      _refreshFiles();
      return;
    }

    if (_currentPath == widget.storageService.rootPath) {
      Navigator.of(context).pop();
      return;
    }
    final parentDir = Directory(_currentPath).parent;
    setState(() {
      _currentPath = parentDir.path;
      _highlightedFile = null;
    });
    _refreshFiles();
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
    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        await widget.transferService!.sendFile(target, file);
        successCount++;
      } catch (e) {
        debugPrint('Failed to send ${file.path}: $e');
        failCount++;
      }
    }

    if (mounted) {
      // Clear selection after transfer initiates
      setState(() {
        _selectedFiles.clear();
      });

      if (failCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('All $successCount files sent successfully to ${target.name}!'),
          ),
        );
      } else if (successCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to send $failCount files to ${target.name}.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Sent $successCount files. Failed to send $failCount files to ${target.name}.'),
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
          title: Text(_isSelectionMode ? '${_selectedFiles.length} selected' : 'File Manager'),
          leading: IconButton(
            icon: Icon(_isSelectionMode ? Icons.close_rounded : Icons.arrow_back_rounded),
            onPressed: _isSelectionMode
                ? () {
                    setState(() {
                      _selectedFiles.clear();
                    });
                  }
                : _navigateUp,
          ),
          actions: _isSelectionMode
              ? [
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
              : [
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_rounded),
                    tooltip: 'New Folder',
                    onPressed: _createFolder,
                  ),
                ],
        ),
        body: Column(
          children: [
            // Breadcrumbs Bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildBreadcrumbs(theme),
                    ),
                  ),
                ],
              ),
            ),

            // File List
            Expanded(
              child: _files.isEmpty
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
                          const Text(
                            'This folder is empty.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final file = _files[index];
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
                              if (_isSelectionMode) {
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
                            },
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              setState(() {
                                if (isSelected) {
                                  _selectedFiles.remove(file);
                                } else {
                                  _selectedFiles.add(file);
                                }
                              });
                            },
                            leading: _isSelectionMode
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
                                : Icon(
                                    _getFileIcon(file),
                                    color: _getIconColor(file, theme),
                                    size: 28,
                                  ),
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
                            trailing: _isSelectionMode
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onPressed: () => _showFileActions(file),
                                  ),
                          ),
                        );
                      },
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
