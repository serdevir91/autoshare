# AutoShare — Agent Guide

This document is a reference guide for AI assistants (agents) working on the AutoShare project.

## Project Summary

AutoShare is a Flutter-based local network file sharing application.
It enables automatic file transfers between Android and Windows devices on the same Wi-Fi/hotspot network.

## Tech Stack

- **Language**: Dart / Flutter 3.11+
- **Platforms**: Android, Windows
- **Package Management**: pub (pubspec.yaml)
- **State Management**: ChangeNotifier + ListenableBuilder
- **Networking**: dart:io (RawDatagramSocket, HttpServer, HttpClient)

## Critical Architectural Decisions

### UDP Discovery (Port 53842)
- `DiscoveryService` sends UDP broadcasts every 3 seconds
- Both `255.255.255.255` (global) and subnet-specific (e.g., `192.168.x.255`) broadcasts are sent
- Subnet broadcast is critical because mobile hotspots often block global broadcast

### HTTP Transfer (Port 53843)
- `TransferService` runs an HTTP server
- Endpoints: `/pair` (POST), `/send` (POST), `/ping` (GET)
- Pairing token (`pairToken`) is generated using UUID v4
- File transfers are only accepted with a valid pairToken

### Windows Notification Stub
- `flutter_local_notifications_windows` requires ATL header (`atlbase.h`)
- Instead of installing ATL, a Dart-only no-op stub package was created
- Location: `packages/flutter_local_notifications_windows_stub/`
- Redirected via `dependency_overrides` in `pubspec.yaml`

### Dependency Conflicts
- `file_picker` (win32 ^5.x) conflicts with `network_info_plus` / `share_plus` (win32 ^6.x)
- Solution: Use `network_info_plus: ^7.0.0` and `share_plus: ^10.1.0`

## File Structure

```
lib/
├── main.dart              # Entry point, theme, navigation
├── models/
│   ├── device_node.dart   # Device: id, name, ip, port, type, pairToken
│   └── shared_file.dart   # File: name, path, size, isDirectory, modifiedDate
├── screens/
│   ├── dashboard_screen.dart    # Main screen: device list, pairing, file sending
│   ├── file_manager_screen.dart # File manager: list, delete, move, share
│   └── settings_screen.dart     # Settings: device name, port, pairing management
└── services/
    ├── discovery_service.dart   # UDP broadcast + listening
    ├── notification_service.dart# Android notifications (Platform.isAndroid guard)
    ├── storage_service.dart     # SharedPreferences + file system ops
    └── transfer_service.dart    # HTTP server + client
```

## Important Rules

1. **Notifications are Android-only**: `NotificationService` guards all methods with `if (!Platform.isAndroid) return;`
2. **Async context**: ScaffoldMessenger/Navigator must be captured BEFORE async gaps (`use_build_context_synchronously`)
3. **debugPrint**: Use `debugPrint()` instead of `print()` in production code
4. **Firewall**: Windows requires firewall rules for UDP 53842 and TCP 53843

## Build Commands

```bash
# Analysis
flutter analyze

# Android APK
flutter build apk --split-per-abi

# Windows EXE
flutter build windows

# Update icons
dart run flutter_launcher_icons
```

## Testing

```bash
flutter test
```
