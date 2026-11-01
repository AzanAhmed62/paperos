import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/paper_exception.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../application/backup_controller.dart';
import '../data/backup_service.dart';
import '../domain/backup_manifest.dart';

/// Settings block for complete local backup and replacement restore.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  bool _selecting = false;

  @override
  Widget build(BuildContext context) {
    final BackupTask? task = ref.watch(backupControllerProvider);
    final BackupController controller = ref.read(
      backupControllerProvider.notifier,
    );
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = paperPalette(context);
    final bool busy = task != null || _selecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperSpace.gutter,
            PaperSpace.xl,
            PaperSpace.gutter,
            PaperSpace.sm,
          ),
          child: Text('Backup and restore', style: type.sectionLabel),
        ),
        PaperSettingRow(
          label: 'Create a backup',
          subtitle:
              'One .paperosbackup file with every book, cover, bookmark, '
              'annotation, note, task, setting and folder. Save it wherever '
              'you choose.',
          onTap: busy ? null : _createBackup,
        ),
        const PaperRule(inset: PaperSpace.gutter),
        PaperSettingRow(
          label: 'Restore from a backup',
          subtitle:
              'Replaces the current library completely. PaperOS validates the '
              'archive and keeps a private safety snapshot first.',
          onTap: busy ? null : _chooseRestore,
        ),
        if (_selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperSpace.gutter,
              PaperSpace.md,
              PaperSpace.gutter,
              0,
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: PaperSpace.md),
                Text('Checking the archive…', style: type.caption),
              ],
            ),
          ),
        if (task != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperSpace.gutter,
              PaperSpace.md,
              PaperSpace.gutter,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(task.message, style: type.caption),
                const SizedBox(height: PaperSpace.sm),
                LinearProgressIndicator(
                  value: task.fraction,
                  minHeight: 3,
                  color: palette.ink,
                  backgroundColor: palette.rule,
                ),
                if (task.cancellable && !task.cancelling)
                  Align(
                    alignment: Alignment.centerRight,
                    child: PaperButton(
                      label: 'Cancel',
                      onPressed: controller.cancel,
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperSpace.gutter,
            PaperSpace.sm,
            PaperSpace.gutter,
            0,
          ),
          child: Text(
            'Backups are unencrypted. Treat the saved file like the books '
            'themselves: anyone who can open it can read your library.',
            style: type.caption,
          ),
        ),
      ],
    );
  }

  Future<void> _createBackup() async {
    try {
      final String? saved = await ref
          .read(backupControllerProvider.notifier)
          .createBackup();
      if (!mounted) return;
      if (saved != null) {
        PaperToast.show(
          context,
          'Backup saved as $saved',
          icon: Icons.archive_outlined,
        );
      }
    } on PaperException catch (error) {
      if (!mounted) return;
      PaperToast.show(
        context,
        error.message,
        icon: error.kind == PaperErrorKind.cancelled
            ? Icons.close
            : Icons.error_outline,
      );
    }
  }

  Future<void> _chooseRestore() async {
    setState(() => _selecting = true);
    BackupPreview? preview;
    try {
      preview = await ref
          .read(backupControllerProvider.notifier)
          .chooseRestoreFile();
      if (!mounted || preview == null) return;
      setState(() => _selecting = false);
      final bool confirmed = await _confirmRestore(preview);
      if (!confirmed) {
        await ref
            .read(backupControllerProvider.notifier)
            .discardPreview(preview);
        return;
      }
      final RestoreResult? result = await ref
          .read(backupControllerProvider.notifier)
          .restore(preview);
      if (!mounted || result == null) return;
      PaperToast.show(
        context,
        'Restored ${result.counts.documents} documents. A safety snapshot '
        'is kept in PaperOS storage.',
        icon: Icons.restore,
      );
    } on PaperException catch (error) {
      if (!mounted) return;
      PaperToast.show(
        context,
        error.message,
        icon: error.kind == PaperErrorKind.cancelled
            ? Icons.close
            : Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<bool> _confirmRestore(BackupPreview preview) async {
    final BackupManifest manifest = preview.manifest;
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final BackupCounts counts = manifest.counts;    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: palette.ink.withValues(alpha: 0.32),
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(),
          insetPadding: const EdgeInsets.all(PaperSpace.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(PaperSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Replace this library?', style: type.heading),
                  const SizedBox(height: PaperSpace.sm),
                  Text(
                    'This backup was made ${_relativeDate(manifest.createdAt)} '
                    'with PaperOS ${manifest.appVersion}.',
                    style: type.body,
                  ),
                  const SizedBox(height: PaperSpace.lg),
                  _PreviewLine(label: 'Documents', value: '${counts.documents}'),
                  _PreviewLine(
                    label: 'Bookmarks',
                    value: '${counts.bookmarks}',
                  ),
                  _PreviewLine(
                    label: 'Annotations',
                    value: '${counts.annotations}',
                  ),
                  _PreviewLine(label: 'Notes', value: '${counts.notes}'),
                  _PreviewLine(label: 'Tasks', value: '${counts.tasks}'),
                  _PreviewLine(
                    label: 'Folders',
                    value: '${counts.locations}',
                  ),
                  _PreviewLine(
                    label: 'Library files',
                    value: _bytes(manifest.libraryBytes),
                  ),
                  const SizedBox(height: PaperSpace.lg),
                  Text(
                    'Everything currently in PaperOS — documents, progress, '
                    'bookmarks, annotations, notes, tasks, settings and folder '
                    'references — will be replaced by this backup. Nothing is '
                    'deleted until every checksum and database row has passed '
                    'validation. A private safety snapshot is kept.',
                    style: type.caption,
                  ),
                  if (manifest.warnings.isNotEmpty) ...<Widget>[
                    const SizedBox(height: PaperSpace.md),
                    for (final String warning in manifest.warnings)
                      Text('• $warning', style: type.caption),
                  ],
                  const SizedBox(height: PaperSpace.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      PaperButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                      const SizedBox(width: PaperSpace.sm),
                      PaperButton(
                        label: 'Replace library',
                        emphasised: true,
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return confirmed ?? false;
  }

  String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _date(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String _relativeDate(DateTime utc) {
    final Duration age = DateTime.now().toUtc().difference(utc.toUtc());
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes} minutes ago';
    if (age.inDays < 1) return '${age.inHours} hours ago';
    if (age.inDays == 1) return 'yesterday';
    return _date(utc.toLocal());
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final PaperTypography type = PaperTypography.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: PaperSpace.xs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: type.caption)),
          Text(value, style: type.body),
        ],
      ),
    );
  }
}
