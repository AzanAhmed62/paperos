import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/search/presentation/search_screen.dart';
import 'package:paperos/features/tasks/application/tasks_providers.dart';
import 'package:paperos/features/tasks/data/task_repository.dart';
import 'package:paperos/theme/paper_palette.dart';
import 'package:paperos/theme/paper_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A task search hit must land on the checklist day that actually contains
/// the task, not on whichever day the Tasks screen happened to be showing.
void main() {
  sqfliteFfiInit();

  late AppDatabaseOpener opener;
  late TaskRepository repository;
  final DateTime due = DateTime(2026, 11, 5);

  setUp(() async {
    opener = AppDatabaseOpener(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = TaskRepository(opener);
    await repository.create(title: 'Renew passport', dueDate: due);
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

  testWidgets('opening a task result selects the task day', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(opener)],
    );
    addTearDown(container.dispose);

    final GoRouter router = GoRouter(
      initialLocation: '/search',
      routes: <RouteBase>[
        GoRoute(
          path: '/search',
          builder: (BuildContext context, GoRouterState state) =>
              const SearchScreen(),
        ),
        GoRoute(
          path: '/tasks',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('tasks page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: PaperTheme.build(style: PaperStyle.white),
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'passport');
    await settle(tester);

    await tester.tap(find.text('Renew passport'));
    await settle(tester);

    expect(container.read(taskDayProvider), due);
    expect(find.text('tasks page'), findsOneWidget);
  });
}
