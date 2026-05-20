import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  final StreamController<String?> _selectNotificationStream = StreamController<String?>.broadcast();
  Stream<String?> get onNotificationTapped => _selectNotificationStream.stream;

  Future<void> init() async {
    // Only support Android and Windows notifications
    if (Platform.isAndroid) {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
          final payload = notificationResponse.payload;
          if (payload != null && payload.isNotEmpty) {
            _selectNotificationStream.add(payload);
          }
        },
      );
    }
  }

  Future<void> showTransferComplete({
    required int id,
    required String fileName,
    required String filePath,
  }) async {
    if (!Platform.isAndroid) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'autoshare_transfer_channel',
      'File Transfers',
      channelDescription: 'Notifies when a file transfer is complete.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      id: id,
      title: 'File Received',
      body: '$fileName has been saved to your device.',
      notificationDetails: platformChannelSpecifics,
      payload: filePath,
    );
  }

  Future<void> showTransferProgress({
    required int id,
    required String fileName,
    required int progress,
  }) async {
    if (!Platform.isAndroid) return;

    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'autoshare_transfer_progress_channel',
      'File Transfer Progress',
      channelDescription: 'Shows real-time file transfer progress.',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: false,
      onlyAlertOnce: true,
      maxProgress: 100,
      progress: progress,
      showProgress: true,
      ongoing: true,
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      id: id,
      title: 'Receiving File...',
      body: '$fileName: %$progress',
      notificationDetails: platformChannelSpecifics,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id: id);
  }
}
