import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/errors/paper_exception.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/notes/data/note_repository.dart';
import 'package:paperos/features/notes/domain/note.dart';
import 'package:paperos/features/notes/presentation/note_editor_screen.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FailingInsertRepository extends NoteRepository {
  _FailingInsertRepository(super.opener);

  @override
  Future<Note> insert(Note note) async {
    throw const PaperException.storage('Simulated note save failure.');
  }
}

/// Holds the first insert open so a delete can race it deterministically.
class _SlowInsertRepository extends NoteRepository {
  _SlowInsertRepository(super.opener);

  final Completer<void> gate = Completer<void>();
  final Completer<void> started = Completer<void>();

  @override
  Future<Note> insert(Note note) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    return super.insert(note);
  }
}

/// Regression coverage for the note editor's autosave contract:
/// opening a note must not write, and leaving must flush the last edit.
void main() {
  sqfliteFfiInit();

  late AppDatabaseOpener opener;
  late NoteRepository repository;
  late Note note;

  setUp(() async {
    opener = AppDatabaseOpener(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = NoteRepository(opener);
    note = await repository.create(
      title: 'Reading list',
      body: 'Paper and ink.',
    );
  });

  tearDown(() async {
    await repository.dispose();
    await (await opener.database).close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Database reads need the real event loop, which the widget tester's
  /// fake clock otherwise withholds.
  Future<Note> readNote(WidgetTester tester) async {
    final Note? read = await tester.runAsync<Note?>(
      () => repository.findById(note.id),
    );
    return read!;
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(opener)],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        NoteEditorScreen(noteId: note.id),
                  ),
                ),
                child: const Text('Open note'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(find.text('Paper and ink.'), findsOneWidget);
  }

  Future<void> openDraft(
    WidgetTester tester, {
    NoteRepository? repositoryOverride,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(opener),
          if (repositoryOverride != null)
            noteRepositoryProvider.overrideWithValue(repositoryOverride),
        ],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const NoteEditorScreen(),
                  ),
                ),
                child: const Text('New note'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('New note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
  }

  Future<int> noteCount(WidgetTester tester) async {
    return await tester.runAsync(() => repository.count()) ?? -1;
  }

  Future<List<Note>> allNotes(WidgetTester tester) async {
    return (await tester.runAsync(() => repository.list()))!;
  }

  testWidgets('opening a note does not mark it as edited', (
    WidgetTester tester,
  ) async {
    final Note before = await readNote(tester);

    await openEditor(tester);

    // Let the debounce elapse. A controller listener firing during load would
    // schedule a write and bump updatedAt even though nothing was typed.
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);

    final Note after = await readNote(tester);
    expect(after.updatedAt, before.updatedAt);
    expect(find.text('Note'), findsOneWidget);
  });

  testWidgets('back closes an unchanged note without writing', (
    WidgetTester tester,
  ) async {
    final Note before = await readNote(tester);
    await openEditor(tester);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('Open note'), findsOneWidget);
    final Note after = await readNote(tester);
    expect(after.updatedAt, before.updatedAt);
  });

  testWidgets('back flushes the final keystrokes before closing', (
    WidgetTester tester,
  ) async {
    await openEditor(tester);

    await tester.enterText(
      find.byType(TextField).at(1),
      'The last line is saved.',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('Open note'), findsOneWidget);
    final Note after = await readNote(tester);
    expect(after.body, 'The last line is saved.');
    expect(after.updatedAt.isAfter(note.updatedAt), isTrue);
  });

  testWidgets('an untouched draft never creates a note', (
    WidgetTester tester,
  ) async {
    await openDraft(tester);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);

    expect(await noteCount(tester), 1);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('New note'), findsOneWidget);
    expect(await noteCount(tester), 1);
  });

  testWidgets('a whitespace-only draft is discarded without a row', (
    WidgetTester tester,
  ) async {
    await openDraft(tester);

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.enterText(find.byType(TextField).at(1), '\n  \n');
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);

    expect(await noteCount(tester), 1);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('New note'), findsOneWidget);
    expect(await noteCount(tester), 1);
  });

  testWidgets('a title-only draft inserts once and updates in place', (
    WidgetTester tester,
  ) async {
    await openDraft(tester);

    await tester.enterText(find.byType(TextField).first, 'Only a title');
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);

    expect(await noteCount(tester), 2);
    final Note titled = (await allNotes(tester))
        .firstWhere((Note candidate) => candidate.title == 'Only a title');
    expect(titled.body, isEmpty);

    await tester.enterText(find.byType(TextField).at(1), 'Body arrives later.');
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);

    // The second save updates the same row; it must not insert a duplicate.
    expect(await noteCount(tester), 2);
    final List<Note> notes = await allNotes(tester);
    final Note updated = notes.firstWhere(
      (Note candidate) => candidate.id == titled.id,
    );
    expect(updated.body, 'Body arrives later.');
  });

  testWidgets('a body-only draft inserts once with an empty title', (
    WidgetTester tester,
  ) async {
    await openDraft(tester);

    await tester.enterText(
      find.byType(TextField).at(1),
      'Just a body line, no title.',
    );
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);

    expect(await noteCount(tester), 2);
    final Note saved = (await allNotes(tester))
        .firstWhere((Note candidate) => candidate.title.isEmpty);
    expect(saved.body, 'Just a body line, no title.');
  });

  testWidgets('rapid edits persist the latest revision, not an older one', (
    WidgetTester tester,
  ) async {
    await openDraft(tester);

    await tester.enterText(find.byType(TextField).first, 'Draft one');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField).at(1), 'First body');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.enterText(find.byType(TextField).at(1), 'Latest body');
    await tester.pump(const Duration(milliseconds: 800));
    await settle(tester);

    expect(await noteCount(tester), 2);
    final Note saved = (await allNotes(tester))
        .firstWhere((Note candidate) => candidate.title == 'Draft one');
    expect(saved.body, 'Latest body');
  });

  testWidgets('deleting during a pending insert leaves no orphan row', (
    WidgetTester tester,
  ) async {
    final _SlowInsertRepository slow = _SlowInsertRepository(opener);
    addTearDown(slow.dispose);
    await openDraft(tester, repositoryOverride: slow);

    await tester.enterText(
      find.byType(TextField).at(1),
      'Delete me before the insert lands.',
    );
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    await tester.runAsync(() => slow.started.future);

    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this draft?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pump();

    // The insert is still in flight, so the delete has nothing to remove yet.
    expect(await noteCount(tester), 1);

    await tester.runAsync(() async {
      slow.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);

    // The raced insert was rolled back; the draft did not become a note.
    expect(await noteCount(tester), 1);
    expect(find.text('New note'), findsOneWidget);
  });

  testWidgets('a failed first save keeps the draft open with its text', (
    WidgetTester tester,
  ) async {
    final _FailingInsertRepository failing = _FailingInsertRepository(opener);
    addTearDown(failing.dispose);
    await openDraft(tester, repositoryOverride: failing);

    await tester.enterText(
      find.byType(TextField).at(1),
      'This text must survive a failed save.',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    // Leaving is blocked, the text is still on screen, and nothing was written.
    expect(find.text('New note'), findsNothing);
    expect(find.text('This text must survive a failed save.'), findsOneWidget);
    expect(
      find.text('Your note could not be saved. Your text is still here.'),
      findsOneWidget,
    );
    expect(find.text('Not saved'), findsOneWidget);
    expect(await noteCount(tester), 1);
  });
}
