import 'dart:async';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/errors/paper_exception.dart';
import '../../../core/storage/app_database.dart';
import '../domain/document.dart';
import '../domain/library_models.dart';

/// The single entry point to stored documents.
///
/// Emits on [changes] after every mutation. Query providers watch that stream
/// instead of sprinkling `ref.invalidate` calls across the widget tree, which
/// is what guarantees that closing a document in the reader immediately shows
/// the new progress in the library and on Paper Home.
class DocumentRepository {
  DocumentRepository(this._opener);

  final AppDatabaseOpener _opener;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    await _changes.close();
  }

  Future<sqflite.Database> get _db => _opener.database;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PaperException {
      rethrow;
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not read its library.',
        cause: error,
      );
    }
  }

  /// Lists documents for [scope], optionally narrowed by a case-insensitive
  /// free-text [query] over title and file name.
  Future<List<Document>> list({
    LibraryScope scope = LibraryScope.all,
    String query = '',
    int? limit,
  }) {
    return _guard(() async {
      final List<String> clauses = <String>[];
      switch (scope) {
        case LibraryScope.all:
          break;
        case LibraryScope.recent:
          clauses.add('last_opened_at IS NOT NULL');
        case LibraryScope.favorites:
          clauses.add('is_favorite = 1');
      }

      final String needle = query.trim();
      if (needle.isNotEmpty) {
        clauses.add('(LOWER(title) LIKE ? OR LOWER(source_name) LIKE ?)');
      }

      final String where = clauses.isEmpty
          ? ''
          : 'WHERE ${clauses.join(' AND ')}';

      final List<Object?> args = <Object?>[];
      if (needle.isNotEmpty) {
        final String pattern = '%${needle.toLowerCase()}%';
        args
          ..add(pattern)
          ..add(pattern);
      }
      if (limit != null) {
        args.add(limit);
      }

      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT * FROM documents $where '
        'ORDER BY (last_opened_at IS NULL), last_opened_at DESC, added_at DESC '
        '${limit == null ? '' : 'LIMIT ?'}',
        args,
      );
      return rows.map(_fromRow).toList(growable: false);
    });
  }

  /// The document Paper Home offers to continue: most recently opened and not
  /// yet finished. Returns null when there is genuinely nothing to continue.
  Future<Document?> mostRecentUnfinished() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT * FROM documents '
        'WHERE last_opened_at IS NOT NULL AND status = ? '
        'AND (last_page IS NOT NULL OR last_fraction IS NOT NULL) '
        'ORDER BY last_opened_at DESC LIMIT 40',
        <Object?>[DocumentStatus.ready.id],
      );
      final Iterable<Document> candidates = rows.map(_fromRow);
      for (final Document document in candidates) {
        if (!document.progress.isFinished) return document;
      }
      // Everything that was opened is finished. Offer the newest one anyway
      // rather than an empty home screen.
      return rows.isEmpty ? null : _fromRow(rows.first);
    });
  }

  Future<Document?> findById(String id) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).query(
        'documents',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    });
  }

  Future<Document?> findBySourceUri(String sourceUri) {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).query(
        'documents',
        where: 'source_uri = ?',
        whereArgs: <Object?>[sourceUri],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.first);
    });
  }

  Future<Document> insert(Document document) {
    return _guard(() async {
      await (await _db).insert(
        'documents',
        _toRow(document),
        conflictAlgorithm: sqflite.ConflictAlgorithm.abort,
      );
      _notify();
      return document;
    });
  }

  /// Updates the mutable half of a document row. Ids, paths and formats are
  /// immutable for the lifetime of a library entry.
  Future<void> update(Document document) {
    return _guard(() async {
      await (await _db).update(
        'documents',
        <String, Object?>{
          'title': document.title,
          'page_count': document.pageCount,
          'status': document.status.id,
          'is_favorite': document.isFavorite ? 1 : 0,
          'last_page': document.progress.position?.page,
          'last_fraction': document.progress.position?.fraction,
          'max_page': document.progress.maxPage,
          'last_opened_at': _millis(document.lastOpenedAt),
          'opened_seconds': document.openedSeconds,
        },
        where: 'id = ?',
        whereArgs: <Object?>[document.id],
      );
      _notify();
    });
  }

  Future<void> setFavorite(String id, bool favorite) async {
    await _guard(() async {
      await (await _db).update(
        'documents',
        <String, Object?>{'is_favorite': favorite ? 1 : 0},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  /// Records where the reader stopped. [maxPageSeen] only ever moves forward,
  /// so "furthest page" survives a re-read from the beginning.
  Future<void> saveProgress({
    required String id,
    required ReadingPosition position,
    required int pageCount,
    int? maxPageSeen,
    DateTime? openedAt,
    Duration sessionLength = Duration.zero,
  }) {
    return _guard(() async {
      await (await _db).rawUpdate(
        '''
UPDATE documents
   SET last_page = ?,
       last_fraction = ?,
       page_count = COALESCE(?, page_count),
       max_page = CASE
                     WHEN ? IS NULL THEN max_page
                     WHEN max_page IS NULL THEN ?
                     ELSE MAX(max_page, ?)
                   END,
       last_opened_at = ?,
       opened_seconds = opened_seconds + ?
 WHERE id = ?
''',
        <Object?>[
          position.page,
          position.fraction,
          pageCount > 0 ? pageCount : null,
          maxPageSeen,
          maxPageSeen,
          maxPageSeen,
          _millis(openedAt ?? DateTime.now()),
          sessionLength.inSeconds,
          id,
        ],
      );
      _notify();
    });
  }

  /// Removes the row. The file itself is deleted separately by
  /// [LibraryService] so that a failed unlink cannot corrupt the index.
  Future<void> delete(String id) {
    return _guard(() async {
      await (await _db).delete(
        'documents',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      _notify();
    });
  }

  Future<int> count() {
    return _guard(() async {
      final List<Map<String, Object?>> rows = await (await _db).rawQuery(
        'SELECT COUNT(*) AS n FROM documents',
      );
      return (rows.first['n'] as int?) ?? 0;
    });
  }

  /// Empties the document index. Cascades to bookmarks, which is what makes
  /// "remove every document" a single honest operation rather than a sequence
  /// the caller has to remember to run in the right order.
  Future<void> clear() {
    return _guard(() async {
      await (await _db).delete('documents');
      _notify();
    });
  }

  static int? _millis(DateTime? value) => value?.millisecondsSinceEpoch;

  static Map<String, Object?> _toRow(Document d) => <String, Object?>{
    'id': d.id,
    'local_path': d.localPath,
    'source_uri': d.sourceUri,
    'source_name': d.sourceName,
    'title': d.title,
    'format': d.format.id,
    'byte_size': d.byteSize,
    'page_count': d.pageCount,
    'status': d.status.id,
    'is_favorite': d.isFavorite ? 1 : 0,
    'last_page': d.progress.position?.page,
    'last_fraction': d.progress.position?.fraction,
    'max_page': d.progress.maxPage,
    'added_at': d.addedAt.millisecondsSinceEpoch,
    'last_opened_at': _millis(d.lastOpenedAt),
    'opened_seconds': d.openedSeconds,
  };

  static Document _fromRow(Map<String, Object?> row) {
    final int? page = row['last_page'] as int?;
    final double? fraction = (row['last_fraction'] as num?)?.toDouble();
    final ReadingPosition? position = (page != null || fraction != null)
        ? ReadingPosition(page: page, fraction: fraction)
        : null;

    return Document(
      id: row['id']! as String,
      localPath: row['local_path']! as String,
      sourceUri: row['source_uri'] as String?,
      sourceName: row['source_name']! as String,
      title: row['title']! as String,
      format:
          DocumentFormat.tryParse(row['format']! as String) ??
          DocumentFormat.unknown,
      byteSize: (row['byte_size'] as int?) ?? 0,
      pageCount: row['page_count'] as int?,
      status: DocumentStatus.parse(row['status']! as String),
      isFavorite: ((row['is_favorite'] as int?) ?? 0) == 1,
      progress: ReadingProgress(
        position: position,
        maxPage: row['max_page'] as int?,
        pageCount: (row['page_count'] as int?) ?? 0,
      ),
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at']! as int),
      lastOpenedAt: row['last_opened_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_opened_at']! as int),
      openedSeconds: (row['opened_seconds'] as int?) ?? 0,
    );
  }
}
