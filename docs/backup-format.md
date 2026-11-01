# PaperOS backup format

PaperOS 1.2 writes a complete local backup as a single file with the extension
`.paperosbackup`. It is an ordinary ZIP container, not a live SQLite database
and not a proprietary encrypted format.

- Format identifier: `paperos.backup`
- Container version: `1`
- Database schema version written: `2`
- Settings document version: `2`
- Extension: `.paperosbackup`
- Encryption: none
- Compression: deflate for metadata, stored (uncompressed) for book and cover
  payloads

A backup is a replacement snapshot. Restoring it is a full replacement of the
library and settings, never a merge. See `backup-restore.md`.

## Container layout

```
manifest.json                 UTF-8 JSON, no BOM
manifest.sha256               hex SHA-256 of manifest.json
database.json                 UTF-8 JSON snapshot of all tables
settings.json                 settings envelope
books/000001.epub             one stored file per document
books/000002.pdf
covers/000001.jpg             one stored file per available cover
covers/000003.png
```

File names under `books/` and `covers/` are sequence numbers assigned while
writing the backup. They are not the original imports, not the document IDs and
not user-visible titles. The manifest links each file to its row through
`documentId`.

Every ZIP entry must be a regular file. Directory entries, symbolic links,
encrypted entries, unsupported compression methods, duplicate names, absolute
paths, drive letters, backslashes, empty segments, `.`/`..` segments and names
outside the safe character set are rejected during preflight.

## `manifest.json`

Example (values shortened):

```json
{
  "format": "paperos.backup",
  "version": 1,
  "appVersion": "1.2.0 (3)",
  "schemaVersion": 2,
  "createdAt": "2026-11-01T10:15:30.000Z",
  "counts": {
    "documents": 1,
    "bookmarks": 1,
    "annotations": 2,
    "notes": 1,
    "tasks": 1,
    "locations": 1
  },
  "entries": [
    {
      "path": "database.json",
      "type": "database",
      "bytes": 12345,
      "sha256": "..."
    },
    {
      "path": "settings.json",
      "type": "settings",
      "bytes": 987,
      "sha256": "..."
    },
    {
      "path": "books/000001.epub",
      "type": "book",
      "bytes": 123456,
      "sha256": "...",
      "documentId": "doc_..."
    }
  ],
  "libraryBytes": 124000,
  "warnings": []
}
```

Fields:

| Field | Meaning |
| --- | --- |
| `format` | Must be `paperos.backup`. |
| `version` | Container format version. PaperOS 1.2 writes and accepts `1`. A higher value is rejected with an "update PaperOS" message. |
| `appVersion` | Human-readable writer version, for diagnosis only. |
| `schemaVersion` | Database schema expected by the rows. Must equal 2 in PaperOS 1.2. Older and newer schemas are rejected. |
| `createdAt` | UTC ISO-8601 timestamp. |
| `counts` | Row counts for `documents`, `bookmarks`, `annotations`, `notes`, `tasks` and `locations`. Checked against `database.json`. |
| `entries` | Payload list. Must contain exactly one `database` and one `settings` entry; all other entries are `book` or `cover`. |
| `libraryBytes` | Sum of all book and cover bytes. Checked against the entries. |
| `warnings` | Non-fatal omissions, currently a missing cover. Shown before restore. |

Each entry has:

| Field | Meaning |
| --- | --- |
| `path` | Archive path. Book files must be flat under `books/`; covers flat under `covers/`. |
| `type` | `database`, `settings`, `book` or `cover`. |
| `bytes` | Uncompressed byte length. Checked against the ZIP header and again after extraction. |
| `sha256` | Lowercase SHA-256 of the extracted bytes. |
| `documentId` | Required for `book` and `cover`; must name exactly one document row. |

## `manifest.sha256`

The file contains the SHA-256 of the exact bytes of `manifest.json`, followed by
two spaces and the file name, for example:

```
6f1d...c2  manifest.json
```

The parser accepts an optional `*` before the name and surrounding whitespace.
It does not accept a different digest, mixed text, or a checksum for another
file. This detects accidental corruption and casual modification of the
manifest; it is not a digital signature.

## `database.json`

```json
{
  "format": "paperos.database",
  "version": 1,
  "schemaVersion": 2,
  "tables": {
    "documents": [],
    "bookmarks": [],
    "annotations": [],
    "notes": [],
    "tasks": [],
    "locations": []
  }
}
```

Rows are selected inside one SQLite transaction with `SELECT * ... ORDER BY
rowid`, so the snapshot cannot contain two different versions of the same table.
The rows use the same columns as the live schema. Documents are never stored
inside SQLite as blobs; only their private paths, metadata, progress and
references are recorded.

The table order is stable: `documents`, `bookmarks`, `annotations`, `notes`,
`tasks`, `locations`. Restoring deletes child tables before `documents` and
inserts documents first, so foreign keys stay valid.

Restore validates:

- table names are exactly the six allowed names;
- every row is an object;
- required columns and types are present;
- IDs are unique within their table;
- all date and time columns are integer epoch milliseconds, and task
  `due_date` is a `yyyy-MM-dd` string;
- boolean columns are integer flags `0` or `1`;
- page/fraction progress values are in range;
- bookmarks, annotations and other child rows point at a document in the
  backup;
- annotation and bookmark locators are non-empty strings;
- no document row is left without a book file;
- manifest counts and entry relationships agree.

The rows are then inserted into a fresh, real SQLite database at the current
schema version and queried back before the live database is touched.

## `settings.json`

This is the same envelope used by the app:

```json
{
  "version": 2,
  "appearance": { "...": "..." },
  "reader": { "...": "..." },
  "launcher": { "...": "..." },
  "home": { "...": "..." },
  "display": { "profile": "eink" },
  "askOnExit": true
}
```

A legacy document with no `version` key and no `display` section remains
readable. A present version outside `1..2`, invalid JSON, or wrong types abort
the restore; they do not fall back to defaults.

## Size and entry limits

PaperOS refuses work before or during extraction when:

| Limit | Value |
| --- | --- |
| ZIP entries | 20,050 |
| Total uncompressed bytes | 8 GiB |
| One payload entry | `maxImportBytes + 16 MiB` |
| `database.json` or `settings.json` | 64 MiB |
| `manifest.json` | 4 MiB |
| `manifest.sha256` | 1 KiB |
| Documents | 10,000 |
| Path length | 200 characters |

Archive bytes are also compared with the compressed payload total, so a
decompression bomb cannot silently expand beyond the declared limits.

## Integrity and trust model

- ZIP structural checks, declared-size checks and per-entry SHA-256 are all
  enforced. The archive reader also rejects malformed or truncated entries.
- The archive is untrusted input. It is never extracted by joining an archive
  path to a filesystem path; payloads are copied to flat names in private
  staging directories.
- A valid checksum proves only that the bytes match the manifest. It does not
  prove who created the archive and does not make an untrusted archive safe to
  merge. Restore still validates every row and relationship.
- The format is not encrypted and is not signed. Anyone who can read the file
  can read the books, notes, settings and reading history inside it. Anyone who
  can rewrite it can produce a different valid archive. See
  `security-and-privacy.md`.
- No version of PaperOS 1.2 invents encryption or accepts password-protected
  ZIPs. An encrypted archive is rejected with an explicit message.

## Compatibility

PaperOS 1.2 accepts format version 1 and schema version 2. It rejects:

- container versions newer than 1;
- database schema versions other than 2, including a newer schema from a future
  PaperOS release;
- settings document versions newer than 2;
- any ZIP path or relationship violation described above.

There is no downgrade path. A backup from a future release must be opened with
a future PaperOS release.
