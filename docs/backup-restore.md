# Backup and restore

PaperOS 1.2 can save the entire local library and settings into one
`.paperosbackup` file and restore it later. This is the only supported way to
move a PaperOS library between installations. The format is described in
`backup-format.md`.

## What is included

- the document rows: title, original file name, source URI, format, byte size,
  page count, author, publisher, language, identifier, description, status,
  favourite flag, progress, open count, timestamps, cover reference and
  fingerprint;
- the private file for every document, including PDFs, EPUBs and text files;
- cover images that still exist;
- bookmarks, including labels, excerpts, chapter titles and locators;
- annotations, including type, excerpts, notes, chapter positions, orphan
  state and locators;
- notes;
- dated and undated tasks;
- SAF folder references (the persisted `content://` tree URIs);
- settings: appearance, reader, launcher favourites, Home sections, display
  profile and exit confirmation.

The SQLite database itself is not copied as a live file. Rows are read inside a
transaction and written as JSON, which is what makes the archive a portable
snapshot rather than a possibly inconsistent copy of a database with a write
journal.

## What is not included

- books are not stored inside the database and are not reconstructed from
  metadata;
- the app's trash directory;
- Android runtime permissions or a live SAF grant beyond the URI itself (the
  provider decides whether an old tree URI is still usable);
- the OS launcher selection, Android Home role, or any state outside PaperOS;
- downloaded or generated files that are not referenced by the library;
- the signing key, app preferences outside `paperos.settings.v1`, or device
  identifiers.

## Creating a backup

1. Open **Settings**.
2. Choose **Back up library**.
3. PaperOS takes a consistent database snapshot, asks every document and cover
   for its current size and SHA-256, writes the archive and verifies its own
   manifest before offering it to the system save picker.
4. Choose a destination with the Android Storage Access Framework picker. The
   archive is streamed to the chosen document URI and the temporary private
   copy is deleted.

No storage permission is requested. The user chooses exactly one file
destination.

If a document is missing its private file, backup stops and names the document.
PaperOS does not silently omit a book. A missing cover is different: a cover is
optional metadata, so the backup records a warning, clears that cover
reference, and continues.

If the save picker is cancelled, no file is left at the destination and the
private temporary archive is removed.

## Restoring a backup

1. Open **Settings**.
2. Choose **Restore from backup**.
3. Pick a `.paperosbackup` file. PaperOS copies it to its private cache using a
   bounded stream (the selected file is never trusted in place).
4. Review the preview: creation date, app version, counts for every table, book
   and cover totals, and warnings.
5. Confirm the replacement. The preview explicitly says that the current
   library and settings will be replaced.
6. PaperOS shows progress and allows cancellation until the final commit.

Restore is a **full replacement**, not a merge. This is deliberate: two
libraries can contain the same document identity with different progress,
bookmarks and annotations, and there is no honest universal rule for choosing a
winner. After a successful restore the library and settings are exactly the
backup's contents.

### Restore sequence

1. **Safety snapshot.** A backup of the current library and settings is written
   to app-private `safety-backups/` before the selected archive is touched.
2. **Preflight.** The ZIP directory, names, sizes, compression, encryption,
   entry count and path safety are checked. `manifest.sha256` is verified.
3. **Manifest validation.** Format version, database schema version, counts,
   entry paths, types, sizes, duplicates, document links, library byte total
   and unexpected files are checked.
4. **Extraction to private staging.** Payloads are copied to flat staging names.
   Each extracted size and SHA-256 is checked against the manifest.
5. **Database JSON validation.** Structure, table names, row shapes, columns,
   identifiers, flags, ranges and child relationships are checked.
6. **Settings validation.** The settings envelope is decoded strictly.
7. **Real SQLite staging.** A fresh database at schema version 2 is created,
   rows are inserted, foreign keys are checked, counts are compared, and SQLite
   `PRAGMA integrity_check` must return `ok`.
8. **Attachment copy.** Book and cover files are copied to new unique names in
   the live library directories. They are not moved or overwritten.
9. **Commit.** Settings are imported, then all six tables are replaced inside
   one transaction. If the transaction fails, the old settings are restored and
   the newly copied files are deleted.
10. **Cleanup.** Files no longer referenced by the restored rows are moved to
    the app trash. Old safety snapshots beyond the retention limit are pruned.

Steps 1–8 do not modify the current library. The database replacement is
transactional. A failure before step 9 leaves the current library in place.

### Rollback and failure limits

- If validation or copying fails, newly copied files are deleted and the live
  database is untouched.
- If the live table transaction fails, settings are restored to their exact
  previous raw value and the newly copied files are deleted.
- If the process is killed after the settings write but before the database
  commit, the database is still the old one while settings may already be the
  restored document. This cross-store window exists because
  `shared_preferences` and SQLite cannot share one transaction. The safety
  snapshot is always created before this point.
- If the process is killed after the database commit but before trash cleanup,
  the restored library is valid; old files are unreferenced and harmless.
- Cleanup of replaced files is best effort. A cleanup failure does not roll
  back a valid restore.

### Safety snapshots

Safety snapshots use the same format and are stored under the app's private
`safety-backups/` directory. The newest three are kept. They are not offered in
the normal file picker unless the app gains an export-safety feature in a later
release; they exist for recovery after a bad restore.

A safety snapshot can fail if the current library already contains a missing
attachment or is too large. In that case restore stops before changing
anything.

## Cancellation

The Cancel button stops the operation at the next safe checkpoint. Cancellation
is checked between files and between restore phases, not inside one large file
copy or one SQLite transaction. A multi-gigabyte file can therefore take time to
reach the next checkpoint. Cancelling before the final commit leaves the live
library untouched; the temporary archive, staging directory and copied files
are removed.

## Untrusted archives

Every downloaded or received backup is untrusted. The restore path rejects:

- path traversal, absolute paths, drive letters, backslashes, empty path
  segments and unsafe characters;
- duplicate or unexpected files, directory entries, symbolic links and
  encrypted entries;
- unsupported ZIP compression and archives above the size/entry limits;
- bad or missing manifest checksums;
- unknown future format or schema versions;
- corrupt JSON, unknown tables or columns, wrong column types and invalid
  flags/ranges;
- duplicate IDs, duplicate document files, duplicate covers and duplicate
  folder paths;
- child rows that refer to a missing document;
- documents with no book file, and covers that do not match the document row;
- counts that disagree with the manifest or tables that fail SQLite validation.

An archive that passes these checks is structurally valid, not necessarily
trusted. The checksum is not a signature and does not establish who created the
file. Restore still performs a full replacement only after the user confirms the
preview.

## Encryption

PaperOS 1.2 does not encrypt backups and does not ship a password prompt.
Encrypting the file externally is possible, but PaperOS cannot open an encrypted
container directly. Do not put a backup on a shared drive or send it through a
service you would not trust with your reading history, notes and highlights.

The format has no custom cryptography. A future encryption version must use a
mature, reviewed library, a real password-based key derivation function, and a
documented recovery story; it must not claim that a wrong password "probably"
worked.

## Tests

Automated tests run the real SQLite engine and cover:

- a populated round trip through every table, attachment, cover and the display
  profile;
- an empty-library backup restored over a populated one;
- cancellation before commit;
- a damaged payload that fails its checksum while the live library stays intact;
- a future manifest version;
- missing attachments;
- path traversal in a ZIP.

The SAF picker and Android document providers still require manual device
testing; see `manual-testing.md`.
