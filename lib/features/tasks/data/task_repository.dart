import 'dart:async';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/errors/paper_exception.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/ids.dart';
import '../domain/task.dart';

/// Calendar day key used as the `due_date` value. Local time, `YYYY-MM-DD`, so
/// that "today" is stable regardless of timezone offset in the row.
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? parseDayKey(String? value) {
  if (value == null || value.isEmpty) return null;
  final List<String> parts = value.split('-');
  if (parts.length != 3) return null;
  final int? year = int.tryParse(parts[0]);
  final int? month = int.tryParse(parts[1]);
  final int? day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final DateTime date = DateTime(year, month, day);
  // DateTime normalises out-of-range days (31 February becomes 3 March), so a
  // round-trip is the only way to reject impossible calendar dates.
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

class TaskRepository {
  TaskRepository(this._opener);

  final AppDatabaseOpener _opener;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async => _changes.close();

  Future<sqflite.Database> get _db => _opener.database;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PaperException {
      rethrow;
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not read your tasks.',
        cause: error,
      );
    }
  }

  /// Tasks for one day plus undated tasks, ordered undone-first then by
  /// creation. This is the query Paper Home runs.
  Future<List<Task>> forDay(DateTime day) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT * FROM tasks WHERE due_date = ? OR due_date IS NULL '
        'ORDER BY is_done ASC, created_at ASC',
        <Object?>[dayKey(day)],
      );
      return rows.map(_fromRow).toList(growable: false);
    });
  }

  Future<List<Task>> list({int? limit}) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT * FROM tasks ORDER BY is_done ASC, '
        '(due_date IS NULL), due_date ASC, created_at ASC '
        '${limit == null ? '' : 'LIMIT ?'}',
        <Object?>[?limit],
      );
      return rows.map(_fromRow).toList(growable: false);
    });
  }

  Future<Task?> findById(String id) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).query(
        'tasks',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    });
  }

  Future<Task> create({required String title, DateTime? dueDate}) {
    return _guard(() async {
      final Task task = Task(
        id: newLocalId(),
        title: title.trim(),
        isDone: false,
        dueDate: dueDate,
        createdAt: DateTime.now(),
        completedAt: null,
      );
      await (await _db).insert('tasks', _toRow(task));
      _notify();
      return task;
    });
  }

  Future<void> setDone(String id, bool isDone) {
    return _guard(() async {
      await (await _db).update(
        'tasks',
        <String, Object?>{
          'is_done': isDone ? 1 : 0,
          'completed_at': isDone ? DateTime.now().millisecondsSinceEpoch : null,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  Future<void> rename(String id, String title) {
    return _guard(() async {
      await (await _db).update(
        'tasks',
        <String, Object?>{'title': title.trim()},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  Future<void> delete(String id) {
    return _guard(() async {
      await (await _db).delete(
        'tasks',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  /// Removes every completed task older than [before]. Used by "Clear done".
  Future<int> clearCompleted({DateTime? before}) {
    return _guard(() async {
      final int removed = await (await _db).delete(
        'tasks',
        where: 'is_done = 1 AND completed_at IS NOT NULL AND completed_at < ?',
        whereArgs: <Object?>[(before ?? DateTime.now()).millisecondsSinceEpoch],
      );
      if (removed > 0) _notify();
      return removed;
    });
  }

  Future<int> count({bool? done}) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT COUNT(*) AS n FROM tasks ${done == null ? '' : 'WHERE is_done = ?'}',
        <Object?>[if (done != null) (done ? 1 : 0)],
      );
      return (rows.first['n'] as int?) ?? 0;
    });
  }

  static Map<String, Object?> _toRow(Task t) => <String, Object?>{
    'id': t.id,
    'title': t.title,
    'is_done': t.isDone ? 1 : 0,
    'due_date': t.dueDate == null ? null : dayKey(t.dueDate!),
    'created_at': t.createdAt.millisecondsSinceEpoch,
    'completed_at': t.completedAt?.millisecondsSinceEpoch,
  };

  static Task _fromRow(Map<String, Object?> row) => Task(
    id: row['id']! as String,
    title: (row['title'] as String?) ?? '',
    isDone: ((row['is_done'] as int?) ?? 0) == 1,
    dueDate: parseDayKey(row['due_date'] as String?),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    completedAt: row['completed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['completed_at']! as int),
  );
}
