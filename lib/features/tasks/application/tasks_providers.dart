import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/task.dart';

/// Emits whenever the tasks table changes.
///
/// The repository's stream is `void`; mapping it to a counter matters because
/// Riverpod de-duplicates identical `AsyncData` values. Without this, only the
/// first mutation would invalidate [tasksForDayProvider] — later edits would
/// be persisted but never reach the screen.
final tasksRevisionProvider = StreamProvider<int>((Ref ref) {
  int revision = 0;
  return ref.watch(taskRepositoryProvider).changes.map((_) => ++revision);
});

/// The day Paper Home and the Tasks screen are looking at.
///
/// Held in one place so that adding a task from Home and seeing it in the
/// Tasks screen cannot disagree about which day is selected.
/// The local calendar day containing [now].
DateTime _startOfToday() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class TaskDayController extends Notifier<DateTime> {
  @override
  DateTime build() => _startOfToday();

  void select(DateTime day) {
    state = DateTime(day.year, day.month, day.day);
  }

  void resetToToday() {
    state = _startOfToday();
  }
}

final taskDayProvider = NotifierProvider<TaskDayController, DateTime>(
  TaskDayController.new,
);

final tasksForDayProvider = FutureProvider<List<Task>>((Ref ref) async {
  ref.watch(tasksRevisionProvider);
  return ref.watch(taskRepositoryProvider).forDay(ref.watch(taskDayProvider));
});

/// Tasks due today, independent of the day the Tasks screen happens to be
/// browsing. Paper Home must always answer "what is due today?" — otherwise
/// paging to next week on the Tasks screen would silently change Home too.
final todayTasksProvider = FutureProvider<List<Task>>((Ref ref) async {
  ref.watch(tasksRevisionProvider);
  return ref.watch(taskRepositoryProvider).forDay(_startOfToday());
});

final openTaskCountProvider = FutureProvider<int>((Ref ref) async {
  ref.watch(tasksRevisionProvider);
  return ref.watch(taskRepositoryProvider).count(done: false);
});

/// Task mutations. Screens call these; they never touch the repository.
class TaskActions {
  const TaskActions(this._ref);

  final Ref _ref;

  /// Returns null when [title] is blank, so a stray newline cannot create an
  /// invisible task.
  Future<Task?> create(String title, {DateTime? dueDate}) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) return Future<Task?>.value();
    return _ref
        .read(taskRepositoryProvider)
        .create(title: trimmed, dueDate: dueDate);
  }

  Future<void> setDone(Task task, bool isDone) =>
      _ref.read(taskRepositoryProvider).setDone(task.id, isDone);

  Future<void> rename(Task task, String title) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == task.title) return Future<void>.value();
    return _ref.read(taskRepositoryProvider).rename(task.id, trimmed);
  }

  Future<void> delete(Task task) =>
      _ref.read(taskRepositoryProvider).delete(task.id);

  Future<int> clearCompleted({DateTime? before}) =>
      _ref.read(taskRepositoryProvider).clearCompleted(before: before);
}

final taskActionsProvider = Provider<TaskActions>(TaskActions.new);
