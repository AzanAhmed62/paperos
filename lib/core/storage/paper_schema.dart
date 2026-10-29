/// SQLite schema for PaperOS.
///
/// Kept as literal DDL rather than generated code: the surface is small, the
/// migration story is completely explicit, and there is no build_runner in the
/// loop for a person (or an agent) to keep working.
library;

/// Bump [PaperConfig.databaseVersion] after editing this file.
abstract final class PaperSchema {
  /// One row per file in the library. A row is created by import and is the
  /// single source of truth for metadata, reading progress and favourites.
  ///
  /// `local_path` is an app-private copy of the original. PaperOS copies on
  /// import deliberately: a SAF grant is revocable and can expire, and a
  /// library that silently loses books is worse than one that uses disk.
  static const String createDocuments = '''
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

  /// Foreign keys are off by default in SQLite; the opener turns them on.
  static const List<String> indexesDocuments = <String>[
    'CREATE INDEX idx_documents_last_opened ON documents (last_opened_at DESC)',
    'CREATE INDEX idx_documents_favorite ON documents (is_favorite, last_opened_at DESC)',
    'CREATE INDEX idx_documents_format ON documents (format)',
    'CREATE INDEX idx_documents_source ON documents (source_uri)',
  ];

  /// `page` is -1 for continuous documents (text); `fraction` then carries a
  /// 0..1 position through the document instead.
  static const String createBookmarks = '''
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

  static const List<String> indexesBookmarks = <String>[
    'CREATE UNIQUE INDEX idx_bookmarks_document_position'
        ' ON bookmarks (document_id, page, fraction)',
    'CREATE INDEX idx_bookmarks_document ON bookmarks (document_id, created_at DESC)',
  ];

  static const String createNotes = '''
CREATE TABLE notes (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''';

  static const List<String> indexesNotes = <String>[
    'CREATE INDEX idx_notes_updated ON notes (updated_at DESC)',
  ];

  static const String createTasks = '''
CREATE TABLE tasks (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  is_done      INTEGER NOT NULL DEFAULT 0,
  due_date     TEXT,
  created_at   INTEGER NOT NULL,
  completed_at INTEGER
);
''';

  static const List<String> indexesTasks = <String>[
    'CREATE INDEX idx_tasks_due ON tasks (due_date, is_done)',
    'CREATE INDEX idx_tasks_created ON tasks (created_at DESC)',
  ];

  /// User-chosen folders, registered through the system folder picker. Paths
  /// are only ever *displayed* back to the user: PaperOS never reads them
  /// directly, because on Android 11+ it could not.
  static const String createLocations = '''
CREATE TABLE locations (
  id        TEXT PRIMARY KEY,
  label     TEXT NOT NULL,
  path      TEXT NOT NULL UNIQUE,
  is_system INTEGER NOT NULL DEFAULT 0,
  added_at  INTEGER NOT NULL
);
''';

  static const List<String> migrations = <String>[];
}
