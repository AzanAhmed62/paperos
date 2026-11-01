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
  last_locator   TEXT,
  max_page       INTEGER,
  added_at       INTEGER NOT NULL,
  last_opened_at INTEGER,
  opened_seconds INTEGER NOT NULL DEFAULT 0,
  author         TEXT,
  publisher      TEXT,
  language       TEXT,
  identifier     TEXT,
  description    TEXT,
  cover_path     TEXT,
  fingerprint    TEXT
);
''';

  /// Foreign keys are off by default in SQLite; the opener turns them on.
  static const List<String> indexesDocuments = <String>[
    'CREATE INDEX idx_documents_last_opened ON documents (last_opened_at DESC)',
    'CREATE INDEX idx_documents_favorite ON documents (is_favorite, last_opened_at DESC)',
    'CREATE INDEX idx_documents_format ON documents (format)',
    'CREATE INDEX idx_documents_source ON documents (source_uri)',
    'CREATE INDEX idx_documents_fingerprint ON documents (fingerprint)',
  ];

  /// `page` is -1 for continuous documents (text); `fraction` then carries a
  /// 0..1 position through the document instead. `locator` is an optional
  /// format-native anchor (currently the EPUB spine/character locator) that is
  /// more stable than either when typography changes.
  static const String createBookmarks = '''
CREATE TABLE bookmarks (
  id            TEXT PRIMARY KEY,
  document_id   TEXT NOT NULL REFERENCES documents (id) ON DELETE CASCADE,
  page          INTEGER NOT NULL DEFAULT -1,
  fraction      REAL NOT NULL DEFAULT -1,
  label         TEXT,
  excerpt       TEXT,
  locator       TEXT,
  chapter_title TEXT,
  created_at    INTEGER NOT NULL
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

  /// A highlight, underline or attached note anchored to a passage.
  ///
  /// Locators are chapter-relative character anchors (`epub:spine=2;char=120`)
  /// rather than offsets into the paginated text. Re-pagination, a new font or
  /// a different screen width therefore cannot silently move a highlight to a
  /// different paragraph. `orphaned` keeps an annotation recoverable when a
  /// future parser cannot resolve its chapter or the passage has changed.
  static const String createAnnotations = '''
CREATE TABLE annotations (
  id            TEXT PRIMARY KEY,
  document_id   TEXT NOT NULL REFERENCES documents (id) ON DELETE CASCADE,
  kind          TEXT NOT NULL,
  start_locator TEXT NOT NULL,
  end_locator   TEXT NOT NULL,
  chapter_index INTEGER,
  chapter_title TEXT,
  excerpt       TEXT NOT NULL,
  note          TEXT,
  orphaned      INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
''';

  static const List<String> indexesAnnotations = <String>[
    'CREATE INDEX idx_annotations_document'
        ' ON annotations (document_id, chapter_index, created_at)',
    'CREATE INDEX idx_annotations_updated'
        ' ON annotations (document_id, updated_at DESC)',
  ];

  /// Backup order: parents before children for insert, reverse for delete.
  static const List<String> backupTables = <String>[
    'documents',
    'bookmarks',
    'annotations',
    'notes',
    'tasks',
    'locations',
  ];

  /// Columns accepted from a backup's JSON. Keeping this explicit means an
  /// unknown or future column is refused instead of silently passed to SQLite.
  static const Map<String, List<String>> backupColumns = <String, List<String>>{
    'documents': <String>[
      'id',
      'local_path',
      'source_uri',
      'source_name',
      'title',
      'format',
      'byte_size',
      'page_count',
      'status',
      'is_favorite',
      'last_page',
      'last_fraction',
      'last_locator',
      'max_page',
      'added_at',
      'last_opened_at',
      'opened_seconds',
      'author',
      'publisher',
      'language',
      'identifier',
      'description',
      'cover_path',
      'fingerprint',
    ],
    'bookmarks': <String>[
      'id',
      'document_id',
      'page',
      'fraction',
      'label',
      'excerpt',
      'locator',
      'chapter_title',
      'created_at',
    ],
    'annotations': <String>[
      'id',
      'document_id',
      'kind',
      'start_locator',
      'end_locator',
      'chapter_index',
      'chapter_title',
      'excerpt',
      'note',
      'orphaned',
      'created_at',
      'updated_at',
    ],
    'notes': <String>[
      'id',
      'title',
      'body',
      'created_at',
      'updated_at',
    ],
    'tasks': <String>[
      'id',
      'title',
      'is_done',
      'due_date',
      'created_at',
      'completed_at',
    ],
    'locations': <String>[
      'id',
      'label',
      'path',
      'is_system',
      'added_at',
    ],
  };

  /// Non-null columns, checked before a restore touches the live database.
  static const Map<String, List<String>> requiredColumns =
      <String, List<String>>{
        'documents': <String>[
          'id',
          'local_path',
          'source_name',
          'title',
          'format',
          'byte_size',
          'status',
          'is_favorite',
          'added_at',
          'opened_seconds',
        ],
        'bookmarks': <String>[
          'id',
          'document_id',
          'page',
          'fraction',
          'created_at',
        ],
        'annotations': <String>[
          'id',
          'document_id',
          'kind',
          'start_locator',
          'end_locator',
          'excerpt',
          'orphaned',
          'created_at',
          'updated_at',
        ],
        'notes': <String>[
          'id',
          'title',
          'body',
          'created_at',
          'updated_at',
        ],
        'tasks': <String>[
          'id',
          'title',
          'is_done',
          'created_at',
        ],
        'locations': <String>[
          'id',
          'label',
          'path',
          'is_system',
          'added_at',
        ],
      };

  /// Additive migration from schema 1. Every statement is safe to run once
  /// inside the upgrade transaction; SQLite rolls the whole batch back if a
  /// statement fails, so a half-migrated library cannot be opened.
  static const List<String> migrateV1ToV2 = <String>[
    'ALTER TABLE documents ADD COLUMN last_locator TEXT',
    'ALTER TABLE documents ADD COLUMN author TEXT',
    'ALTER TABLE documents ADD COLUMN publisher TEXT',
    'ALTER TABLE documents ADD COLUMN language TEXT',
    'ALTER TABLE documents ADD COLUMN identifier TEXT',
    'ALTER TABLE documents ADD COLUMN description TEXT',
    'ALTER TABLE documents ADD COLUMN cover_path TEXT',
    'ALTER TABLE documents ADD COLUMN fingerprint TEXT',
    'CREATE INDEX IF NOT EXISTS idx_documents_fingerprint'
        ' ON documents (fingerprint)',
    'ALTER TABLE bookmarks ADD COLUMN locator TEXT',
    'ALTER TABLE bookmarks ADD COLUMN chapter_title TEXT',
    createAnnotations,
    ...indexesAnnotations,
  ];
}
