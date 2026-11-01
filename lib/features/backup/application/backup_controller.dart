import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/platform/saf_file_service.dart';
import '../../settings/application/settings_controller.dart';
import '../data/backup_archive.dart';
import '../data/backup_service.dart';
import '../domain/backup_manifest.dart';

enum BackupTaskKind { create, restore }

/// Live progress shown by Settings while a backup operation is running.
class BackupTask {
  const BackupTask({
    required this.kind,
    required this.message,
    this.fraction,
    this.cancellable = true,
    this.cancelling = false,
  });

  final BackupTaskKind kind;
  final String message;
  final double? fraction;
  final bool cancellable;
  final bool cancelling;

  BackupTask copyWith({
    String? message,
    double? fraction,
    bool? cancellable,
    bool? cancelling,
  }) {
    return BackupTask(
      kind: kind,
      message: message ?? this.message,
      fraction: fraction ?? this.fraction,
      cancellable: cancellable ?? this.cancellable,
      cancelling: cancelling ?? this.cancelling,
    );
  }
}

/// Orchestrates picker, archive service, settings reload and UI refresh.
class BackupController extends Notifier<BackupTask?> {
  bool _cancelled = false;

  @override
  BackupTask? build() => null;

  SafFileService get _saf => ref.read(safFileServiceProvider);
  BackupService get _service => ref.read(backupServiceProvider);

  void cancel() {
    final BackupTask? task = state;
    if (task == null || !task.cancellable || task.cancelling) return;
    _cancelled = true;
    state = task.copyWith(
      message: 'Stopping after the current file…',
      cancelling: true,
    );
  }

  void clear() {
    if (state != null) state = null;
  }

  Future<BackupPreview?> chooseRestoreFile() async {
    final PickedBackupFile? picked = await _saf.pickBackup();
    if (picked == null) return null;
    try {
      return await _service.inspect(
        archivePath: picked.path,
        displayName: picked.name,
      );
    } on Object {
      try {
        await File(picked.path).delete();
      } on FileSystemException {
        // Cache files are disposable.
      }
      rethrow;
    }
  }

  /// Returns the user-facing file name, or null when the save dialog was
  /// cancelled. The archive is a temporary app-private file either way.
  Future<String?> createBackup() async {
    _cancelled = false;
    state = const BackupTask(
      kind: BackupTaskKind.create,
      message: 'Reading the library',
      fraction: 0,
    );
    String? temporary;
    try {
      final BackupResult result = await _service.createBackup(
        settings: ref.read(settingsProvider),
        isCancelled: () => _cancelled,
        onProgress: _onProgress(BackupTaskKind.create),
      );
      temporary = result.path;
      state = state?.copyWith(
        message: 'Choose where to save the backup',
        fraction: 1,
        cancellable: false,
      );
      final bool saved = await _saf.saveBackup(
        sourcePath: result.path,
        suggestedName: _suggestedName(result),
      );
      if (!saved) return null;
      return _suggestedName(result);
    } on BackupCancelledException {
      throw PaperException(
        PaperErrorKind.cancelled,
        'Backup cancelled. Nothing was saved.',
      );
    } finally {
      if (temporary != null) {
        try {
          final File file = File(temporary);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // The work directory is disposable.
        }
      }
      state = null;
    }
  }

  Future<void> discardPreview(BackupPreview preview) async {
    try {
      final File file = File(preview.archivePath);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Import cache is disposable.
    }
  }

  Future<RestoreResult?> restore(BackupPreview preview) async {
    _cancelled = false;
    state = const BackupTask(
      kind: BackupTaskKind.restore,
      message: 'Preparing restore',
      fraction: 0,
    );
    try {
      final RestoreResult result = await _service.restore(
        preview: preview,
        currentSettings: ref.read(settingsProvider),
        isCancelled: () => _cancelled,
        onProgress: _onProgress(BackupTaskKind.restore),
      );
      ref.read(settingsProvider.notifier).reload();
      ref.read(documentRepositoryProvider).notifyChanged();
      ref.read(bookmarkRepositoryProvider).notifyChanged();
      ref.read(annotationRepositoryProvider).notifyChanged();
      ref.read(noteRepositoryProvider).notifyChanged();
      ref.read(taskRepositoryProvider).notifyChanged();
      ref.read(locationRepositoryProvider).notifyChanged();
      return result;
    } finally {
      try {
        final File file = File(preview.archivePath);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Import cache is disposable.
      }
      state = null;
    }
  }

  void Function(BackupProgress progress) _onProgress(BackupTaskKind kind) {
    return (BackupProgress progress) {
      state = BackupTask(
        kind: kind,
        message: _cancelled && progress.cancellable
            ? 'Stopping after the current file…'
            : progress.message,
        fraction: progress.fraction,
        cancellable: progress.cancellable && !_cancelled,
        cancelling: _cancelled && progress.cancellable,
      );
    };
  }

  String _suggestedName(BackupResult result) {
    final DateTime now = result.manifest.createdAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'PaperOS ${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}${two(now.minute)}.paperosbackup';
  }
}

final backupControllerProvider =
    NotifierProvider<BackupController, BackupTask?>(BackupController.new);
