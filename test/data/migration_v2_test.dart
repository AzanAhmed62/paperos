import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paperos/core/storage/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support.dart';

/// The schema as it shipped in v1.0. Copied literally here on purpose: a
/// migration test that used the current DDL would not prove anything.
const String _v1Documents = '''
CREATE TABLE documents (
  id             TEXT PRIMARY KEY,
  local_path     TEXT NOT NULL,
  source_uri     TEXT,
  source_name    TEXT NOT NULL,
  title          TEXT NOT NULL,
  format         TEXT NOT NULL,
  byte_size      INTEGER NOT NULL DEFAULT 0,
  page_count     INTEGER,
  status         TEXT NOT NULL DEFAULT 'ready',
  is_favorite    INTEGER NOT NULL DEFAULT 0,
  last_page      INTEGER,
  last_fraction  REAL,
  max_page       INTEGER,
  added_at       INTEGER NOT NULL,
  last_opened_at INTEGER,
  opened_seconds INTEGER NOT NULL DEFAULT 0
);
''';

const String _v1Bookmarks = '''
CREATE TABLE bookmarks (
  id          TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES documents (id) ON DELETE CASCADE,
  page        INTEGER NOT NULL DEFAULT -1,
  fraction    REAL NOT NULL DEFAULT -1,
  label       TEXT,
  excerpt     TEXT,
  created_at  INTEGER NOT NULL
);
''';

const String _v1Notes = '''
CREATE TABLE notes (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''';

const String _v1Tasks = '''
CREATE TABLE tasks (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  is_done      INTEGER NOT NULL DEFAULT 0,
  due_date     TEXT,
  created_at   INTEGER NOT NULL,
  completed_at INTEGER
);
''';

void main() {
  initFfi();

  test(
    'migrates a populated v1 library to v2 without losing user data',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'paperos_migration_',
      );
      final String path = p.join(directory.path, 'paperos.db');

      try {
        final Database old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onConfigure: (Database db) =>
                db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (Database db, int version) async {
              await db.execute(_v1Documents);
              await db.execute(_v1Bookmarks);
              await db.execute(_v1Notes);
              await db.execute(_v1Tasks);
              await db.execute(
                'CREATE UNIQUE INDEX idx_bookmarks_document_position '
                'ON bookmarks (document_id, page, fraction)',
              );
            },
          ),
        );
        await old.insert('documents', <String, Object?>{
          'id': 'old-doc',
          'local_path': '/library/old.epub',
          'source_uri': 'content://old.epub',
          'source_name': 'old.epub',
          'title': 'An Old Book',
          'format': 'epub',
          'byte_size': 4096,
          'page_count': 120,
          'is_favorite': 1,
          'last_page': 17,
          'last_fraction': 0.14,
          'max_page': 20,
          'added_at': 1000,
          'last_opened_at': 2000,
          'opened_seconds': 55,
        });
        await old.insert('bookmarks', <String, Object?>{
          'id': 'old-bookmark',
          'document_id': 'old-doc',
          'page': 17,
          'fraction': 0.14,
          'label': 'Saved chapter',
          'excerpt': 'Old excerpt',
          'created_at': 1500,
        });
        await old.insert('notes', <String, Object?>{
          'id': 'old-note',
          'title': 'A note from v1',
          'body': 'It must survive the upgrade.',
          'created_at': 1600,
          'updated_at': 1700,
        });
        await old.insert('tasks', <String, Object?>{
          'id': 'old-task',
          'title': 'A task from v1',
          'is_done': 1,
          'due_date': '2026-10-29',
          'created_at': 1800,
          'completed_at': 1900,
        });
        await old.close();

        final AppDatabaseOpener opener = AppDatabaseOpener(
          factory: databaseFactoryFfi,
          path: path,
        );
        final Database db = await opener.database;

        final List<Map<String, Object?>> documentRows = await db.query(
          'documents',
        );
        expect(documentRows, hasLength(1));
        final Map<String, Object?> document = documentRows.single;
        expect(document['title'], 'An Old Book');
        expect(document['last_page'], 17);
        expect(document['last_fraction'], 0.14);
        expect(document['is_favorite'], 1);
        expect(document['opened_seconds'], 55);
        for (final String column in <String>[
          'last_locator',
          'author',
          'publisher',
          'language',
          'identifier',
          'description',
          'cover_path',
          'fingerprint',
        ]) {
          expect(document.keys, contains(column));
          expect(document[column], isNull);
        }

        final Map<String, Object?> bookmark = (await db.query(
          'bookmarks',
        )).single;
        expect(bookmark['label'], 'Saved chapter');
        expect(bookmark['excerpt'], 'Old excerpt');
        expect(
          bookmark.keys,
          containsAll(<String>['locator', 'chapter_title']),
        );
        expect(bookmark['locator'], isNull);

        expect((await db.query('notes')).single, <String, Object?>{
          'id': 'old-note',
          'title': 'A note from v1',
          'body': 'It must survive the upgrade.',
          'created_at': 1600,
          'updated_at': 1700,
        });
        expect((await db.query('tasks')).single, <String, Object?>{
          'id': 'old-task',
          'title': 'A task from v1',
          'is_done': 1,
          'due_date': '2026-10-29',
          'created_at': 1800,
          'completed_at': 1900,
        });

        final List<Map<String, Object?>> annotationTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'annotations'",
        );
        expect(annotationTables, hasLength(1));

        await db.insert('annotations', <String, Object?>{
          'id': 'new-annotation',
          'document_id': 'old-doc',
          'kind': 'highlight',
          'start_locator': 'epub:spine=0;char=3',
          'end_locator': 'epub:spine=0;char=8',
          'chapter_index': 0,
          'chapter_title': 'Chapter One',
          'excerpt': 'Old excerpt',
          'note': null,
          'orphaned': 0,
          'created_at': 3000,
          'updated_at': 3000,
        });
        await db.delete(
          'documents',
          where: 'id = ?',
          whereArgs: <Object?>['old-doc'],
        );
        expect(await db.query('annotations'), isEmpty);

        await opener.close();
        await directory.delete(recursive: true);
      } finally {
        if (directory.existsSync()) await directory.delete(recursive: true);
      }
    },
  );
}
