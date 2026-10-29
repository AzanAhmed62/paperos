import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/notes/data/note_repository.dart';
import 'package:paperos/features/notes/domain/note.dart';
import 'package:paperos/features/notes/presentation/note_editor_screen.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
}
