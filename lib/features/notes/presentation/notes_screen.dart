import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/utils/date_format.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';

/// Notes: plain local text.
///
/// No folders, no tags, no formatting. A note list that is a list, because the
/// value of a note is in the writing, not in the filing.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Note>> notes = ref.watch(notesProvider);
    final DateTime now = DateTime.now();

    final List<Note> visible =
        notes.value
            ?.where(
              (Note note) =>
                  _query.isEmpty ||
                  note.title.toLowerCase().contains(_query) ||
                  note.body.toLowerCase().contains(_query),
            )
            .toList(growable: false) ??
        const <Note>[];

    return Scaffold(
      appBar: PaperTopBar(
        title: 'Notes',
        subtitle: notes.value == null
            ? null
            : '${notes.value!.length} note${notes.value!.length == 1 ? '' : 's'}',
        leading: IconButton(
          onPressed: _create,
          icon: const Icon(Icons.add),
          tooltip: 'New note',
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push(Routes.search),
            icon: const Icon(Icons.search),
            tooltip: 'Search everything',
          ),
        ],
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
              controller: _search,
              hintText: 'Filter notes',
              onChanged: (String value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      body: notes.when(
        loading: () => const PaperLoading(),
        error: (Object error, StackTrace stack) => PaperErrorView(
          message: 'Your notes could not be read from storage.',
          onRetry: () => ref.invalidate(notesProvider),
        ),
        data: (List<Note> all) {
          if (all.isEmpty) {
            return PaperEmptyState(
              title: 'No notes yet',
              message:
                  'Notes are stored on this device only. Nothing is sent '
                  'anywhere.',
              icon: Icons.edit_note_outlined,
              action: PaperButton(
                label: 'Write a note',
                icon: Icons.add,
                onPressed: _create,
              ),
            );
          }
          if (visible.isEmpty) {
            return PaperEmptyState(
              title: 'No matches',
              message: 'No note contains "$_query".',
              icon: Icons.search_off_outlined,
              action: PaperButton(
                label: 'Clear filter',
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: PaperSpace.xxl),
            itemCount: visible.length,
            itemBuilder: (BuildContext context, int index) {
              final Note note = visible[index];
              return PaperListTile(
                title: note.displayTitle,
                subtitle: note.preview.isEmpty
                    ? 'Edited ${formatRelative(note.updatedAt, now)}'
                    : note.preview,
                semanticLabel:
                    '${note.displayTitle}, edited ${formatRelative(note.updatedAt, now)}',
                trailing: Text(
                  formatCompactDate(note.updatedAt),
                  style: PaperTypography.of(context).caption,
                ),
                onTap: () => context.push(Routes.noteEditorPath(note.id)),
                onLongPress: () => _confirmDelete(note),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create() async {
    final Note created = await ref.read(noteActionsProvider).create();
    if (!mounted) return;
    await context.push(Routes.noteEditorPath(created.id));
  }

  Future<void> _confirmDelete(Note note) async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete this note?',
      message:
          '"${note.displayTitle}" will be removed from this device. This '
          'cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    await ref.read(noteActionsProvider).delete(note.id);
    if (!mounted) return;
    PaperToast.show(context, 'Note deleted', icon: Icons.delete_outline);
  }
}
