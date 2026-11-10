import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/app/providers.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/tasks/application/tasks_providers.dart';
import 'package:paperos/features/tasks/data/task_repository.dart';
import 'package:paperos/features/tasks/domain/task.dart';

import 'support.dart';

void main() {
  initFfi();

  late AppDatabaseOpener opener;
  late TaskRepository repository;
  late ProviderContainer container;

  setUp(() {
    opener = openTestDatabase();
    repository = TaskRepository(opener);
    container = ProviderContainer(
      overrides: [taskRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() async {
    container.dispose();
    await repository.dispose();
    await opener.close();
  });

  test('Home stays on today after Tasks browses another day', () async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime tomorrow = today.add(const Duration(days: 1));

    await repository.create(title: 'Today', dueDate: today);
    await repository.create(title: 'Tomorrow', dueDate: tomorrow);

    container.read(taskDayProvider.notifier).select(tomorrow);

    final List<Task> homeTasks = await container.read(
      todayTasksProvider.future,
    );
    final List<Task> browsedDayTasks = await container.read(
      tasksForDayProvider.future,
    );

    expect(homeTasks.map((Task task) => task.title), <String>['Today']);
    expect(browsedDayTasks.map((Task task) => task.title), <String>[
      'Tomorrow',
    ]);
  });

  test('todayTasksProvider refreshes after each mutation, not just the first', () async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    // A widget keeps this provider alive by watching it; a bare `.future` read
    // does not, so hold a listener just as the Home section does.
    final ProviderSubscription<AsyncValue<List<Task>>> subscription = container
        .listen(todayTasksProvider, (_, _) {});
    addTearDown(subscription.close);

    Future<List<Task>> waitFor(
      bool Function(List<Task> tasks) ready, {
      String? description,
    }) async {
      for (int attempt = 0; attempt < 200; attempt++) {
        final AsyncValue<List<Task>> value = container.read(todayTasksProvider);
        if (value.hasValue && !value.isLoading && ready(value.requireValue)) {
          return value.requireValue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('todayTasksProvider did not refresh: ${description ?? ''}');
    }

    final Task first = await repository.create(title: 'First', dueDate: today);
    final Task second = await repository.create(
      title: 'Second',
      dueDate: today,
    );

    List<Task> tasks = await waitFor((List<Task> tasks) => tasks.length == 2);

    await repository.setDone(first.id, true);
    tasks = await waitFor(
      (List<Task> tasks) =>
          tasks.firstWhere((Task task) => task.id == first.id).isDone,
      description: 'first task marked done',
    );

    await repository.delete(second.id);
    tasks = await waitFor(
      (List<Task> tasks) => tasks.length == 1,
      description: 'second task deleted',
    );
    expect(tasks.map((Task task) => task.title), <String>['First']);
  });
}
