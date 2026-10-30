# Database migrations

PaperOS keeps user data in one SQLite database. Imported EPUB and other document
files stay in app-private storage; the database stores index rows, progress, and
anchors only.

Current schema version: **2** (`PaperConfig.databaseVersion`).

The implementation is deliberately explicit:

- `lib/core/storage/paper_schema.dart` contains the v2 DDL and the ordered v1 to
  v2 statements.
- `lib/core/storage/app_database.dart` opens the database, enables foreign keys,
  creates a fresh v2 schema, or runs the version-guarded upgrade.
- `lib/config/app_config.dart` is the single place where the version number is
  raised.
- `test/data/migration_v2_test.dart` creates a real populated v1 database and
  opens it through the production opener.

There is no destructive fallback. The migration never drops a table, recreates a
table, clears progress, or deletes a file.

## Version 1 to version 2

An upgrade from v1 to v2 is additive:

### Documents

Adds nullable columns:

| Column | Purpose |
| --- | --- |
| `last_locator` | Stable EPUB chapter/character position, separate from page and fraction |
| `author` | EPUB package metadata |
| `publisher` | EPUB package metadata |
| `language` | EPUB package metadata |
| `identifier` | EPUB package metadata |
| `description` | EPUB package metadata |
| `cover_path` | App-private cover file |
| `fingerprint` | SHA-256 content identity for deduplication |

Also adds `idx_documents_fingerprint`.

Existing columns and rows are not rewritten. Existing page and fraction progress
remain authoritative for PDF/TXT and remain fallbacks for EPUB.

### Bookmarks

Adds nullable columns:

| Column | Purpose |
| --- | --- |
| `locator` | EPUB chapter/character anchor |
| `chapter_title` | Human-readable destination label |

Existing page/fraction bookmarks remain readable. A bookmark without a locator
continues to use its page or fraction.

### Annotations

Creates the new `annotations` table with:

- primary key `id`;
- `document_id` foreign key to `documents(id)` with `ON DELETE CASCADE`;
- `kind` (`highlight`, `underline`, `note`);
- `start_locator`, `end_locator`, chapter index/title, excerpt, optional note;
- `orphaned` flag;
- timestamps.

Indexes:

- `(document_id, chapter_index, created_at)`;
- `(document_id, updated_at DESC)`.

The cascade is enabled by `PRAGMA foreign_keys = ON` in `onConfigure`. Deleting
a document removes its bookmarks and annotations, but not notes, tasks, or
settings.

### Untouched tables

The migration does not alter `notes`, `tasks`, or `locations`. Their rows remain
exactly as they were. The migration test seeds a note and a task in the v1
database and asserts they survive unchanged.

## Execution semantics

`sqflite` runs `onUpgrade` inside the database open transaction. If any of the
ordered statements fails:

- SQLite rolls back the upgrade batch;
- the database is not left half-migrated;
- `AppDatabaseOpener` converts the failure into a `PaperException.storage`;
- the app reports that it could not open the local library.

The app does not catch that failure by deleting the database. Manual recovery
must preserve the file for inspection; a user should not have to choose between
losing their library and using the app.

Fresh installs use `onCreate`, which creates the complete v2 schema directly,
including the `annotations` table and its indexes.

## What the migration test proves

`test/data/migration_v2_test.dart`:

1. Creates a temporary SQLite file at schema version 1 using a literal copy of
   the v1 documents, bookmarks, notes, and tasks DDL. It does not use the current
   schema, so the test cannot accidentally prove only that v2 matches itself.
2. Inserts a document with progress, favourite state, and reading time; a
   bookmark with label and excerpt; a note; and a completed dated task.
3. Closes the database and opens it through `AppDatabaseOpener`.
4. Reads back the document, progress, favourite state, reading time, bookmark
   label/excerpt, note body/timestamps, and task state/date.
5. Confirms every new v2 document and bookmark column exists and is null for old
   rows.
6. Inserts a v2 annotation and deletes its document, confirming the annotation
   cascades away.

## Adding a future version

When schema v3 is needed:

1. Add the new DDL or `ALTER TABLE` statements to `PaperSchema`.
2. Add ordered migration statements from v2 to v3; never edit the v1 to v2 list
   after release.
3. Raise `PaperConfig.databaseVersion` in the same change.
4. Add a version guard in `AppDatabaseOpener.onUpgrade`:

   ```dart
   if (from < 2 && to >= 2) { ... }
   if (from < 3 && to >= 3) { ... }
   ```

5. Add a test that opens a populated v2 database through the real opener and
   verifies all existing user data plus the new fields.
6. Update this document and the schema version in the final report.

Rules for every future migration:

- no `DROP TABLE` on user data;
- no table rebuild without a tested, transactional copy and foreign-key check;
- no destructive fallback;
- preserve unknown/newer columns when possible;
- keep the version guard so an upgrade path from every older release remains
  explicit;
- do not store book files in SQLite.

## Recovery and rollback limits

There is no automatic rollback to an older schema version. Android normally
installs an application update rather than a downgrade; a downgrade would leave
the older app unable to understand newer columns, but the additive approach
means those extra columns do not break old queries unless a new table is
required.

Before a future risky migration, a one-time database backup should be considered.
v1.1 does not add an automatic backup because it would duplicate storage and is
not needed for the two additive column groups and one new table in this release.
