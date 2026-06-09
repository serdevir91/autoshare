import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AgeSignalsSnapshot {
  final bool success;
  final bool supported;
  final bool shouldBlockAccess;
  final String? userStatus;
  final int? userStatusCode;
  final int? ageLower;
  final int? ageUpper;
  final DateTime? mostRecentApprovalDate;
  final String? installId;
  final int? errorCode;
  final String? errorName;
  final String? message;
  final DateTime checkedAt;

  const AgeSignalsSnapshot({
    required this.success,
    required this.supported,
    required this.shouldBlockAccess,
    required this.checkedAt,
    this.userStatus,
    this.userStatusCode,
    this.ageLower,
    this.ageUpper,
    this.mostRecentApprovalDate,
    this.installId,
    this.errorCode,
    this.errorName,
    this.message,
  });

  factory AgeSignalsSnapshot.unsupported(String message) {
    return AgeSignalsSnapshot(
      success: false,
      supported: false,
      shouldBlockAccess: false,
      checkedAt: DateTime.now(),
      message: message,
    );
  }

  factory AgeSignalsSnapshot.fromPlatform(Map<dynamic, dynamic> map) {
    final checkedAtMillis = map['checkedAtMillis'] as int?;
    final approvalMillis = map['mostRecentApprovalDateMillis'] as int?;

    return AgeSignalsSnapshot(
      success: map['success'] == true,
      supported: map['supported'] != false,
      shouldBlockAccess: map['shouldBlockAccess'] == true,
      userStatus: map['userStatus'] as String?,
      userStatusCode: map['userStatusCode'] as int?,
      ageLower: map['ageLower'] as int?,
      ageUpper: map['ageUpper'] as int?,
      mostRecentApprovalDate: approvalMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(approvalMillis),
      installId: map['installId'] as String?,
      errorCode: map['errorCode'] as int?,
      errorName: map['errorName'] as String?,
      message: map['message'] as String?,
      checkedAt: checkedAtMillis == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(checkedAtMillis),
    );
  }

  factory AgeSignalsSnapshot.fromJson(Map<String, dynamic> json) {
    return AgeSignalsSnapshot(
      success: json['success'] == true,
      supported: json['supported'] != false,
      shouldBlockAccess: json['shouldBlockAccess'] == true,
      userStatus: json['userStatus'] as String?,
      userStatusCode: json['userStatusCode'] as int?,
      ageLower: json['ageLower'] as int?,
      ageUpper: json['ageUpper'] as int?,
      mostRecentApprovalDate: _dateFromIso(json['mostRecentApprovalDate']),
      installId: json['installId'] as String?,
      errorCode: json['errorCode'] as int?,
      errorName: json['errorName'] as String?,
      message: json['message'] as String?,
      checkedAt: _dateFromIso(json['checkedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'supported': supported,
      'shouldBlockAccess': shouldBlockAccess,
      'userStatus': userStatus,
      'userStatusCode': userStatusCode,
      'ageLower': ageLower,
      'ageUpper': ageUpper,
      'mostRecentApprovalDate': mostRecentApprovalDate?.toIso8601String(),
      'installId': installId,
      'errorCode': errorCode,
      'errorName': errorName,
      'message': message,
      'checkedAt': checkedAt.toIso8601String(),
    };
  }

  String get ageRangeLabel {
    if (ageLower == null && ageUpper == null) return 'Not provided';
    if (ageLower != null && ageUpper == null) return '$ageLower+';
    if (ageLower == null) return '0-$ageUpper';
    return '$ageLower-$ageUpper';
  }

  String get statusLabel {
    return userStatus?.replaceAll('_', ' ') ?? 'No status returned';
  }

  String get detailsText {
    if (!supported) return message ?? 'Play Age Signals is not supported here.';
    if (!success) {
      final code = errorCode == null ? '' : ' ($errorCode)';
      return '${errorName ?? 'AGE_SIGNALS_ERROR'}$code\n${message ?? 'The age signals check failed.'}';
    }

    final lines = <String>[
      'Status: $statusLabel',
      'Age range: $ageRangeLabel',
      'Checked: ${checkedAt.toLocal()}',
    ];

    if (mostRecentApprovalDate != null) {
      lines.add('Latest approval: ${mostRecentApprovalDate!.toLocal()}');
    }
    if (installId != null && installId!.isNotEmpty) {
      lines.add('Install ID: $installId');
    }
    if (shouldBlockAccess) {
      lines.add('Parent approval was denied for a significant change.');
    }
    return lines.join('\n');
  }

  static DateTime? _dateFromIso(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class AgeSignalsService {
  static const MethodChannel _channel = MethodChannel(
    'com.autoshare.app/age_signals',
  );
  static const String _lastSnapshotKey = 'age_signals_last_snapshot';

  static Future<AgeSignalsSnapshot> check() async {
    if (!Platform.isAndroid) {
      return AgeSignalsSnapshot.unsupported(
        'Play Age Signals is only available on Android.',
      );
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'checkAgeSignals',
      );
      final snapshot = AgeSignalsSnapshot.fromPlatform(response ?? {});
      await _saveLastSnapshot(snapshot);
      return snapshot;
    } on PlatformException catch (e) {
      final snapshot = AgeSignalsSnapshot(
        success: false,
        supported: true,
        shouldBlockAccess: false,
        errorName: e.code,
        message: e.message,
        checkedAt: DateTime.now(),
      );
      await _saveLastSnapshot(snapshot);
      return snapshot;
    }
  }

  static Future<AgeSignalsSnapshot?> lastSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSnapshotKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AgeSignalsSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> checkOnStartup(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final snapshot = await check();
    if (!context.mounted || !snapshot.shouldBlockAccess) return;

    await _showBlockedDialog(context, snapshot);
  }

  static Future<void> checkAndShow(BuildContext context) async {
    final snapshot = await check();
    if (!context.mounted) return;

    if (snapshot.shouldBlockAccess) {
      await _showBlockedDialog(context, snapshot);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded),
            SizedBox(width: 10),
            Text('Play Age Signals'),
          ],
        ),
        content: Text(snapshot.detailsText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showBlockedDialog(
    BuildContext context,
    AgeSignalsSnapshot snapshot,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.block_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Access Restricted'),
          ],
        ),
        content: Text(
          'Google Play reports that parent approval was denied for this supervised account.\n\n${snapshot.detailsText}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<void> _saveLastSnapshot(AgeSignalsSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSnapshotKey, jsonEncode(snapshot.toJson()));
  }
}
