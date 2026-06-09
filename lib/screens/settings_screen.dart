import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/age_signals_service.dart';
import '../services/storage_service.dart';
import '../services/transfer_service.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storageService;
  final TransferService transferService;

  const SettingsScreen({
    super.key,
    required this.storageService,
    required this.transferService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _portController;
  late TextEditingController _downloadPathController;
  bool _isCheckingAgeSignals = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.storageService.deviceName,
    );
    _portController = TextEditingController(
      text: widget.storageService.devicePort.toString(),
    );
    _downloadPathController = TextEditingController(
      text: widget.storageService.rootPath,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portController.dispose();
    _downloadPathController.dispose();
    super.dispose();
  }

  Future<void> _pickDownloadPath() async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null) {
      setState(() {
        _downloadPathController.text = path;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final newName = _nameController.text.trim();
    final newPort = int.parse(_portController.text.trim());
    final newDownloadPath = _downloadPathController.text.trim();

    final oldPort = widget.storageService.devicePort;

    await widget.storageService.setDeviceName(newName);
    await widget.storageService.setDevicePort(newPort);
    if (newDownloadPath.isNotEmpty) {
      await widget.storageService.setDownloadPath(newDownloadPath);
    }

    // If port changed, restart HTTP Server
    if (oldPort != newPort) {
      widget.transferService.stopServer();
      await widget.transferService.startServer();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!')),
      );
      Navigator.of(context).pop();
    }
  }

  void _removePairedDevice(String id, String name) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
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
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pairedDevices = widget.storageService.getPairedDevices();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device Configuration',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),

              // Device Name TextField
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Device Name',
                  helperText: 'The name other devices on the network will see.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.badge_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a device name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Device Port TextField
              TextFormField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Port',
                  helperText:
                      'Default: 53843. Only change if there is a conflict.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.settings_ethernet_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a port number';
                  }
                  final port = int.tryParse(value.trim());
                  if (port == null || port < 1024 || port > 65535) {
                    return 'Enter a valid port between 1024 and 65535';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Download Folder Selector
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _downloadPathController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Download Folder',
                        helperText: 'Incoming files will be saved here.',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.folder_shared_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _pickDownloadPath,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Browse'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text(
                    'Save Settings',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              if (Platform.isWindows || Platform.isAndroid) ...[
                const SizedBox(height: 24),
                Text(
                  'Software Updates',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      UpdateService.check(context, showUpToDate: true);
                    },
                    icon: const Icon(Icons.update_rounded),
                    label: const Text(
                      'Check for Updates',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              if (Platform.isAndroid) ...[
                const SizedBox(height: 24),
                Text(
                  'Play Age Signals',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isCheckingAgeSignals
                        ? null
                        : () async {
                            setState(() {
                              _isCheckingAgeSignals = true;
                            });
                            await AgeSignalsService.checkAndShow(context);
                            if (mounted) {
                              setState(() {
                                _isCheckingAgeSignals = false;
                              });
                            }
                          },
                    icon: _isCheckingAgeSignals
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_rounded),
                    label: const Text(
                      'Check Age Signals',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Paired Devices Management Section
              Text(
                'Paired Device Management',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              if (pairedDevices.isEmpty)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        'No paired devices found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pairedDevices.length,
                  itemBuilder: (context, index) {
                    final device = pairedDevices[index];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            device.type == 'pc'
                                ? Icons.computer
                                : Icons.phone_android,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          device.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('ID: ${device.id.substring(0, 8)}...'),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                          ),
                          onPressed: () =>
                              _removePairedDevice(device.id, device.name),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
