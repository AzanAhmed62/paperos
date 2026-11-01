# Security and privacy

PaperOS is a local-first Android app. It has no account system, no cloud sync,
no analytics, no advertising SDK, no remote book fetching and no content-path
network calls. Reading, search, notes, tasks, annotations and backups are local
operations.

This document states what the code does, what the Android package declares, and
where the limits are. It does not claim that a debug manifest is a release
manifest, and it does not claim that an untrusted backup is authenticated.

## Android permissions and components

The hand-written release manifest (`android/app/src/main/AndroidManifest.xml`)
declares:

- **no `INTERNET` permission**;
- **no storage permission**, including `READ_EXTERNAL_STORAGE`,
  `WRITE_EXTERNAL_STORAGE`, `MANAGE_EXTERNAL_STORAGE` and
  `ACCESS_MEDIA_LOCATION`;
- no camera, microphone, contacts, location, SMS, call-log or advertising-ID
  permission;
- `android:allowBackup="false"` and
  `android:fullBackupContent="false"`, so Android does not automatically upload
  app-private reading data through cloud backup;
- one exported activity, `MainActivity`, because it must be launchable, can be
  selected as a Home app, and accepts `VIEW` intents for PDF and plain text;
- `<queries>` entries for launcher activities, Home activities, PDF viewers and
  the Flutter text-processing intent. These are visibility declarations, not
  permissions.

The debug manifest is expected to add `INTERNET` for Flutter's development
tooling. Debug artifacts are not release artifacts. The release build's merged
manifest must be audited separately; see `release-process.md`.

## Storage model

- Imported books and covers are copied into the app's private documents
  directory. No broad filesystem access is requested.
- SAF grants are scoped to the folder or file the user chooses. PaperOS stores
  the granted tree URI for Files browsing, but never assumes that a grant lasts
  forever or that a content URI is a normal file path.
- The library metadata lives in a private SQLite database. Books are files, not
  database blobs.
- Notes, tasks, settings and reading positions stay in app-private storage.
- Deleted library files are moved into app-private trash rather than immediately
  unlinked.
- Backup archives are written to app-private staging first, then streamed to the
  destination document URI the user selects.

App-private storage is not a promise of forensic secrecy. A rooted device, a
debug build, an OS-level backup tool, or malware with equivalent privileges may
be able to read it. PaperOS does not add its own database or archive encryption
in 1.2.

## Backup files are not encrypted

A `.paperosbackup` is a plain ZIP. It contains:

- the full text of every imported book;
- covers;
- reading progress and history;
- bookmarks, highlights, annotations and notes;
- tasks;
- settings, including pinned app package names;
- SAF folder URIs.

Anyone who can read the file can read that content. Anyone who can modify it can
construct a different archive. The per-entry SHA-256 and the manifest checksum
detect corruption and casual modification; they are **not** a signature and do
not authenticate the author.

PaperOS 1.2 deliberately does not invent encryption. It rejects encrypted ZIP
entries instead of pretending to support them. A future encryption format must:

- use a mature, reviewed library and a standard password-based KDF;
- store a verifiable authentication tag;
- never store the password in plaintext;
- fail closed on a wrong password or a modified archive;
- document recovery and compatibility rather than claiming a broken file is
  "probably fine".

Users who need to move a backup through an untrusted channel should encrypt the
file with a tool they trust, or keep it on local media. PaperOS cannot open an
externally encrypted container directly.

## Untrusted archive handling

Restore treats the archive as hostile input. It checks ZIP structure, entry
names, duplicate names, directory entries, symlinks, encryption flags,
compression methods, declared and actual sizes, entry counts, global limits,
manifest checksums, per-entry checksums, JSON shape, table/column allowlists,
types, ranges, identifiers, counts, foreign keys, SQLite integrity and file
relationships before committing.

Archive paths are never joined directly to a filesystem path. Payloads are
extracted to flat sequence names in private staging directories. A traversal
attempt is rejected before extraction. Missing attachments, duplicate document
IDs, unexpected files and future schema versions abort the restore.

Restore performs a safety snapshot first and does not delete the current library
before the selected backup has been validated. The live database replacement is
one transaction. See `backup-restore.md` for the exact sequence and the
cross-store crash window.

## Reader and import parsing

- EPUB files are parsed by PaperOS' own bounded parser, not a WebView and not a
  remote rendering service. Archive paths, XML entity expansion and declared
  unbounded entries are treated as untrusted.
- PDFs are rendered by Android's `PdfRenderer` through a platform channel.
- Text imports are decoded locally and paginated locally.
- Import size and page limits live in `lib/config/app_config.dart`.
- Malformed archives must produce a recoverable error, not an endless spinner
  or a partial library row.

## Signing and release integrity

Production signing is fail-closed. The release build requires user-owned
credentials supplied through an untracked `android/key.properties` file or
external Gradle properties/environment variables. The debug keystore is only
used for debug builds. PaperOS never generates a keystore, chooses a password,
or falls back to debug signing for a release build.

There is no remote update channel. A release APK/AAB is only as trustworthy as
the machine and key used to build it. Do not distribute an artifact that was
signed with a shared or debug key.

## Dependency surface

The security-sensitive dependencies are:

- `archive` for ZIP structure and extraction;
- `crypto` for SHA-256;
- `sqflite` for SQLite;
- `shared_preferences` for settings;
- `file_picker` for user-driven SAF selection.

No package in the app implements a bespoke cipher or password prompt. Versions
are pinned in `pubspec.yaml`/`pubspec.lock`; `flutter pub outdated` reports
available upgrades but upgrades are not applied blindly, especially where they
raise the minimum Dart/Flutter version.

## Known limitations

- No hardware validation has been performed; see `manual-testing.md`.
- Backups are unencrypted and unsigned.
- The safety snapshot and settings/database commit cannot be one atomic
  cross-store transaction.
- A malicious but structurally valid backup still replaces the library after
  the user confirms it. Integrity checks are not a trust decision.
- The debug manifest contains `INTERNET`; only a release manifest audit is
  evidence for distribution.
- The app's private trash and safety snapshots are not user-exportable through
  the UI in 1.2.

## Audit commands

Run these on the actual release artifact, not on an assumption:

```powershell
# Merged release manifest
Get-Content build\app\intermediates\merged_manifests\release\AndroidManifest.xml

# APK permissions and badging
& "$env:ANDROID_HOME\build-tools\<version>\aapt.exe" dump badging path\to\app-release.apk

# AAB manifest (manifest is inside the bundle's base module)
& "$env:ANDROID_HOME\build-tools\<version>\aapt2.exe" dump xmltree path\to\app-release.aab --file base/manifest/AndroidManifest.xml
```

Expected result: no `android.permission.INTERNET`, no broad storage permission,
no unexpected exported component and no unrelated service. A missing release
artifact is not a pass.

See `release-process.md` for the commands used in this repository.
