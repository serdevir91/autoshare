import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  // Current app version matching pubspec.yaml
  static const String currentVersion = '1.0.3';
  static const String repoUrl = 'https://api.github.com/repos/serdevir91/autoshare/releases/latest';

  // Compare simple semantic version strings (e.g. 1.0.2 vs 1.0.3)
  static bool _isNewerVersion(String current, String latest) {
    try {
      final curClean = current.replaceAll('v', '').split('+').first.trim();
      final latClean = latest.replaceAll('v', '').split('+').first.trim();
      
      final curParts = curClean.split('.').map(int.parse).toList();
      final latParts = latClean.split('.').map(int.parse).toList();
      
      for (var i = 0; i < latParts.length; i++) {
        if (i >= curParts.length) return true;
        if (latParts[i] > curParts[i]) return true;
        if (latParts[i] < curParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }

  // Check for updates
  static Future<void> check(BuildContext context, {bool showUpToDate = false}) async {
    if (!Platform.isWindows) return;

    final client = HttpClient();
    client.userAgent = 'AutoShare-Updater';
    client.connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client.getUrl(Uri.parse(repoUrl));
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final latestTag = json['tag_name'] as String;
        final releaseName = json['name'] as String? ?? latestTag;
        final bodyText = json['body'] as String? ?? 'Bug fixes and performance improvements.';

        if (_isNewerVersion(currentVersion, latestTag)) {
          if (context.mounted) {
            _showUpdateDialog(context, latestTag, releaseName, bodyText);
          }
        } else if (showUpToDate) {
          if (context.mounted) {
            _showUpToDateDialog(context);
          }
        }
      } else if (showUpToDate) {
        if (context.mounted) {
          _showErrorDialog(context, 'Failed to fetch release info: Server returned code ${response.statusCode}');
        }
      }
    } catch (e) {
      if (showUpToDate && context.mounted) {
        _showErrorDialog(context, 'Failed to check for updates: $e');
      }
    } finally {
      client.close();
    }
  }

  static void _showUpToDateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 10),
            Text('Up to Date'),
          ],
        ),
        content: const Text('You are using the latest version of AutoShare (v$currentVersion).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Update Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static void _showUpdateDialog(
    BuildContext context,
    String latestTag,
    String releaseName,
    String changelog,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Update Available'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version ($releaseName) of AutoShare is available.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Current Version: v$currentVersion'),
              Text('Latest Version: $latestTag'),
              const SizedBox(height: 16),
              const Text(
                'Release Notes:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    changelog,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _performUpdate(context);
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    );
  }

  static void _performUpdate(BuildContext context) {
    final downloadUrl = 'https://github.com/serdevir91/autoshare/releases/latest/download/windows-setup-AutoShare.exe';
    
    // ValueNotifier to track download progress
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('Downloading update installer...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Installing Update'),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, progress, _) {
                      return Column(
                        children: [
                          LinearProgressIndicator(
                            value: progress > 0 ? progress : null,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 10),
                          if (progress > 0)
                            Text(
                              '%${(progress * 100).toInt()}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: statusNotifier,
                    builder: (context, status, _) {
                      return Text(
                        status,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Download & Install in background
    _downloadAndInstall(downloadUrl, progressNotifier, statusNotifier).catchError((e) {
      if (context.mounted) {
        Navigator.pop(context); // Close progress dialog
        _showErrorDialog(context, 'Failed to perform update: $e');
      }
    });
  }

  static Future<void> _downloadAndInstall(
    String downloadUrl,
    ValueNotifier<double> progressNotifier,
    ValueNotifier<String> statusNotifier,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}\\windows-setup-AutoShare-update.exe';
    
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    
    try {
      final request = await client.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();
      
      if (response.statusCode != HttpStatus.ok) {
        throw Exception('Server returned code ${response.statusCode}');
      }
      
      final file = File(tempPath);
      final sink = file.openWrite();
      
      final contentLength = response.contentLength;
      int bytesDownloaded = 0;
      
      await response.forEach((chunk) {
        sink.add(chunk);
        bytesDownloaded += chunk.length;
        if (contentLength > 0) {
          progressNotifier.value = bytesDownloaded / contentLength;
        }
      });
      
      await sink.flush();
      await sink.close();
      
      statusNotifier.value = 'Launching installer... Closing AutoShare.';
      await Future.delayed(const Duration(milliseconds: 800));

      // Run Inno Setup installer detached, passing /SILENT if desired, but default wizard is safer
      // Inno Setup will close the running autoshare.exe automatically since we set CloseApplications=force
      await Process.start(tempPath, [], mode: ProcessStartMode.detached);
      exit(0);
    } catch (e) {
      client.close();
      rethrow;
    }
  }
}
