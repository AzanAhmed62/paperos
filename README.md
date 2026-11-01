# PaperOS

A quiet, local-first reading environment for Android, built with Flutter.

PaperOS is a single app, not a replacement operating system. It can be selected
as an Android Home app, but it still runs inside Android and does not replace the
platform. Inside the app are five destinations — **Home**, **Library**, **Files**,
**Notes**, and **Settings** — plus full-screen overlays for the reader, the task
checklist, search, the note editor, and the app drawer. Everything is drawn in a
single monochrome white / warm / ink palette with no accent colour and no
decorative chrome.

Everything the app stores stays on the device. There are no accounts, no cloud
sync, no analytics, and no network calls in the content path. The release
manifest declares no storage permission and no `INTERNET` permission; the debug
manifest adds `INTERNET` only because the Flutter development tool needs it for
hot reload and debugging.

Current version: **1.2.0+3** (`dev.paperos.app`, schema version 2).

## What is new in 1.2

- **Full local backup and restore** through the Android Storage Access Framework.
  A `.paperosbackup` archive contains documents, covers, metadata, progress,
  locators, bookmarks, annotations, notes, tasks, granted folders, and settings.
  Restore is a validated full replacement with a safety snapshot, not a merge.
- **Annotation export** as Markdown or JSON, with title, author, export date,
  chapters, excerpts, notes, annotation type, bookmarks, locations, and explicit
  orphan disclosure.
- **Persistent Standard / E-Ink Friendly display profiles** that change motion,
  contrast, touch targets, clock cadence, reader flow, page-turn zones and
  render-time typography. The E-Ink profile is software-only; it does not fake a
  vendor refresh API.
- **Fail-closed release signing** using user-owned credentials, plus optimized
  release/split-ABI build configuration and a documented manifest audit.
- Reader reliability, empty/error states, long-text handling and responsive
  layout improvements covered by the automated suite.

## Current behaviour

### Home

Paper Home shows, in order: a live clock, the document you were last reading,
the tasks due today (plus undated tasks), recent documents, and an entry to the
app drawer. A task added on Home belongs to today. Paging the Tasks screen to
another day does not change what Home calls "today". With the E-Ink profile the
clock updates once at each minute boundary instead of every second.

### Library and reader

- Import PDF, EPUB 2/3, and plain-text files through the system file picker
  (Android SAF). Imports are copied into app-private storage, so a later SAF
  grant expiry cannot make a book disappear.
- Re-importing the same source is a no-op. If the private copy disappeared, the
  existing row is relinked instead of duplicated, preserving progress,
  bookmarks, annotations, and a user-chosen title. A SHA-256 fingerprint also
  recognises identical content selected through a different provider URI.
- List and search by title, author, or file name; favourite, rename, and remove
  documents. Filters cover all formats plus EPUB, PDF, TXT, recent, favourites,
  unread, in-progress, and completed. Sorting is deliberately limited to title,
  author, and recently opened; remove-all moves files to the app's trash
  directory first.
- Read PDFs through Android's native `PdfRenderer`, with persisted page
  progress and bookmarks.
- Read EPUB without a WebView or network access. The bounded parser handles the
  package document, EPUB 3 navigation, EPUB 2 NCX navigation, nested contents,
  metadata, and covers. Reflowable chapters support paged and continuous
  scrolling modes, font size, line height, margins, page theme, page numbers,
  nested table of contents, in-book search, bookmarks, and a persisted reading
  position.
- Select EPUB text to add a highlight, underline, or attached note. Annotations
  can be edited above their original passage, listed in a per-book annotation
  library, reopened at their anchor, or deleted. Unresolved anchors are kept and
  marked orphaned rather than silently discarded.
- Export a book's annotations as Markdown or JSON through the system save
  picker. The export states when a chapter or bookmark location cannot be
  resolved; it does not silently drop orphaned user work.
- Keep reading position across font, margin, line-height, page-theme, display
  profile, and orientation changes with a chapter-relative EPUB locator.
  Progress writes are debounced while reading and flushed when the reader
  closes.
- Read plain text with Dart-side pagination, adjustable size and spacing,
  page-turn modes, page numbers, and persisted progress.
- Optional keep-screen-on while a document is open.

### Backup and restore

Settings offers **Back up library** and **Restore from backup**. Backup streams
a complete, checksummed archive to a destination chosen with the SAF save
picker. Restore shows a preview with counts and warnings, explicitly replaces the
current library after confirmation, and creates a safety snapshot first. Invalid
archives, unsafe paths, future versions, missing attachments, duplicate
identifiers, broken relationships, and bad checksums are rejected before live
data is changed. See [`docs/backup-format.md`](docs/backup-format.md) and
[`docs/backup-restore.md`](docs/backup-restore.md).

### Files

Files is a real SAF document browser, not a task list. The user grants one or
more folders through the system folder picker. PaperOS persists each grant and
can then list children, descend into subfolders, and copy a supported file into
the library for reading. Unsupported files are shown honestly as unsupported.
PaperOS never asks for broad storage access and never browses outside the folders
the user granted.

### Tasks

Tasks are a persistent dated checklist. A task can belong to a day or have no
date. The Tasks screen browses one day at a time, with undated tasks shown on
every day; Home always shows today's tasks. Search results for a dated task
select that task's day before opening the checklist.

### Notes

A note is a title and a plain body. Saves are debounced while typing, opening a
note does not rewrite it, and leaving the editor flushes the final keystrokes
before the route closes.

### Search

One search box covers document titles and file names, note titles and bodies,
and task titles. Each result opens the surface that owns it.

### Settings

Settings covers the monochrome paper style, interface text size, serif reading
face, reader size and spacing, paged/scroll flow, page theme, keep-screen-on,
display profile, Home sections and clock, app-drawer system-app visibility,
pinned apps, storage information, backup/restore, remove-all, and the bundled
font licences. Settings are stored as one versioned JSON document in
`shared_preferences`; legacy documents without a version remain readable.

### Launcher surfaces

The app drawer lists launchable apps through a platform channel, can show or hide
system apps, supports pinned apps, and can launch an app. Settings also exposes
the Android Home-role request. These surfaces require Android and have not been
exercised end to end in this environment.

## Verification status

The statuses are deliberately narrow. "Verified" means automated tests exercise
the shipped code, not that every visual detail was inspected on hardware.

| Area | Status | Evidence / remaining gap |
| --- | --- | --- |
| Navigation shell and boot | Verified | Widget test boots the real app and its five destinations. |
| Tasks repository, day selection, Home independence | Verified | SQLite repository tests plus provider and widget tests. |
| Note editor save/leave behaviour | Verified | Widget tests cover open-without-write, back-without-write, and flush-on-back. |
| Library, bookmark, and annotation persistence | Verified | Repository tests run against the real SQLite engine. |
| Schema v1 to v2 migration | Verified | A populated v1 database is upgraded and its documents, progress, bookmarks, notes, and tasks are read back. |
| EPUB 2/3 parsing and malformed-archive safety | Verified | Unit tests cover EPUB 2 NCX, EPUB 3 navigation, nested contents, metadata, unsafe paths, declared unbounded entries, non-EPUB input, empty spines, and image-only chapters. |
| EPUB import, metadata, cover, duplicate recognition, stale-row relink | Verified | Repository tests exercise same-source re-import, fingerprint dedup, revived private copies, and preservation of user data. |
| EPUB pagination, locator restore, search, annotation ranges | Verified | Backend and reader-session tests cover typography changes, scroll/paged switching, orphan recovery, and malformed-book errors. |
| EPUB reader chrome and library filters | Verified | Widget tests open the real reader, read the page, exercise every filter, search by author, and sort through the menu. |
| Text pagination | Verified | Unit tests cover empty, short, long, lazy, and fraction cases. |
| Backup archive validation and full restore | Verified in tests | Real SQLite round trip over every table, empty library, cancellation, damaged payload, missing attachment, future format, and path traversal. SAF transfer is not device-tested. |
| Annotation Markdown/JSON export | Verified | Structure, order, counts, safe filenames, graphics-free empty book, and orphan disclosure are unit-tested. |
| Standard/E-Ink display policy | Verified in tests | Profile parsing, conservative capabilities, policy values, clock cadence, render-time typography, settings v2 persistence, legacy decode and future rejection. Visual quality is not device-tested. |
| Settings v2 envelope and legacy settings | Verified | Version 1 documents remain readable; unsupported versions fail strict import. |
| PDF native dispose and page bounds | Partially verified | Backend tests cover lifecycle and navigation; actual rendering needs Android. |
| SAF file/folder browsing | Implemented but runtime-unverified | Kotlin channel and Dart service exist; unit tests cover channel mapping. |
| Backup save/restore through Android SAF | Implemented but runtime-unverified | Native streaming channel compiles in review; needs a real document provider. |
| PDF rendering on screen | Implemented but runtime-unverified | Uses `PdfRenderer`; no device or emulator was available. |
| EPUB touch selection and visual typography | Implemented but runtime-unverified | Reader chrome and page text pass widget tests; real touch handles, theme rendering, scrolling feel, and E-Ink ghosting need a device. |
| Import through the system picker | Implemented but runtime-unverified | Needs a real Android picker and provider. |
| Home-role request, app discovery, app launch | Implemented but runtime-unverified | Platform channels compile; behaviour needs Android. |
| Keep-screen-on | Implemented but runtime-unverified | Platform channel compiles; behaviour needs Android. |
| Release permissions | Static audit pending artifact | The hand-written release manifest declares no `INTERNET` or storage permission. The merged release manifest must be audited on a built artifact; see the final report. |
| Production signing | Not run | No owner keystore credentials were supplied. Release tasks fail closed rather than debug-sign. |
| Cloud sync, accounts, analytics | Not implemented | Explicitly out of scope. |
| PDF highlights and annotations | Not implemented | The native PDF path renders bitmaps and does not expose selectable text. |
| Backup encryption | Not implemented | Backups are plain ZIPs; see `security-and-privacy.md`. |
| Fixed-layout EPUB, DRM, audio/video, MathML, scripting | Not supported | The EPUB path is a bounded reflowable-text reader, not a browser. |
| Hardware E-Ink refresh | Not implemented | No documented, testable vendor API is wired up. |

## Requirements

- Flutter with Dart `^3.13.0` (the EPUB parser's XML dependency requires it).
  This repository was analysed, tested, and built with **Flutter 3.47.7 /
  Dart 3.13.5**.
- Android SDK, `minSdk` 24. `compileSdk` and `targetSdk` follow the Flutter
  SDK's pinned versions (36 at the time of writing).
- **JDK 17 or 21.** This checkout was built with JDK 21.0.12. Gradle 8.14's
  Kotlin DSL does not support JDK 25; do not point `JAVA_HOME` at Android
  Studio's JDK 25 if that is what the machine provides.
- The Flutter Gradle plugin provisions an NDK even though this project compiles
  no native sources. Flutter 3.47.7 pins `ndkVersion` 28.2.13676358; a build
  fails during configuration if no NDK is present.
- For tests, the `sqlite3` library used by `sqflite_common_ffi` must be available
  through the Dart build hook cache or a system SQLite installation.
- `android/local.properties` must point at the local Android SDK and Flutter
  SDK. Paths are machine-specific and the file is git-ignored.

## Build and test

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to
`build/app/outputs/flutter-apk/app-debug.apk`. Exact v1.2 artifact sizes,
hashes, manifest audit results and test totals are recorded in the final report
and [`docs/performance-report.md`](docs/performance-report.md).

Release builds require owner-supplied credentials and fail closed otherwise:

```bash
# with android/key.properties or PAPEROS_* credentials configured:
flutter build apk --release
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

There is no debug-signing fallback for release. An explicit unsigned analysis
build is possible only with `-Ppaperos.allowUnsignedRelease=true` and is not
installable or distributable. The full procedure, manifest audit, and signature
verification commands are in [`docs/release-process.md`](docs/release-process.md).

The automated suite contains the original 134 tests plus v1.2 backup,
annotation-export, display-profile, settings-envelope, and regression tests. The
exact total and result are recorded in the final report:

- `test/unit/` — EPUB parsing and archive safety, EPUB pagination/locators, text
  pagination, PDF backend lifetime/navigation, file-browser channel mapping,
  annotation export, and display policy.
- `test/data/` — repositories, filters/sorts, import deduplication, annotations,
  bookmark locators, settings, the real v1-to-v2 SQLite migration, and full
  backup/restore against real SQLite.
- `test/reader/` — EPUB opening, paged/scroll switching, annotation and bookmark
  persistence, and malformed-book recovery.
- `test/widget/` — the real app shell, reader chrome, EPUB library filters and
  sorting, Tasks, Files, the note editor, the search field, and task-result day
  selection in search.

No physical Android device or emulator was connected during this work, so SAF
picker interaction, backup save/restore through a document provider, native PDF
rendering, EPUB text-selection handles and E-Ink appearance, the Home role,
installed-app discovery and launching, and keep-screen-on remain
runtime-unverified. Production signing was not exercised because no owner
credentials were supplied. See the manual checklist below.

Design notes:

- [`docs/architecture.md`](docs/architecture.md) — components, data flow, and
  security boundaries.
- [`docs/backup-format.md`](docs/backup-format.md) — archive layout, manifest,
  checksums, limits, and versioning.
- [`docs/backup-restore.md`](docs/backup-restore.md) — user workflow, restore
  sequence, rollback, cancellation, and tests.
- [`docs/eink-profile.md`](docs/eink-profile.md) — profile behaviour, capability
  seam, and honest hardware limits.
- [`docs/release-process.md`](docs/release-process.md) — signing, builds,
  manifest audit, and release checklist.
- [`docs/security-and-privacy.md`](docs/security-and-privacy.md) — permissions,
  untrusted archives, privacy, and threat limits.
- [`docs/reader-engine-decision.md`](docs/reader-engine-decision.md) — why v1.1
  uses a bounded native parser rather than a WebView or Readium.
- [`docs/database-migrations.md`](docs/database-migrations.md) — the additive
  v1-to-v2 migration and recovery expectations.
- [`docs/performance-report.md`](docs/performance-report.md) — measured artifact
  size and test/build cost, with unmeasured runtime paths called out.
- [`docs/roadmap.md`](docs/roadmap.md) — completed work, later candidates, and
  explicit non-goals.
- [`docs/manual-testing.md`](docs/manual-testing.md) — the device checklist this
  environment could not run.

## Manual phone checklist

The authoritative 36-case checklist with explicit statuses is in
[`docs/manual-testing.md`](docs/manual-testing.md). In short:

1. Install and launch; confirm the five destinations and release manifest.
2. Import EPUB 3, EPUB 2, PDF, and `.txt`; reopen after force-stop.
3. Exercise contents, search, paged/scroll flow, typography, orientation,
   bookmarks, selection, annotation editing, and orphan display.
4. Re-import a stale private copy and duplicate content; confirm one row.
5. Use Files, Tasks, Notes, Home-role, app drawer, and keep-screen-on.
6. Back up a populated library, restore it, and compare every table and setting.
7. Try invalid archives, cancellation, and a restore that must leave the old
   library intact.
8. Export annotations as Markdown and JSON; verify orphan disclosure.
9. Switch to E-Ink Friendly and check motion, clock, selection, chrome, reader
   paging and visual quality on a real E-Ink panel.
10. Build with owner credentials; verify the release signature and audit the
    merged manifest for no `INTERNET` or broad storage permission.

## Architecture

State is plain Riverpod (`Notifier` / `AsyncNotifier`); there is no code
generation. Navigation is `go_router`, with the five destinations in a
`StatefulShellRoute.indexedStack` and overlays pushed on the root navigator.
Feature folders use `domain/`, `data/`, `application/`, and `presentation/`
where they need those layers.

```
lib/
  main.dart                 bootstrap (preferences override + PaperApp)
  app/                      router, destination shell, providers, PaperApp
  config/                   build-time configuration
  core/
    display/                profile, policy, capability seam, clock tick
    errors/                 PaperException
    platform/               native bridges (files, PDF, apps, keep-screen-on,
                            streaming backup document I/O)
    storage/                SQLite schema/opener, app-private storage
    utils/                  ids, dates, formatting
  features/
    annotations/            highlight, underline and note domain/data
    backup/                 archive validation, service, SAF controller
    display/                display provider and reader adjustments
    home/ library/ files/ notes/ tasks/ settings/ launcher/ search/
    reader/
      epub/                 bounded EPUB parser, book model and text backend
  shared/widgets/           design-system widgets
  theme/                    palette, spacing, typography, ThemeData
```

Content lives in one SQLite database (documents, progress, bookmarks,
annotations, notes, tasks, granted folders). EPUB and other files stay as
app-private files and are never copied into SQLite. Settings live separately in
`shared_preferences` so that reading the theme never opens the content database.
Imported files are copied into app-private storage; the library never depends on
a live SAF grant.

## Design rules

`lib/theme` holds a monochrome palette, a spacing scale, and a typography scale
built on bundled Noto Serif faces. `lib/shared/widgets` provides the reusable
surfaces. The rules are: no colour, no ripple, and no ornament that is not
load-bearing. The E-Ink profile increases contrast, target size and selection
visibility without adding a second visual language.

## Known limitations

- No device or emulator verification. Native surfaces, touch behaviours, SAF
  document-provider flows, backup transfer and E-Ink visuals are compile-checked,
  unit/widget-tested, and statically reviewed, not run on hardware.
- Backups are unencrypted and unsigned. They contain books, notes and reading
  history; store them on media you trust. PaperOS cannot open an externally
  encrypted container.
- Restore replaces the whole library. There is no merge mode, because no
  universal conflict rule has been proven safe.
- The settings write and SQLite commit cannot share one transaction. A process
  kill between them is a documented cross-store window; the safety snapshot is
  created before it.
- The E-Ink profile is software-only. No documented, testable vendor refresh API
  is wired up, so PaperOS does not claim to flash an E-Ink panel.
- The EPUB reader is intentionally text-first. It does not execute scripts, load
  remote resources, or reproduce publisher CSS, fixed-layout pages, comic
  panels, MathML, ruby, audio/video, media overlays, or DRM. Image-only spine
  items become an explicit placeholder rather than invented prose.
- EPUB positions are PaperOS CFI-style chapter/character locators, not literal
  EPUB DOM CFIs. They are stable inside PaperOS but are not a bookmark format
  that another EPUB application can import.
- PDF highlights and notes are not supported because the native PDF path
  renders bitmaps rather than exposing selectable text.
- A page-perfect visual comparison across all EPUB themes and Android font
  scales still needs a physical device.
- Production signing is not configured in this checkout. Release builds fail
  closed until an owner supplies credentials.
