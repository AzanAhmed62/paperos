import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/errors/paper_exception.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/ids.dart';
import '../../../shared/widgets/paper_widgets.dart';
import '../../../theme/paper_palette.dart';
import '../../../theme/paper_space.dart';
import '../../../theme/paper_typography.dart';
import '../application/notes_providers.dart';
import '../domain/note.dart';

/// The note editor.
///
/// A new note is a draft that exists only in memory until the user writes
/// something meaningful. The first meaningful autosave inserts one row; every
/// later save updates that same row. Leaving an untouched draft writes nothing.
/// Saves are serialised so an older asynchronous write can never overwrite a
/// newer revision, and leaving flushes the latest keystrokes before the route
/// is popped.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.noteId});

  /// Null for a new, unsaved draft.
  final String? noteId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _bodyFocus = FocusNode();

  Timer? _saveTimer;
  Note? _note;
  String? _draftId;
  bool _loaded = false;
  bool _suppressChanges = false;
  bool _leaving = false;
  bool _deleted = false;
  bool _saveFailed = false;

  /// Serialises writes. Each task captures the latest text when it runs, so a
  /// queued save always reflects the newest revision rather than the revision
  /// that existed when the timer fired.
  Future<void> _writeQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
    final String? id = widget.noteId;
    if (id == null) {
      _draftId = newLocalId();
      _loaded = true;
    } else {
      unawaited(_load(id));
    }
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

  Future<void> _load(String id) async {
    final Note? loaded = await ref.read(noteRepositoryProvider).findById(id);
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

  bool get _hasContent =>
      _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty;

  bool get _isDirty {
    final Note? note = _note;
    if (note == null) return _hasContent;
    return _title.text != note.title || _body.text != note.body;
  }

  void _onChanged() {
    if (_suppressChanges) return;
    _saveFailed = false;
    _scheduleSave();
    setState(() {});
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_save());
    });
  }

  /// Queues one save. The repository call runs only after every earlier save
  /// has finished, which makes overlapping debounce and Back flushes safe.
  Future<void> _save() {
    if (_deleted) return Future<void>.value();
    final Future<void> queued = _writeQueue.then((_) => _persistLatest());
    _writeQueue = queued;
    return queued;
  }

  Future<void> _persistLatest() async {
    if (_deleted || !mounted) return;
    final Note? note = _note;
    final String title = _title.text;
    final String body = _body.text;
    try {
      if (note == null) {
        if (title.trim().isEmpty && body.trim().isEmpty) return;
        final DateTime now = DateTime.now();
        final Note created = await ref
            .read(noteActionsProvider)
            .insert(
              Note(
                id: _draftId!,
                title: title,
                body: body,
                createdAt: now,
                updatedAt: now,
              ),
            );
        if (_deleted) {
          // Delete raced the insert. Remove the row that was just created
          // rather than leaving an orphan behind.
          await ref.read(noteActionsProvider).delete(created.id);
          return;
        }
        _note = created;
        _saveFailed = false;
        if (mounted) setState(() {});
        return;
      }
      if (title == note.title && body == note.body) return;
      final Note next = note.copyWith(
        title: title,
        body: body,
        updatedAt: DateTime.now(),
      );
      await ref.read(noteActionsProvider).save(next);
      _note = next;
      _saveFailed = false;
      if (mounted) setState(() {});
    } on PaperException {
      _saveFailed = true;
      if (mounted) setState(() {});
    } catch (_) {
      _saveFailed = true;
      if (mounted) setState(() {});
    }
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
    if (_saveFailed && _isDirty) {
      _leaving = false;
      PaperToast.show(
        context,
        'Your note could not be saved. Your text is still here.',
        icon: Icons.error_outline,
      );
      return;
    }
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
                  _StatusBar(
                    words: words,
                    dirty: dirty,
                    saveFailed: _saveFailed,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _deleteNote() async {
    final Note? note = _note;
    if (note == null && !_hasContent) {
      Navigator.of(context).maybePop();
      return;
    }
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: note == null ? 'Discard this draft?' : 'Delete this note?',
      message: note == null
          ? 'This note has not been saved yet. Discarding it cannot be undone.'
          : '"${note.displayTitle}" will be removed from this device.',
      confirmLabel: note == null ? 'Discard' : 'Delete',
    );
    if (!confirmed || !mounted) return;

    _deleted = true;
    _saveTimer?.cancel();
    // Let an in-flight insert or update finish, then delete the persisted row.
    await _writeQueue;
    try {
      final Note? persisted = _note;
      if (persisted != null) {
        await ref.read(noteActionsProvider).delete(persisted.id);
      }
    } on PaperException catch (error) {
      _deleted = false;
      if (mounted) {
        PaperToast.show(context, error.message, icon: Icons.error_outline);
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.words,
    required this.dirty,
    required this.saveFailed,
  });

  final int words;
  final bool dirty;
  final bool saveFailed;

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
          if (saveFailed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, size: 13, color: palette.inkMuted),
                const SizedBox(width: PaperSpace.xs),
                Text('Not saved', style: type.caption),
              ],
            )
          else if (dirty)
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
