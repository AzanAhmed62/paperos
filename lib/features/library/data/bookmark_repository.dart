import 'dart:async';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/errors/paper_exception.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/ids.dart';
import '../domain/document.dart';

/// Bookmarks, always scoped to one document.
///
/// The unique index on (document_id, page, fraction) means "add bookmark" at a
/// position that already has one is a no-op instead of a duplicate row, which
/// matches what a reader should do when you press the bookmark key twice.
class BookmarkRepository {
  BookmarkRepository(this._opener);

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
        'PaperOS could not read your bookmarks.',
        cause: error,
      );
    }
  }

  Future<List<Bookmark>> listFor(String documentId) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).query(
        'bookmarks',
        where: 'document_id = ?',
        whereArgs: <Object?>[documentId],
        orderBy: 'page ASC, fraction ASC, created_at ASC',
      );
      return rows.map(_fromRow).toList(growable: false);
    });
  }

  Future<int> countFor(String documentId) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT COUNT(*) AS n FROM bookmarks WHERE document_id = ?',
        <Object?>[documentId],
      );
      return (rows.first['n'] as int?) ?? 0;
    });
  }

  /// Bookmark totals for every document that has at least one bookmark, in a
  /// single query.
  ///
  /// The library needs a count next to every row; asking per row would mean one
  /// query per document on every rebuild of the list.
  Future<Map<String, int>> countsByDocument() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT document_id, COUNT(*) AS n FROM bookmarks GROUP BY document_id',
      );
      return <String, int>{
        for (final Map<String, Object?> row in rows)
          row['document_id']! as String: (row['n'] as int?) ?? 0,
      };
    });
  }

  Future<Bookmark?> atPosition({
    required String documentId,
    required ReadingPosition position,
  }) {
    return _guard(() async {
      final String? locator = position.locator;
      final List<Map<String, Object?>> rows = await (await _db).query(
        'bookmarks',
        where: locator != null
            ? 'document_id = ? AND locator = ?'
            : 'document_id = ? AND page = ? AND fraction = ?',
        whereArgs: locator != null
            ? <Object?>[documentId, locator]
            : <Object?>[
                documentId,
                position.page ?? -1,
                position.fraction ?? -1.0,
              ],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    });
  }

  /// Adds a bookmark and returns it, or the existing one if the exact position
  /// was already marked.
  Future<Bookmark> add({
    required String documentId,
    required ReadingPosition position,
    String? label,
    String? excerpt,
    String? chapterTitle,
  }) {
    return _guard(() async {
      final Bookmark? existing = await atPosition(
        documentId: documentId,
        position: position,
      );
      if (existing != null) {
        final bool labelChanged = label != null && existing.label != label;
        final bool chapterChanged =
            chapterTitle != null && existing.chapterTitle != chapterTitle;
        if (labelChanged || chapterChanged) {
          await _updateMetadata(
            existing.id,
            label: labelChanged ? label : null,
            chapterTitle: chapterChanged ? chapterTitle : null,
          );
        }
        return existing.copyWith(
          label: labelChanged ? label : null,
          chapterTitle: chapterChanged ? chapterTitle : null,
        );
      }

      final Bookmark bookmark = Bookmark(
        id: newLocalId(),
        documentId: documentId,
        page: position.page ?? -1,
        fraction: position.fraction ?? -1.0,
        label: label,
        excerpt: excerpt,
        locator: position.locator,
        chapterTitle: chapterTitle,
        createdAt: DateTime.now(),
      );
      await (await _db).insert(
        'bookmarks',
        _toRow(bookmark),
        conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
      );
      _notify();
      return bookmark;
    });
  }

  Future<void> _updateMetadata(
    String id, {
    String? label,
    String? chapterTitle,
  }) async {
    await (await _db).update(
      'bookmarks',
      <String, Object?>{'label': ?label, 'chapter_title': ?chapterTitle},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    _notify();
  }

  Future<void> remove(String id) {
    return _guard(() async {
      await (await _db).delete(
        'bookmarks',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  /// Removes every bookmark in a document. Used when the document is deleted
  /// as a user action; the foreign key handles the implicit case.
  Future<void> removeAllFor(String documentId) {
    return _guard(() async {
      await (await _db).delete(
        'bookmarks',
        where: 'document_id = ?',
        whereArgs: <Object?>[documentId],
      );
      _notify();
    });
  }

  Future<int> countAll() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT COUNT(*) AS n FROM bookmarks',
      );
      return (rows.first['n'] as int?) ?? 0;
    });
  }

  static Map<String, Object?> _toRow(Bookmark b) => <String, Object?>{
    'id': b.id,
    'document_id': b.documentId,
    'page': b.page,
    'fraction': b.fraction,
    'label': b.label,
    'excerpt': b.excerpt,
    'locator': b.locator,
    'chapter_title': b.chapterTitle,
    'created_at': b.createdAt.millisecondsSinceEpoch,
  };

  static Bookmark _fromRow(Map<String, Object?> row) => Bookmark(
    id: row['id']! as String,
    documentId: row['document_id']! as String,
    page: (row['page'] as int?) ?? -1,
    fraction: (row['fraction'] as num?)?.toDouble() ?? -1.0,
    label: row['label'] as String?,
    excerpt: row['excerpt'] as String?,
    locator: row['locator'] as String?,
    chapterTitle: row['chapter_title'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );
}
