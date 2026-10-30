import 'dart:async';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../config/app_config.dart';
import '../errors/paper_exception.dart';
import 'paper_schema.dart';

/// Opens (and migrates) the PaperOS content database.
///
/// The [sqflite.DatabaseFactory] and path are injectable so that tests can run
/// the real SQLite engine against an in-memory database. Nothing else in the
/// app knows which factory it is talking to.
class AppDatabaseOpener {
  AppDatabaseOpener({sqflite.DatabaseFactory? factory, this.path})
    : _factory = factory;

  final sqflite.DatabaseFactory? _factory;
  final String? path;

  sqflite.Database? _database;
  Future<sqflite.Database>? _opening;

  /// The open database, or opens it on first use.
  Future<sqflite.Database> get database async {
    final sqflite.Database? existing = _database;
    if (existing != null && existing.isOpen) return existing;
    return _opening ??= _open();
  }

  Future<sqflite.Database> _open() async {
    try {
      final sqflite.DatabaseFactory factory =
          _factory ?? sqflite.databaseFactory;
      final String resolvedPath = path ?? await _defaultPath();

      final sqflite.Database db = await factory.openDatabase(
        resolvedPath,
        options: sqflite.OpenDatabaseOptions(
          version: PaperConfig.databaseVersion,
          onConfigure: (sqflite.Database database) async {
            // Bookmarks belong to documents and must disappear with them.
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (sqflite.Database database, int version) async {
            for (final Map<String, Object?> bundle in [
              _bundle(
                PaperSchema.createDocuments,
                PaperSchema.indexesDocuments,
              ),
              _bundle(
                PaperSchema.createBookmarks,
                PaperSchema.indexesBookmarks,
              ),
              _bundle(PaperSchema.createNotes, PaperSchema.indexesNotes),
              _bundle(PaperSchema.createTasks, PaperSchema.indexesTasks),
              _bundle(PaperSchema.createLocations, const <String>[]),
              _bundle(
                PaperSchema.createAnnotations,
                PaperSchema.indexesAnnotations,
              ),
            ]) {
              await database.execute(bundle['sql']! as String);
              for (final Object? index in bundle['indexes']! as List<Object?>) {
                await database.execute(index! as String);
              }
            }
          },
          onUpgrade: (sqflite.Database database, int from, int to) async {
            // Explicit, additive, version-guarded migrations. Never drop or
            // recreate a table: progress, bookmarks, notes and tasks predate
            // EPUB support and must survive every upgrade.
            if (from < 2 && to >= 2) {
              for (final String statement in PaperSchema.migrateV1ToV2) {
                await database.execute(statement);
              }
            }
          },
        ),
      );
      _database = db;
      return db;
    } on PaperException {
      rethrow;
    } catch (error) {
      throw PaperException.storage(
        'PaperOS could not open its local library.',
        cause: error,
        detail: 'openDatabase(path: $path)',
      );
    } finally {
      _opening = null;
    }
  }

  static Map<String, Object?> _bundle(String sql, List<String> indexes) =>
      <String, Object?>{'sql': sql, 'indexes': indexes};

  static Future<String> _defaultPath() async =>
      '${await sqflite.getDatabasesPath()}/${PaperConfig.databaseName}';

  /// Closes the handle. Used by tests and on app teardown.
  Future<void> close() async {
    final sqflite.Database? db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
