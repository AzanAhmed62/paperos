import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../config/app_config.dart';
import '../errors/paper_exception.dart';

/// A backup copied out of the system picker into PaperOS' cache.
class PickedBackupFile {
  const PickedBackupFile({
    required this.path,
    required this.name,
    required this.byteSize,
  });

  final String path;
  final String name;
  final int byteSize;
}

/// Streaming SAF bridge used for `.paperosbackup` save and restore.
///
/// This is deliberately separate from `file_picker`: that API buffers complete
/// files, while a full library may be hundreds of megabytes. The Android side
/// copies with a 64 KiB buffer and enforces a maximum size.
abstract interface class SafFileService {
  bool get isSupported;

  Future<PickedBackupFile?> pickBackup();

  /// Returns false when the user cancelled the save dialog.
  Future<bool> saveBackup({
    required String sourcePath,
    required String suggestedName,
  });
}

class PlatformSafFileService implements SafFileService {
  const PlatformSafFileService();

  static const MethodChannel _channel = MethodChannel('dev.paperos/saf');

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<PickedBackupFile?> pickBackup() async {
    if (!isSupported) {
      throw const PaperException.platform(
        'Backup restore uses the Android system file picker on this build.',
      );
    }
    try {
      final Object? value = await _channel.invokeMethod<Object?>(
        'pickBackup',
        <String, Object?>{'maxBytes': PaperConfig.maxBackupUncompressedBytes},
      );
      if (value == null) return null;
      if (value is! Map) {
        throw const PaperException.platform(
          'The system file picker returned an unexpected result.',
        );
      }
      final String? path = value['path'] as String?;
      final String? name = value['name'] as String?;
      final int? bytes = (value['bytes'] as num?)?.toInt();
      if (path == null || name == null || bytes == null) {
        throw const PaperException.platform(
          'The chosen backup could not be read.',
        );
      }
      return PickedBackupFile(path: path, name: name, byteSize: bytes);
    } on PlatformException catch (error) {
      throw PaperException.platform(
        error.message ?? 'The system file picker failed.',
        cause: error,
        detail: error.code,
      );
    }
  }

  @override
  Future<bool> saveBackup({
    required String sourcePath,
    required String suggestedName,
  }) async {
    if (!isSupported) {
      throw const PaperException.platform(
        'Backup export uses the Android system file picker on this build.',
      );
    }
    if (!await File(sourcePath).exists()) {
      throw const PaperException.missingFile(
        'The finished backup disappeared before it could be saved.',
      );
    }
    try {
      final bool? saved = await _channel.invokeMethod<bool>(
        'saveBackup',
        <String, Object?>{
          'sourcePath': sourcePath,
          'suggestedName': p.basename(suggestedName),
          'mimeType': 'application/zip',
        },
      );
      return saved ?? false;
    } on PlatformException catch (error) {
      throw PaperException.platform(
        error.message ?? 'PaperOS could not save the backup.',
        cause: error,
        detail: error.code,
      );
    }
  }
}
