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
import '../application/library_providers.dart';
import '../domain/document.dart';
import '../domain/library_models.dart';

/// The library: every document PaperOS owns, with its reading state.
///
/// This is the screen a launcher is judged on, so it is a plain list with a
/// strong sort and a per-row menu — no carousels, no covers, no grid. It
/// states honestly which formats are recognised but not yet readable, instead
/// of hiding them.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LibraryEntry>> entries = ref.watch(
      libraryEntriesProvider,
    );
    final LibraryQuery query = ref.watch(libraryQueryProvider);
    final ImportOutcome? outcome = ref.watch(importControllerProvider);

    return Scaffold(
      appBar: PaperTopBar(
        title: 'Library',
        subtitle: _subtitleFor(entries.value),
        leading: const _ImportButton(),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push(Routes.search),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: _LibraryControls(query: query),
        ),
      ),
      body: Column(
        children: <Widget>[
          if (outcome != null) _ImportBanner(outcome: outcome),
          Expanded(
            child: entries.when(
              loading: () => const PaperLoading(label: 'Reading your library'),
              error: (Object error, StackTrace stack) => PaperErrorView(
                message: error is PaperException
                    ? error.message
                    : 'Your library could not be read from storage.',
                onRetry: () => ref.invalidate(libraryEntriesProvider),
              ),
              data: (List<LibraryEntry> items) {
                if (items.isEmpty) {
                  return _emptyStateFor(query);
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: PaperSpace.xl),
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int index) {
                    final LibraryEntry entry = items[index];
                    return _DocumentRow(
                      entry: entry,
                      showRule: index != items.length - 1,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _subtitleFor(List<LibraryEntry>? entries) {
    if (entries == null) return null;
    if (entries.isEmpty) return null;
    return '${entries.length} document${entries.length == 1 ? '' : 's'}';
  }

  Widget _emptyStateFor(LibraryQuery query) {
    if (query.search.isNotEmpty) {
      return PaperEmptyState(
        title: 'No matches',
        message: 'Nothing in your library matches "${query.search}".',
        icon: Icons.search_off_outlined,
        action: PaperButton(
          label: 'Clear search',
          onPressed: () =>
              ref.read(libraryQueryProvider.notifier).setSearch(''),
        ),
      );
    }
    if (query.scope != LibraryScope.all) {
      return PaperEmptyState(
        title: 'Nothing here',
        message:
            'This filter is empty. Recent collects documents you have opened; '
            'Favourites keeps the ones you marked.',
        icon: Icons.menu_book_outlined,
        action: PaperButton(
          label: 'Show all',
          onPressed: () => ref
              .read(libraryQueryProvider.notifier)
              .setScope(LibraryScope.all),
        ),
      );
    }
    return PaperEmptyState(
      title: 'Your library is empty',
      message:
          'Import a PDF, EPUB or text file to start reading. PaperOS keeps a '
          'private copy, so the file stays readable even if you move the '
          'original.',
      icon: Icons.upload_file_outlined,
      action: PaperButton(
        label: 'Import a document',
        icon: Icons.add,
        onPressed: () =>
            ref.read(importControllerProvider.notifier).importFromPicker(),
      ),
    );
  }
}

/// The top-bar leading action is an import button rather than a back button,
/// because the library is a top-level destination and never a pushed screen.
class _ImportButton extends ConsumerStatefulWidget {
  const _ImportButton();

  @override
  ConsumerState<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends ConsumerState<_ImportButton> {
  bool _busy = false;

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final Document? imported = await ref
          .read(importControllerProvider.notifier)
          .importFromPicker();
      if (imported != null && mounted) {
        PaperToast.show(
          context,
          'Imported ${imported.title}',
          icon: Icons.check_outlined,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _busy ? null : _import,
      icon: _busy ? const PaperProgress() : const Icon(Icons.add),
      tooltip: 'Import a document',
    );
  }
}

class _LibraryControls extends ConsumerWidget {
  const _LibraryControls({required this.query});

  final LibraryQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);
    final LibraryQueryController controller = ref.read(
      libraryQueryProvider.notifier,
    );

    return Container(
      color: palette.canvas,
      padding: const EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        0,
        PaperSpace.gutter,
        PaperSpace.sm,
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: PaperSearchField(
                  hintText: 'Search titles or authors',
                  onChanged: controller.setSearch,
                ),
              ),
              const SizedBox(width: PaperSpace.xs),
              PopupMenuButton<LibrarySort>(
                tooltip: 'Sort library',
                icon: const Icon(Icons.sort),
                initialValue: query.sort,
                onSelected: controller.setSort,
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<LibrarySort>>[
                      for (final LibrarySort sort in LibrarySort.values)
                        PopupMenuItem<LibrarySort>(
                          value: sort,
                          child: Text(sort.label),
                        ),
                    ],
              ),
            ],
          ),
          const SizedBox(height: PaperSpace.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final LibraryScope scope in LibraryScope.values)
                  Padding(
                    padding: const EdgeInsets.only(right: PaperSpace.sm),
                    child: PaperChip(
                      label: scope.label,
                      selected: query.scope == scope,
                      onTap: () => controller.setScope(scope),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportBanner extends ConsumerWidget {
  const _ImportBanner({required this.outcome});

  final ImportOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = paperPalette(context);

    return Container(
      width: double.infinity,
      color: palette.inverseCanvas,
      padding: const EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        PaperSpace.md,
        PaperSpace.sm,
        PaperSpace.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            outcome.failed ? Icons.error_outline : Icons.check,
            size: 18,
            color: palette.inverseInk,
          ),
          const SizedBox(width: PaperSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  outcome.title,
                  style: type.meta.copyWith(
                    color: palette.inverseInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  outcome.message,
                  style: type.caption.copyWith(color: palette.inverseInk),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                ref.read(importControllerProvider.notifier).dismiss(),
            icon: Icon(Icons.close, size: 18, color: palette.inverseInk),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends ConsumerWidget {
  const _DocumentRow({required this.entry, required this.showRule});

  final LibraryEntry entry;
  final bool showRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Document document = entry.document;
    final PaperTypography type = PaperTypography.of(context);
    final bool canRead = DocumentFormat.isReadable(document.format);
    final bool missing = document.status == DocumentStatus.missing;

    final Widget row = PaperListTile(
      title: entry.primary,
      subtitle: entry.secondary,
      semanticLabel: '${entry.primary}, ${entry.secondary}',
      trailing: _RowTrailing(document: document, canRead: canRead),
      onTap: canRead && !missing
          ? () => context.push(Routes.readerPath(document.id))
          : null,
      onLongPress: () => _showRowMenu(context, ref),
    );

    return Column(
      children: <Widget>[
        if (entry.showProgress)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperSpace.gutter,
              0,
              PaperSpace.gutter,
              PaperSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PaperProgressBar(value: entry.progress),
                const SizedBox(height: PaperSpace.xs),
                Text(entry.progressLine, style: type.caption),
              ],
            ),
          ),
        row,
        if (showRule) const PaperRule(inset: PaperSpace.gutter),
      ],
    );
  }

  Future<void> _showRowMenu(BuildContext context, WidgetRef ref) async {
    final Document document = entry.document;
    final LibraryActions actions = ref.read(libraryActionsProvider);

    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: paperModalAnimationStyle(context),
      backgroundColor: paperPalette(context).canvas,
      barrierColor: paperPalette(context).ink.withValues(alpha: 0.32),
      shape: const RoundedRectangleBorder(),
      builder: (BuildContext sheetContext) {
        final PaperPalette palette = paperPalette(sheetContext);
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PaperSpace.gutter,
                  PaperSpace.lg,
                  PaperSpace.gutter,
                  PaperSpace.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      document.title,
                      style: PaperTypography.of(sheetContext).heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: PaperSpace.xs),
                    Text(
                      '${entry.secondary}\nAdded ${formatShortDate(document.addedAt)}',
                      style: PaperTypography.of(sheetContext).caption,
                    ),
                  ],
                ),
              ),
              const PaperRule(strong: true),
              PaperListTile(
                title: document.isFavorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                leading: Icon(
                  document.isFavorite ? Icons.star_outline : Icons.star_border,
                  size: 20,
                  color: palette.inkMuted,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  actions.toggleFavorite(document);
                },
              ),
              PaperListTile(
                title: 'Rename',
                leading: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: palette.inkMuted,
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final String? renamed = await showPaperTextPrompt(
                    context,
                    title: 'Rename',
                    label: 'Title',
                    initialValue: document.title,
                  );
                  if (renamed != null) await actions.rename(document, renamed);
                },
              ),
              PaperListTile(
                title: 'Remove from library',
                leading: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: palette.ink,
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final bool confirmed = await confirmDestructiveAction(
                    context,
                    title: 'Remove ${document.title}?',
                    message:
                        'The copy PaperOS made will be deleted. The original '
                        'file, if you still have it, is not touched.',
                    confirmLabel: 'Remove',
                  );
                  if (!confirmed) return;
                  try {
                    await actions.remove(document);
                    if (context.mounted) {
                      PaperToast.show(
                        context,
                        'Removed ${document.title}',
                        icon: Icons.delete_outline,
                      );
                    }
                  } on PaperException catch (error) {
                    if (!context.mounted) return;
                    PaperToast.show(
                      context,
                      error.message,
                      icon: Icons.error_outline,
                    );
                  }
                },
              ),
              const SizedBox(height: PaperSpace.sm),
            ],
          ),
        );
      },
    );
  }
}

class _RowTrailing extends ConsumerWidget {
  const _RowTrailing({required this.document, required this.canRead});

  final Document document;
  final bool canRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperTypography type = PaperTypography.of(context);
    final PaperPalette palette = paperPalette(context);

    if (document.status == DocumentStatus.missing) {
      return Text(
        'Missing',
        style: type.meta.copyWith(color: palette.inkFaint),
      );
    }
    if (!canRead) {
      // Honest, and specific: which format, and that it is not readable yet.
      return Text(
        '${document.format.label} · not yet readable',
        style: type.caption.copyWith(color: palette.inkFaint),
      );
    }
    if (document.isFavorite) {
      return Icon(Icons.star, size: 18, color: palette.ink);
    }
    return Icon(Icons.chevron_right, size: 18, color: palette.inkFaint);
  }
}
