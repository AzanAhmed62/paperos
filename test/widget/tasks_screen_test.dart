import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/tasks/presentation/tasks_screen.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabaseOpener opener;

  setUp(() {
    opener = AppDatabaseOpener(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await (await opener.database).close();
  });

  /// Gives the real sqflite-ffi work a chance to finish, then lets the
  /// resulting provider rebuild reach the widget tree.
  ///
  /// A single runAsync/pump pair is not enough: the first pump flushes the
  /// provider invalidation, which starts another database read that only the
  /// next real-async turn can complete.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpTasks(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(opener)],
        child: MaterialApp(
          theme: PaperTheme.build(style: PaperStyle.white),
          home: const TasksScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('starts with an empty checklist for today', (
    WidgetTester tester,
  ) async {
    await pumpTasks(tester);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('No tasks for this day'), findsOneWidget);
  });

  testWidgets('adds a task from the composer and completes it', (
    WidgetTester tester,
  ) async {
    await pumpTasks(tester);

    await tester.enterText(find.byType(TextField), 'Buy ink');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await settle(tester);

    expect(find.text('Buy ink'), findsWidgets);

    // Ticking the box records it as done.
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);

    expect(find.text('1 of 1 done'), findsOneWidget);
  });
}
