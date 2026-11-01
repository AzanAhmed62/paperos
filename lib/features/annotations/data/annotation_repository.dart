import 'dart:async';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/errors/paper_exception.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/ids.dart';
import '../domain/annotation.dart';

/// Persistent highlights, underlines and attached notes.
///
/// The table cascades from `documents`, so removing a book removes its
/// annotations without a second cleanup pass. Unresolved anchors are not
/// deleted: [markOrphaned] keeps the excerpt and note recoverable.
class AnnotationRepository {
  AnnotationRepository(this._opener);

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
        'PaperOS could not read your annotations.',
        cause: error,
      );
    }
  }

  Future<List<Annotation>> listFor(String documentId) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).query(
        'annotations',
        where: 'document_id = ?',
        whereArgs: <Object?>[documentId],
        orderBy: 'chapter_index ASC, created_at ASC',
      );
      return rows.map(_fromRow).toList(growable: false);
    });
  }

  Future<Map<String, int>> countsByDocument() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT document_id, COUNT(*) AS n FROM annotations GROUP BY document_id',
      );
      return <String, int>{
        for (final Map<String, Object?> row in rows)
          row['document_id']! as String: (row['n'] as int?) ?? 0,
      };
    });
  }

  Future<Annotation> add({
    required String documentId,
    required AnnotationKind kind,
    required String startLocator,
    required String endLocator,
    required String excerpt,
    int? chapterIndex,
    String? chapterTitle,
    String? note,
  }) {
    return _guard(() async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final Annotation annotation = Annotation(
        id: newLocalId(),
        documentId: documentId,
        kind: kind,
        startLocator: startLocator,
        endLocator: endLocator,
        excerpt: excerpt,
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        note: note,
        createdAt: DateTime.fromMillisecondsSinceEpoch(now),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
      );
      await (await _db).insert('annotations', _toRow(annotation));
      _notify();
      return annotation;
    });
  }

  Future<void> updateNote(String id, String? note) {
    return _guard(() async {
      final String? trimmed = note?.trim();
      await (await _db).update(
        'annotations',
        <String, Object?>{
          'note': trimmed == null || trimmed.isEmpty ? null : trimmed,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  /// Keeps an unresolved anchor visible instead of deleting the annotation.
  Future<void> markOrphaned(String id, {bool orphaned = true}) {
    return _guard(() async {
      await (await _db).update(
        'annotations',
        <String, Object?>{
          'orphaned': orphaned ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  Future<void> remove(String id) {
    return _guard(() async {
      await (await _db).delete(
        'annotations',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  Future<int> countAll() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT COUNT(*) AS n FROM annotations',
      );
      return (rows.first['n'] as int?) ?? 0;
    });
  }

  static Map<String, Object?> _toRow(Annotation a) => <String, Object?>{
    'id': a.id,
    'document_id': a.documentId,
    'kind': a.kind.id,
    'start_locator': a.startLocator,
    'end_locator': a.endLocator,
    'chapter_index': a.chapterIndex,
    'chapter_title': a.chapterTitle,
    'excerpt': a.excerpt,
    'note': a.note,
    'orphaned': a.orphaned ? 1 : 0,
    'created_at': a.createdAt.millisecondsSinceEpoch,
    'updated_at': a.updatedAt.millisecondsSinceEpoch,
  };

  static Annotation _fromRow(Map<String, Object?> row) => Annotation(
    id: row['id']! as String,
    documentId: row['document_id']! as String,
    kind: AnnotationKind.parse(row['kind']! as String),
    startLocator: row['start_locator']! as String,
    endLocator: row['end_locator']! as String,
    chapterIndex: row['chapter_index'] as int?,
    chapterTitle: row['chapter_title'] as String?,
    excerpt: row['excerpt']! as String,
    note: row['note'] as String?,
    orphaned: ((row['orphaned'] as int?) ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
}
