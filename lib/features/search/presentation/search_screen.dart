import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/utils/date_format.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../../library/domain/document.dart';
import '../../notes/domain/note.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../tasks/domain/task.dart';

enum SearchHitKind { document, note, task }

/// One search result.
///
/// Carries identifiers rather than a callback so that the provider stays a pure
/// function of the query string — which is what makes it testable, and what
/// stops a stale closure from capturing a defunct [BuildContext].
@immutable
class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.dueDate,
  });

  final SearchHitKind kind;
  final String id;
  final String title;
  final String subtitle;

  /// Only set for task hits. Opening a dated task must select its day first;
  /// otherwise the checklist appears empty and the hit looks lost.
  final DateTime? dueDate;
}

@immutable
class SearchResults {
  const SearchResults({required this.query, required this.hits});

  final String query;
  final List<SearchHit> hits;

  bool get isEmpty => hits.isEmpty;
}

/// How many results of each kind are shown.
///
/// Bounded so that a one-letter query on a large library cannot turn the search
/// screen into a several-thousand-row list.
const int kSearchLimit = 25;

/// Searches documents, notes and tasks at once.
///
/// Substring matching, not fuzzy search: over a personal library this is
/// instant, predictable and explainable, and a user who cannot predict why a
/// result appeared stops trusting the search box.
final searchResultsProvider = FutureProvider.autoDispose
    .family<SearchResults, String>((Ref ref, String query) async {
      final String needle = query.trim().toLowerCase();
      if (needle.isEmpty) {
        return const SearchResults(query: '', hits: <SearchHit>[]);
      }

      final List<SearchHit> hits = <SearchHit>[];

      final List<Document> documents = await ref
          .watch(documentRepositoryProvider)
          .list(query: needle, limit: kSearchLimit);
      for (final Document document in documents) {
        hits.add(
          SearchHit(
            kind: SearchHitKind.document,
            id: document.id,
            title: document.title,
            subtitle: _documentSubtitle(document),
          ),
        );
      }

      final List<Note> notes = await ref
          .watch(noteRepositoryProvider)
          .list(query: needle, limit: kSearchLimit);
      for (final Note note in notes) {
        hits.add(
          SearchHit(
            kind: SearchHitKind.note,
            id: note.id,
            title: note.displayTitle,
            subtitle:
                'Note · edited ${formatRelative(note.updatedAt, DateTime.now())}',
          ),
        );
      }

      // The tasks table has no full-text index; a personal task list is small
      // enough that filtering the rows in memory is cheaper than a new index.
      final List<Task> tasks = await ref
          .watch(taskRepositoryProvider)
          .list(limit: 500);
      int taskHits = 0;
      for (final Task task in tasks) {
        if (taskHits >= kSearchLimit) break;
        if (!task.title.toLowerCase().contains(needle)) continue;
        taskHits++;
        hits.add(
          SearchHit(
            kind: SearchHitKind.task,
            id: task.id,
            title: task.title,
            subtitle: task.isDone
                ? 'Task · done'
                : task.dueDate == null
                ? 'Task · no date'
                : 'Task · due ${formatDayMonth(task.dueDate!)}',
            dueDate: task.dueDate,
          ),
        );
      }

      return SearchResults(query: needle, hits: hits);
    });

String _documentSubtitle(Document document) {
  final List<String> parts = <String>[document.format.label];
  if (document.pageCount != null && document.pageCount! > 0) {
    parts.add('${document.pageCount} pages');
  }
  parts.add(
    document.lastOpenedAt != null
        ? 'opened ${formatRelative(document.lastOpenedAt!, DateTime.now())}'
        : 'added ${formatDayMonth(document.addedAt)}',
  );
  return parts.join(' · ');
}

/// Search across documents, notes and tasks.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SearchResults> results = ref.watch(
      searchResultsProvider(_query),
    );
    final bool idle = _query.trim().isEmpty;

    return Scaffold(
      appBar: PaperTopBar(
        title: 'Search',
        onBack: () => Navigator.of(context).maybePop(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperSpace.gutter,
              0,
              PaperSpace.gutter,
              PaperSpace.sm,
            ),
            child: PaperSearchField(
              hintText: 'Documents, notes, tasks',
              autofocus: true,
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
        ),
      ),
      body: idle
          ? const PaperEmptyState(
              title: 'Search everything',
              message:
                  'Document titles, note text and tasks are searched at '
                  'once. Nothing leaves this device.',
              icon: Icons.search,
            )
          : results.when(
              loading: () => const PaperLoading(),
              error: (Object error, StackTrace stack) => PaperErrorView(
                message: 'The search could not be completed.',
                onRetry: () => ref.invalidate(searchResultsProvider(_query)),
              ),
              data: (SearchResults data) {
                if (data.isEmpty) {
                  return PaperEmptyState(
                    title: 'No matches',
                    message:
                        'Nothing in your documents, notes or tasks contains '
                        '"${data.query}".',
                    icon: Icons.search_off_outlined,
                  );
                }
                return _Results(query: data.query, hits: data.hits);
              },
            ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.hits});

  final String query;
  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: PaperSpace.xxl),
      itemCount: hits.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              PaperSpace.gutter,
              PaperSpace.lg,
              PaperSpace.gutter,
              PaperSpace.sm,
            ),
            child: Text(
              '${hits.length} result${hits.length == 1 ? '' : 's'} for "$query"',
              style: type.caption,
            ),
          );
        }
        final SearchHit hit = hits[index - 1];
        return Column(
          children: <Widget>[
            PaperListTile(
              title: hit.title,
              subtitle: hit.subtitle,
              leading: Icon(
                _iconFor(hit.kind),
                size: 20,
                color: palette.inkMuted,
              ),
              trailing: const Icon(Icons.north_west, size: 16),
              onTap: () => _open(context, ref, hit),
            ),
            if (index != hits.length) const PaperRule(inset: PaperSpace.gutter),
          ],
        );
      },
    );
  }

  static IconData _iconFor(SearchHitKind kind) => switch (kind) {
    SearchHitKind.document => Icons.menu_book_outlined,
    SearchHitKind.note => Icons.edit_note_outlined,
    SearchHitKind.task => Icons.check_circle_outline,
  };

  void _open(BuildContext context, WidgetRef ref, SearchHit hit) {
    switch (hit.kind) {
      case SearchHitKind.document:
        context.push(Routes.readerPath(hit.id));
      case SearchHitKind.note:
        context.push(Routes.noteEditorPath(hit.id));
      case SearchHitKind.task:
        // A task has no detail screen: the Tasks checklist is where it lives.
        // A dated task only appears on its own day, so move the checklist
        // there before showing it.
        final TaskDayController day = ref.read(taskDayProvider.notifier);
        final DateTime? due = hit.dueDate;
        if (due == null) {
          day.resetToToday();
        } else {
          day.select(due);
        }
        context.push(Routes.tasks);
    }
  }
}
