import 'dart:async';

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
import '../application/notes_providers.dart';
import '../domain/note.dart';

/// The note editor.
///
/// Two fields and a word count. The draft is written to the database on a
/// debounce, and leaving the screen flushes the final keystrokes before the
/// route is popped.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _bodyFocus = FocusNode();

  Timer? _saveTimer;
  Note? _note;
  bool _loaded = false;
  bool _suppressChanges = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.removeListener(_onChanged);
    _body.removeListener(_onChanged);
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Note? loaded = await ref
        .read(noteRepositoryProvider)
        .findById(widget.noteId);
    if (!mounted) return;
    if (loaded == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _note = loaded;
    // Programmatic seeding must not look like a user edit: relying on the
    // controller listeners here would bump `updatedAt` merely by opening a
    // note and reorder the note list.
    _suppressChanges = true;
    _title.text = loaded.title;
    _body.text = loaded.body;
    _suppressChanges = false;
    setState(() => _loaded = true);
  }

  bool get _isDirty {
    final Note? note = _note;
    if (note == null) return false;
    return _title.text != note.title || _body.text != note.body;
  }

  void _onChanged() {
    if (_suppressChanges) return;
    _scheduleSave();
    setState(() {});
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    final Note? note = _note;
    if (note == null || !_isDirty) return;
    final Note next = note.copyWith(
      title: _title.text,
      body: _body.text,
      updatedAt: DateTime.now(),
    );
    await ref.read(noteActionsProvider).save(next);
    _note = next;
    if (mounted) setState(() {});
  }

  /// Flushes before leaving, so a back gesture never discards the last
  /// keystrokes.
  ///
  /// [Navigator.pop] is used rather than `maybePop` because `PopScope` above
  /// reports `canPop: false`; `maybePop` would invoke this callback again and
  /// the editor would never close.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _saveTimer?.cancel();
    await _save();
    if (!mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go(Routes.notes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);
    final String draftBody = _body.text.trim();
    final int words = draftBody.isEmpty
        ? 0
        : draftBody.split(RegExp(r'\s+')).length;
    final bool dirty = _isDirty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: PaperTopBar(
          title: 'Note',
          subtitle: _note == null
              ? null
              : 'Edited ${formatRelative(_note!.updatedAt, DateTime.now())}',
          onBack: _leave,
          actions: <Widget>[
            IconButton(
              onPressed: _bodyFocus.requestFocus,
              icon: const Icon(Icons.keyboard_alt_outlined),
              tooltip: 'Continue writing',
            ),
            IconButton(
              onPressed: _deleteNote,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete note',
            ),
          ],
        ),
        body: !_loaded
            ? const PaperLoading()
            : Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        PaperSpace.gutter,
                        PaperSpace.md,
                        PaperSpace.gutter,
                        PaperSpace.xxl,
                      ),
                      children: <Widget>[
                        TextField(
                          controller: _title,
                          style: type.screenTitleSmall,
                          cursorColor: palette.ink,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 1,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Title',
                            hintStyle: type.screenTitleSmall.copyWith(
                              color: palette.inkFaint,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: PaperSpace.sm,
                            ),
                          ),
                        ),
                        const PaperRule(),
                        const SizedBox(height: PaperSpace.md),
                        TextField(
                          controller: _body,
                          focusNode: _bodyFocus,
                          style: type.body,
                          cursorColor: palette.ink,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
                          minLines: 12,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Start writing.',
                            hintStyle: type.body.copyWith(
                              color: palette.inkFaint,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBar(words: words, dirty: dirty),
                ],
              ),
      ),
    );
  }

  Future<void> _deleteNote() async {
    final Note? note = _note;
    if (note == null) return;
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete this note?',
      message: '"${note.displayTitle}" will be removed from this device.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    _saveTimer?.cancel();
    await ref.read(noteActionsProvider).delete(note.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.words, required this.dirty});

  final int words;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final PaperPalette palette = paperPalette(context);
    final PaperTypography type = PaperTypography.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.rule)),
      ),
      padding: EdgeInsets.fromLTRB(
        PaperSpace.gutter,
        PaperSpace.sm,
        PaperSpace.gutter,
        MediaQuery.viewInsetsOf(context).bottom + PaperSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(words == 1 ? '1 word' : '$words words', style: type.caption),
          const Spacer(),
          if (dirty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.circle, size: 6, color: palette.inkFaint),
                const SizedBox(width: PaperSpace.xs + PaperSpace.xs),
                Text('Saving…', style: type.caption),
              ],
            ),
        ],
      ),
    );
  }
}
