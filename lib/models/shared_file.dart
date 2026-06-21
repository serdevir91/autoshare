import 'dart:io';
import 'package:intl/intl.dart';

class SharedFile {
  final String name;
  final String path;
  final int size;
  final DateTime dateModified;
  final bool isDirectory;

  SharedFile({
    required this.name,
    required this.path,
    required this.size,
    required this.dateModified,
    required this.isDirectory,
  });

  factory SharedFile.fromFileSystemEntity(FileSystemEntity entity) {
    final stat = entity.statSync();
    return SharedFile(
      name: entity.path.split(Platform.pathSeparator).last,
      path: entity.path,
      size: isFolder(entity) ? 0 : stat.size,
      dateModified: stat.modified,
      isDirectory: isFolder(entity),
    );
  }

  static bool isFolder(FileSystemEntity entity) {
    return entity is Directory;
  }

  String get sizeFormatted {
    if (isDirectory) return '';
    if (size <= 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    // Simple log base 1024 implementation
    double bytes = size.toDouble();
    int suffixIndex = 0;
    while (bytes >= 1024 && suffixIndex < suffixes.length - 1) {
      bytes /= 1024;
      suffixIndex++;
    }
    return '${bytes.toStringAsFixed(1)} ${suffixes[suffixIndex]}';
  }

  String get dateFormatted {
    return DateFormat('dd.MM.yyyy HH:mm').format(dateModified);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedFile &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}
