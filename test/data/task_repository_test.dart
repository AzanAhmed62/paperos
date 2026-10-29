import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/tasks/data/task_repository.dart';
import 'package:paperos/features/tasks/domain/task.dart';

import 'support.dart';

void main() {
  initFfi();

  late AppDatabaseOpener opener;
  late TaskRepository tasks;

  setUp(() async {
    opener = openTestDatabase();
    tasks = TaskRepository(opener);
  });

  tearDown(() async {
    await tasks.dispose();
    await (await opener.database).close();
  });

  group('create', () {
    test('stores a task and reads it back', () async {
      final Task created = await tasks.create(
        title: '  Buy ink  ',
        dueDate: DateTime(2026, 3, 4),
      );

      expect(created.title, 'Buy ink', reason: 'title is trimmed');
      expect(created.isDone, isFalse);
      expect(created.dueDate, DateTime(2026, 3, 4));
      expect(created.completedAt, isNull);

      final Task? reloaded = await tasks.findById(created.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.title, 'Buy ink');
      expect(reloaded.dueDate, DateTime(2026, 3, 4));
    });

    test('keeps an undated task undated', () async {
      final Task created = await tasks.create(title: 'Someday');
      expect(created.dueDate, isNull);
      expect((await tasks.findById(created.id))!.dueDate, isNull);
    });
  });

  group('forDay', () {
    test(
      'returns tasks due that day plus undated ones, but not other days',
      () async {
        await tasks.create(title: 'Today', dueDate: DateTime(2026, 5, 10));
        await tasks.create(title: 'Tomorrow', dueDate: DateTime(2026, 5, 11));
        await tasks.create(title: 'Unscheduled');

        final List<Task> forDay = await tasks.forDay(DateTime(2026, 5, 10));
        final List<String> titles = forDay
            .map((Task task) => task.title)
            .toList();

        expect(titles, containsAll(<String>['Today', 'Unscheduled']));
        expect(titles, isNot(contains('Tomorrow')));
      },
    );

    test('orders unfinished tasks before finished ones', () async {
      final Task done = await tasks.create(
        title: 'Finished',
        dueDate: DateTime(2026, 5, 10),
      );
      await tasks.create(title: 'Open', dueDate: DateTime(2026, 5, 10));
      await tasks.setDone(done.id, true);

      final List<Task> forDay = await tasks.forDay(DateTime(2026, 5, 10));
      expect(forDay.first.title, 'Open');
      expect(forDay.last.title, 'Finished');
    });
  });

  group('mutations', () {
    test('setDone records and clears the completion time', () async {
      final Task task = await tasks.create(title: 'Do it');

      await tasks.setDone(task.id, true);
      Task? reloaded = await tasks.findById(task.id);
      expect(reloaded!.isDone, isTrue);
      expect(reloaded.completedAt, isNotNull);

      await tasks.setDone(task.id, false);
      reloaded = await tasks.findById(task.id);
      expect(reloaded!.isDone, isFalse);
      expect(reloaded.completedAt, isNull);
    });

    test('rename trims and persists the new title', () async {
      final Task task = await tasks.create(title: 'Old');
      await tasks.rename(task.id, '  New name ');
      expect((await tasks.findById(task.id))!.title, 'New name');
    });

    test('delete removes exactly one task', () async {
      final Task a = await tasks.create(title: 'A');
      await tasks.create(title: 'B');
      await tasks.delete(a.id);
      expect(await tasks.findById(a.id), isNull);
      expect(await tasks.count(), 1);
    });

    test(
      'clearCompleted removes only finished tasks older than the cutoff',
      () async {
        final Task old = await tasks.create(title: 'Old done');
        await tasks.setDone(old.id, true);
        final Task fresh = await tasks.create(title: 'Still open');

        final int removed = await tasks.clearCompleted(
          before: DateTime.now().add(const Duration(minutes: 1)),
        );

        expect(removed, 1);
        expect(await tasks.findById(old.id), isNull);
        expect(await tasks.findById(fresh.id), isNotNull);
      },
    );

    test('count filters by done state', () async {
      final Task a = await tasks.create(title: 'A');
      await tasks.create(title: 'B');
      await tasks.setDone(a.id, true);

      expect(await tasks.count(), 2);
      expect(await tasks.count(done: false), 1);
      expect(await tasks.count(done: true), 1);
    });
  });

  group('parseDayKey', () {
    test('accepts real dates, including leap day', () {
      expect(parseDayKey('2026-03-04'), DateTime(2026, 3, 4));
      expect(parseDayKey('2024-02-29'), DateTime(2024, 2, 29));
      expect(parseDayKey(null), isNull);
      expect(parseDayKey(''), isNull);
    });

    test('rejects impossible or malformed dates', () {
      expect(parseDayKey('2026-02-31'), isNull);
      expect(parseDayKey('2025-02-29'), isNull);
      expect(parseDayKey('2026-13-01'), isNull);
      expect(parseDayKey('2026-00-10'), isNull);
      expect(parseDayKey('2026-01-00'), isNull);
      expect(parseDayKey('not-a-date'), isNull);
      expect(parseDayKey('2026-01'), isNull);
    });
  });

  test('emits a change event after a mutation', () async {
    final Future<void> change = tasks.changes.first;
    await tasks.create(title: 'Trigger');
    await expectLater(change, completes);
  });
}
