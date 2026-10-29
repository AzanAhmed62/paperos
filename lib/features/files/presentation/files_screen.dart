import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/utils/date_format.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../../library/application/library_providers.dart';
import '../../library/domain/document.dart';
import '../application/files_providers.dart';
import '../domain/browsed_entry.dart';

/// Files: the folders the user has shared with PaperOS.
///
/// Android 11+ will not let an app roam the filesystem, and PaperOS refuses to
/// ask for `MANAGE_EXTERNAL_STORAGE` to pretend otherwise. So this is not a
/// general file manager: it is a browser over the specific folders the user
/// granted through the system picker. Directories open in place, supported
/// documents are copied in and opened, and everything else is shown honestly as
/// something PaperOS cannot read yet.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  /// The path of folders descended into, within the current location. Empty
  /// means "show the list of granted folders".
  final List<_BrowseStep> _steps = <_BrowseStep>[];

  /// Uri of the entry currently being copied into the library, if any.
  String? _openingUri;

  @override
  Widget build(BuildContext context) {
    final _BrowseStep? current = _steps.isEmpty ? null : _steps.last;

    return PopScope(
      canPop: _steps.isEmpty,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _steps.isNotEmpty) {
          setState(() => _steps.removeLast());
        }
      },
      child: Scaffold(
        appBar: PaperTopBar(
          title: 'Files',
          subtitle: current?.label ?? 'Folders you have added',
          leading: _steps.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  onPressed: () => setState(() => _steps.removeLast()),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                ),
          actions: <Widget>[
            IconButton(
              onPressed: _addFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'Add a folder',
            ),
          ],
        ),
        body: current == null ? _locationsView() : _childrenView(current),
      ),
    );
  }

  // --------------------------------------------------------------- locations

  Widget _locationsView() {
    final AsyncValue<List<BrowsedLocation>> locations = ref.watch(
      locationsProvider,
    );

    return locations.when(
      loading: () => const PaperLoading(),
      error: (Object error, StackTrace stack) => PaperErrorView(
        message: 'Your folders could not be read from storage.',
        onRetry: () => ref.invalidate(locationsProvider),
      ),
      data: (List<BrowsedLocation> all) {
        if (all.isEmpty) {
          return PaperEmptyState(
            title: 'No folders yet',
            message:
                'Add a folder and PaperOS can list its documents. '
                'Nothing outside the folders you choose is ever read.',
            icon: Icons.folder_open_outlined,
            action: PaperButton(
              label: 'Add a folder',
              icon: Icons.add,
              onPressed: _addFolder,
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: PaperSpace.xxl),
          itemCount: all.length,
          itemBuilder: (BuildContext context, int index) {
            final BrowsedLocation location = all[index];
            return _FolderTile(
              label: location.label,
              subtitle: 'Tap to browse',
              onTap: () => setState(() {
                _steps
                  ..clear()
                  ..add(
                    _BrowseStep(
                      location: location,
                      directoryUri: null,
                      label: location.label,
                    ),
                  );
              }),
              onLongPress: () => _removeLocation(location),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------- children

  Widget _childrenView(_BrowseStep step) {
    final BrowseRequest request = BrowseRequest(
      location: step.location,
      directoryUri: step.directoryUri,
    );
    final AsyncValue<List<BrowsedEntry>> children = ref.watch(
      folderChildrenProvider(request),
    );

    return children.when(
      loading: () => const PaperLoading(),
      error: (Object error, StackTrace stack) => PaperErrorView(
        title: 'This folder could not be opened',
        message: error is PaperException
            ? error.message
            : 'PaperOS could not list this folder.',
        onRetry: () => ref.invalidate(folderChildrenProvider(request)),
      ),
      data: (List<BrowsedEntry> entries) {
        if (entries.isEmpty) {
          return const PaperEmptyState(
            title: 'This folder is empty',
            message: 'There is nothing here for PaperOS to show.',
            icon: Icons.folder_open_outlined,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: PaperSpace.xxl),
          itemCount: entries.length,
          itemBuilder: (BuildContext context, int index) {
            final BrowsedEntry entry = entries[index];
            return _EntryTile(
              entry: entry,
              busy: _openingUri == entry.uri,
              onTap: () => _openEntry(step, entry),
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------------------- actions

  Future<void> _addFolder() async {
    try {
      final BrowsedLocation? added = await ref
          .read(locationActionsProvider)
          .addLocation();
      if (!mounted || added == null) return;
      PaperToast.show(
        context,
        'Added "${added.label}".',
        icon: Icons.folder_outlined,
      );
    } on PaperException catch (error) {
      if (!mounted) return;
      PaperToast.show(context, error.message);
    }
  }

  Future<void> _removeLocation(BrowsedLocation location) async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Remove this folder?',
      message:
          '"${location.label}" will no longer appear in Files. '
          'Documents you already imported stay in your library.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    await ref.read(locationActionsProvider).removeLocation(location);
    if (!mounted) return;
    PaperToast.show(context, 'Removed "${location.label}".');
  }

  Future<void> _openEntry(_BrowseStep step, BrowsedEntry entry) async {
    if (entry.isDirectory) {
      setState(() {
        _steps.add(
          _BrowseStep(
            location: step.location,
            directoryUri: entry.uri,
            label: entry.name,
          ),
        );
      });
      return;
    }

    if (!entry.isReadable) {
      PaperToast.show(
        context,
        entry.format == DocumentFormat.unknown
            ? 'PaperOS cannot open ${entry.name}.'
            : 'PaperOS recognises ${entry.format.label} but does not open it yet.',
      );
      return;
    }

    setState(() => _openingUri = entry.uri);
    final Document? document = await ref
        .read(importControllerProvider.notifier)
        .importBrowsedEntry(entry);
    if (!mounted) return;
    setState(() => _openingUri = null);

    if (document != null) {
      context.push(Routes.readerPath(document.id));
    } else {
      final ImportOutcome? outcome = ref.read(importControllerProvider);
      PaperToast.show(
        context,
        outcome?.message ?? 'That file could not be opened.',
      );
    }
  }
}

/// One level inside a location.
class _BrowseStep {
  const _BrowseStep({
    required this.location,
    required this.directoryUri,
    required this.label,
  });

  final BrowsedLocation location;

  /// Null means the location's root.
  final String? directoryUri;
  final String label;
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    return Column(
      children: <Widget>[
        PaperListTile(
          title: label,
          subtitle: subtitle,
          leading: Icon(
            Icons.folder_outlined,
            size: 22,
            color: palette.inkMuted,
          ),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
        const PaperRule(inset: PaperSpace.gutter),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.busy,
    required this.onTap,
  });

  final BrowsedEntry entry;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    final IconData icon = entry.isDirectory
        ? Icons.folder_outlined
        : entry.isReadable
        ? Icons.description_outlined
        : Icons.insert_drive_file_outlined;
    final Color iconColor = entry.isDirectory || entry.isReadable
        ? palette.inkMuted
        : palette.inkFaint;

    return Column(
      children: <Widget>[
        PaperListTile(
          title: entry.name,
          subtitle: _subtitle(),
          leading: Icon(icon, size: 22, color: iconColor),
          trailing: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : entry.isDirectory
              ? const Icon(Icons.chevron_right, size: 18)
              : entry.isReadable
              ? null
              : Text('Not supported', style: type.caption),
          onTap: busy ? null : onTap,
        ),
        const PaperRule(inset: PaperSpace.gutter),
      ],
    );
  }

  String _subtitle() {
    if (entry.isDirectory) return 'Folder';
    final List<String> facts = <String>[entry.format.label];
    final int? size = entry.byteSize;
    if (size != null && size > 0) facts.add(formatBytes(size));
    final DateTime? modified = entry.lastModified;
    if (modified != null) facts.add('Changed ${formatDayMonth(modified)}');
    return facts.join(' · ');
  }
}
