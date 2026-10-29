import 'package:paperos/core/storage/app_database.dart';
import 'package:paperos/features/library/domain/document.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the real SQLite engine against an in-memory database.
///
/// The repositories are tested against actual SQL rather than a hand-written
/// fake, so a broken statement, a wrong column name or a bad `COALESCE` shows
/// up here instead of on a device.
void initFfi() {
  sqfliteFfiInit();
}

AppDatabaseOpener openTestDatabase() {
  return AppDatabaseOpener(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
}

int _nextId = 0;

/// A valid, ready document with a caller-controlled title and id.
Document makeDocument({
  String? id,
  String title = 'Untitled',
  DocumentFormat format = DocumentFormat.pdf,
  int? pageCount = 10,
  DocumentStatus status = DocumentStatus.ready,
  bool isFavorite = false,
  String? localPath,
}) {
  final String resolvedId = id ?? 'doc-${_nextId++}';
  return Document(
    id: resolvedId,
    localPath: localPath ?? '/library/$resolvedId.${format.id}',
    sourceUri: 'content://imports/$resolvedId',
    sourceName: '$title.${format.id}',
    title: title,
    format: format,
    byteSize: 2048,
    pageCount: pageCount,
    status: status,
    isFavorite: isFavorite,
    progress: const ReadingProgress(
      position: null,
      maxPage: null,
      pageCount: 0,
    ),
    addedAt: DateTime(2026, 1, 1),
    lastOpenedAt: null,
    openedSeconds: 0,
  );
}

/// Resets the id counter so ids are stable between tests.
void resetIds() => _nextId = 0;

extension SqfliteClose on sqflite.Database {
  Future<void> closeQuietly() async {
    if (isOpen) await close();
  }
}
