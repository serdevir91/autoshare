import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../models/device_node.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';
import '../services/storage_service.dart';
import 'file_manager_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  final StorageService storageService;
  final DiscoveryService discoveryService;
  final TransferService transferService;

  const DashboardScreen({
    super.key,
    required this.storageService,
    required this.discoveryService,
    required this.transferService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late StreamSubscription<PairRequestEvent> _pairSubscription;
  late StreamSubscription<TransferStatus> _transferSubscription;
  bool _isRefreshingPairedDevices = false;
  bool _showWindowsBanner = true;

  @override
  void initState() {
    super.initState();
    _showWindowsBanner = widget.storageService.showWindowsBanner;

    // Start discovery and HTTP server
    widget.discoveryService.start();
    widget.transferService.startServer();

    // Listen for pairing requests
    _pairSubscription = widget.transferService.onPairRequest.listen((event) {
      _showPairRequestDialog(event);
    });

    // Listen for transfer events to show overlay
    _transferSubscription = widget.transferService.onTransferStatus.listen((
      status,
    ) {
      if (status.status == TransferState.running) {
        _showTransferProgressDialog(status);
      }
    });
  }

  @override
  void dispose() {
    _pairSubscription.cancel();
    _transferSubscription.cancel();
    super.dispose();
  }

  void _showPairRequestDialog(PairRequestEvent event) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          title: Row(
            children: [
              Icon(
                event.sender.type == 'pc'
                    ? Icons.computer
                    : Icons.phone_android,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Text('Pairing Request'),
            ],
          ),
          content: Text(
            '${event.sender.name} (${event.sender.ip}) wants to pair with you. Do you want to automatically accept files from this device?',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                event.callback(false);
              },
              child: const Text(
                'Decline',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                event.callback(true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Paired with ${event.sender.name}.')),
                );
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  // Active transfer dialog reference to prevent spawning duplicates
  bool _isTransferDialogOpen = false;

  void _showTransferProgressDialog(TransferStatus initialStatus) {
    if (_isTransferDialogOpen) return;
    _isTransferDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StreamBuilder<TransferStatus>(
          stream: widget.transferService.onTransferStatus,
          initialData: initialStatus,
          builder: (context, snapshot) {
            final status = snapshot.data!;
            final isDone = status.status == TransferState.completed;
            final isFailed = status.status == TransferState.failed;

            if (isDone || isFailed) {
              final nav = Navigator.of(context);
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted && nav.canPop()) {
                  nav.pop();
                  _isTransferDialogOpen = false;
                  if (isDone && status.isIncoming && status.filePath != null) {
                    // Prompt user to open file manager on completion
                    _showFileReceivedSnackBar(
                      status.fileName,
                      status.filePath!,
                    );
                  }
                }
              });
            }

            return PopScope(
              canPop: false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    if (status.status == TransferState.running) ...[
                      SizedBox(
                        height: 80,
                        width: 80,
                        child: CircularProgressIndicator(
                          value: status.progress,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        status.isIncoming ? 'Receiving File' : 'Sending File',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ] else if (isDone) ...[
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 80,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Transfer Complete',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.green,
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.error, color: Colors.red, size: 80),
                      const SizedBox(height: 24),
                      const Text(
                        'Transfer Failed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      status.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (status.status == TransferState.running)
                      Text(
                        '${_formatSize(status.bytesTransferred)} / ${_formatSize(status.fileSize)} (%${(status.progress * 100).toInt()})',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) => _isTransferDialogOpen = false);
  }

  void _showFileReceivedSnackBar(String fileName, String filePath) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('$fileName received.'),
        action: SnackBarAction(
          label: 'VIEW',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FileManagerScreen(
                  storageService: widget.storageService,
                  highlightFilePath: filePath,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB"];
    double size = bytes.toDouble();
    int suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  Future<void> _pickAndSendFile(DeviceNode device) async {
    final result = await FilePicker.pickFiles(allowMultiple: false);
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);

    try {
      await widget.transferService.sendFile(device, file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${p.basename(file.path)} sent successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File send failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _removePairedDevice(String id, String name) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Remove Pairing'),
          content: Text('Do you want to remove the pairing with $name?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                await widget.storageService.removePairedDevice(id);
                setState(() {}); // Rebuild to refresh paired list
                messenger.showSnackBar(
                  SnackBar(content: Text('Pairing with $name removed.')),
                );
              },
              child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refreshPairedDevices() async {
    if (_isRefreshingPairedDevices) return;
    setState(() {
      _isRefreshingPairedDevices = true;
    });

    try {
      await widget.discoveryService.broadcastPresence();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingPairedDevices = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AutoShare',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'File Manager',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      FileManagerScreen(storageService: widget.storageService),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    storageService: widget.storageService,
                    transferService: widget.transferService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.discoveryService,
          widget.transferService,
        ]),
        builder: (context, _) {
          final discovered = widget.discoveryService.discoveredDevices;
          final paired = widget.storageService.getPairedDevices();

          // Separate active paired and active unpaired
          final activePairedIds = discovered
              .where((d) => d.isPaired)
              .map((d) => d.id)
              .toSet();
          final activeUnpaired = discovered.where((d) => !d.isPaired).toList();

          return RefreshIndicator(
            onRefresh: () async {
              await widget.discoveryService.broadcastPresence();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Windows Download Banner (Dismissible, only shown on Android)
                  if (Platform.isAndroid && _showWindowsBanner)
                    _buildWindowsDownloadBanner(theme),

                  // Local Device Info Card (Premium Glassmorphic style)
                  _buildLocalInfoCard(theme),
                  const SizedBox(height: 24),

                  // Paired Devices List
                  _buildSectionHeader(
                    theme,
                    'Paired Devices',
                    Icons.link_rounded,
                    trailing: IconButton(
                      tooltip: 'Refresh Paired Devices',
                      onPressed: _isRefreshingPairedDevices
                          ? null
                          : () {
                              _refreshPairedDevices();
                            },
                      icon: _isRefreshingPairedDevices
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (paired.isEmpty)
                    _buildEmptyStateCard(
                      'No paired devices yet.',
                      'Send a pairing request from the network devices list below.',
                      Icons.link_off_rounded,
                      theme,
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: paired.length,
                      itemBuilder: (context, index) {
                        final peer = paired[index];
                        final isOnline = activePairedIds.contains(peer.id);

                        // Find matching discovered peer to get fresh IP
                        final freshPeer = discovered.firstWhere(
                          (d) => d.id == peer.id,
                          orElse: () => peer,
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isOnline
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                peer.type == 'pc'
                                    ? Icons.computer
                                    : Icons.phone_android,
                                color: isOnline
                                    ? theme.colorScheme.primary
                                    : Colors.grey,
                              ),
                            ),
                            title: Text(
                              peer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              isOnline ? 'Online (${freshPeer.ip})' : 'Offline',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Unpair Device',
                                  onPressed: () => _removePairedDevice(peer.id, peer.name),
                                ),
                                if (isOnline) ...[
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _pickAndSendFile(freshPeer),
                                    icon: const Icon(
                                      Icons.send_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Send'),
                                    style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),

                  // Discovered Devices List
                  _buildSectionHeader(
                    theme,
                    'Network Devices',
                    Icons.wifi_find_rounded,
                    trailing: widget.discoveryService.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  if (activeUnpaired.isEmpty)
                    _buildEmptyStateCard(
                      'Scanning for nearby devices...',
                      'Make sure the app is open on other devices and connected to the same Wi-Fi network.',
                      Icons.radar_rounded,
                      theme,
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: activeUnpaired.length,
                      itemBuilder: (context, index) {
                        final peer = activeUnpaired[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              child: Icon(
                                peer.type == 'pc'
                                    ? Icons.computer
                                    : Icons.phone_android,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            title: Text(
                              peer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text('${peer.ip}:${peer.port}'),
                            trailing: ElevatedButton(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Sending pairing request to ${peer.name}...',
                                    ),
                                  ),
                                );
                                final success = await widget.transferService
                                    .pairWithDevice(peer);
                                if (context.mounted) {
                                  if (success) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Successfully paired with ${peer.name}!',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${peer.name} declined or could not be reached.',
                                        ),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Pair'),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocalInfoCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer.withAlpha(200),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withAlpha(25),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Platform.isWindows ? Icons.computer : Icons.phone_android,
            size: 36,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              widget.storageService.deviceName,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.green.withAlpha(100),
                width: 1.5,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'Active',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsDownloadBanner(ThemeData theme) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 24.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.secondaryContainer.withAlpha(120),
              theme.colorScheme.surfaceContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withAlpha(30),
                    radius: 24,
                    child: Icon(
                      Icons.laptop_windows_rounded,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AutoShare for Windows',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Transfer files to your computer instantly. Click to download the Windows installer.',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () async {
                            final url = Uri.parse(
                              'https://github.com/serdevir91/autoshare/releases/latest/download/windows-setup-AutoShare.exe',
                            );
                            if (await canLaunchUrl(url)) {
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not open download link.'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download Installer'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24), // Space for close button
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                  size: 20,
                ),
                tooltip: 'Dismiss',
                onPressed: () async {
                  setState(() {
                    _showWindowsBanner = false;
                  });
                  await widget.storageService.setShowWindowsBanner(false);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme,
    String title,
    IconData icon, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  Widget _buildEmptyStateCard(
    String title,
    String subtitle,
    IconData icon,
    ThemeData theme,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(100),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline.withAlpha(150)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
