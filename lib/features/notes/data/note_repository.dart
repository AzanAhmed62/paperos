import 'dart:async';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/errors/paper_exception.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/ids.dart';
import '../domain/note.dart';

class NoteRepository {
  NoteRepository(this._opener);

  final AppDatabaseOpener _opener;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void notifyChanged() => _notify();

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
        'PaperOS could not read your notes.',
        cause: error,
      );
    }
  }

  Future<List<Note>> list({String query = '', int? limit}) {
    return _guard(() async {
      final String needle = query.trim();
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        needle.isEmpty
            ? 'SELECT * FROM notes ORDER BY updated_at DESC '
                  '${limit == null ? '' : 'LIMIT ?'}'
            : 'SELECT * FROM notes WHERE LOWER(title) LIKE ? OR LOWER(body) LIKE ? '
                  'ORDER BY updated_at DESC '
                  '${limit == null ? '' : 'LIMIT ?'}',
        <Object?>[
          if (needle.isNotEmpty) ...<Object?>[
            '%${needle.toLowerCase()}%',
            '%${needle.toLowerCase()}%',
          ],
          ?limit,
        ],
      );
      return rows.map(_fromRow).toList(growable: false);
    });
  }

  Future<Note?> findById(String id) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).query(
        'notes',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    });
  }

  Future<Note> create({String title = '', String body = ''}) {
    return _guard(() async {
      final DateTime now = DateTime.now();
      final Note note = Note(
        id: newLocalId(),
        title: title,
        body: body,
        createdAt: now,
        updatedAt: now,
      );
      await (await _db).insert('notes', _toRow(note));
      _notify();
      return note;
    });
  }

  Future<void> update(Note note) {
    return _guard(() async {
      await (await _db).update(
        'notes',
        <String, Object?>{
          'title': note.title,
          'body': note.body,
          'updated_at': note.updatedAt.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[note.id],
      );
      _notify();
    });
  }

  Future<void> delete(String id) {
    return _guard(() async {
      await (await _db).delete(
        'notes',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  Future<int> count() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT COUNT(*) AS n FROM notes',
      );
      return (rows.first['n'] as int?) ?? 0;
    });
  }

  static Map<String, Object?> _toRow(Note n) => <String, Object?>{
    'id': n.id,
    'title': n.title,
    'body': n.body,
    'created_at': n.createdAt.millisecondsSinceEpoch,
    'updated_at': n.updatedAt.millisecondsSinceEpoch,
  };

  static Note _fromRow(Map<String, Object?> row) => Note(
    id: row['id']! as String,
    title: (row['title'] as String?) ?? '',
    body: (row['body'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}
