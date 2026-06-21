import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'screens/dashboard_screen.dart';
import 'screens/file_manager_screen.dart';
import 'services/discovery_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'services/transfer_service.dart';

// Global key for navigating from outside widget contexts (e.g. notification clicks)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global notifier for theme settings in AutoShare
final ValueNotifier<({ThemeMode themeMode, bool isAmoled})> themeNotifier = ValueNotifier(
  (themeMode: ThemeMode.system, isAmoled: false),
);

ThemeMode _parseThemeMode(String modeStr) {
  switch (modeStr) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

Future<void> _registerWindowsSendToShortcut() async {
  if (!Platform.isWindows) return;
  try {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return;

    final sendToDir = Directory(p.join(appData, 'Microsoft', 'Windows', 'SendTo'));
    if (!sendToDir.existsSync()) return;

    final shortcutFile = File(p.join(sendToDir.path, 'AutoShare.lnk'));

    final exePath = Platform.resolvedExecutable;
    // Don't create shortcut if running in debug mode/testing
    if (exePath.contains('flutter_tools') || exePath.contains('dart.exe')) {
      return;
    }

    final psCommand =
        '\$WshShell = New-Object -ComObject WScript.Shell; '
        '\$Shortcut = \$WshShell.CreateShortcut(\'${shortcutFile.path}\'); '
        '\$Shortcut.TargetPath = \'$exePath\'; '
        '\$Shortcut.Save();';

    await Process.run('powershell', ['-Command', psCommand]);
    debugPrint('Windows SendTo shortcut created/updated.');
  } catch (e) {
    debugPrint('Error creating Windows SendTo shortcut: $e');
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register Windows SendTo shortcut
  if (Platform.isWindows) {
    unawaited(_registerWindowsSendToShortcut());
  }

  // Parse files shared via command line arguments
  final List<File> initialFiles = [];
  if (Platform.isWindows) {
    for (final arg in args) {
      final file = File(arg);
      try {
        if (file.existsSync()) {
          initialFiles.add(file);
        }
      } catch (_) {}
    }
  }

  // Initialize storage first
  final storageService = StorageService();
  await storageService.init();

  // Load initial theme settings
  final initialModeStr = storageService.themeMode;
  final initialBgStr = storageService.backgroundMode;
  final initialThemeMode = _parseThemeMode(initialModeStr);
  final initialIsAmoled = initialBgStr == 'pure_black';
  themeNotifier.value = (themeMode: initialThemeMode, isAmoled: initialIsAmoled);

  // Initialize notifications
  final notificationService = NotificationService();
  await notificationService.init();

  // Initialize network services
  final discoveryService = DiscoveryService(storageService);
  final transferService = TransferService(storageService);

  runApp(
    AutoShareApp(
      storageService: storageService,
      discoveryService: discoveryService,
      transferService: transferService,
      notificationService: notificationService,
      initialFiles: initialFiles,
    ),
  );
}

class AutoShareApp extends StatefulWidget {
  final StorageService storageService;
  final DiscoveryService discoveryService;
  final TransferService transferService;
  final NotificationService notificationService;
  final List<File> initialFiles;

  const AutoShareApp({
    super.key,
    required this.storageService,
    required this.discoveryService,
    required this.transferService,
    required this.notificationService,
    this.initialFiles = const [],
  });

  @override
  State<AutoShareApp> createState() => _AutoShareAppState();
}

class _AutoShareAppState extends State<AutoShareApp> {
  late StreamSubscription<String?> _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    // Listen to notification clicks to open custom file manager
    _notificationSubscription = widget.notificationService.onNotificationTapped
        .listen((filePath) {
          if (filePath != null && filePath.isNotEmpty) {
            _navigateToFileManager(filePath);
          }
        });
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request notifications permission (Android 13+)
      if (await Permission.notification.status.isDenied) {
        await Permission.notification.request();
      }

      // File manager requires broad storage access on Android 11+
      final allFilesStatus = await Permission.manageExternalStorage.status;
      if (!allFilesStatus.isGranted) {
        await Permission.manageExternalStorage.request();
      }

      await widget.storageService.refreshRootDirectory();
    }
  }

  void _navigateToFileManager(String filePath) {
    // Navigate to the file manager, passing the file path to highlight it
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => FileManagerScreen(
          storageService: widget.storageService,
          highlightFilePath: filePath,
          discoveryService: widget.discoveryService,
          transferService: widget.transferService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vibrant Color Palettes
    final colorSchemeLight = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6200EE),
      brightness: Brightness.light,
      primary: const Color(0xFF6200EE),
      secondary: const Color(0xFF03DAC6),
    );

    final colorSchemeDark = ColorScheme.fromSeed(
      seedColor: const Color(0xFFBB86FC),
      brightness: Brightness.dark,
      primary: const Color(0xFFBB86FC),
      secondary: const Color(0xFF03DAC6),
      surface: const Color(0xFF121212),
    );

    return MaterialApp(
      title: 'AutoShare',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system, // Supports OS setting
      // Light Theme
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorSchemeLight,
        scaffoldBackgroundColor: const Color(0xFFF9F9FB),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      // Dark Theme (Premium)
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: colorSchemeDark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      home: DashboardScreen(
        storageService: widget.storageService,
        discoveryService: widget.discoveryService,
        transferService: widget.transferService,
        initialFiles: widget.initialFiles,
      ),
    );
  }
}
