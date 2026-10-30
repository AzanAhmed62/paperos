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

## Current behaviour

### Home

Paper Home shows, in order: a live clock, the document you were last reading,
the tasks due today (plus undated tasks), recent documents, and an entry to the
app drawer. A task added on Home belongs to today. Paging the Tasks screen to
another day does not change what Home calls "today".

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
- Keep reading position across font, margin, line-height, page-theme, and
  orientation changes with a chapter-relative EPUB locator. Progress writes are
  debounced while reading and flushed when the reader closes.
- Read plain text with Dart-side pagination, adjustable size and spacing,
  page-turn modes, page numbers, and persisted progress.
- Optional keep-screen-on while a document is open.

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
Home sections and clock, app-drawer system-app visibility, pinned apps, storage
information, remove-all, and the bundled font licences. Settings are stored as
one JSON document in `shared_preferences`.

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
| PDF native dispose and page bounds | Partially verified | Backend tests cover lifecycle and navigation; actual rendering needs Android. |
| SAF file/folder browsing | Implemented but runtime-unverified | Kotlin channel and Dart service exist; unit tests cover channel mapping. |
| PDF rendering on screen | Implemented but runtime-unverified | Uses `PdfRenderer`; no device or emulator was available. |
| EPUB touch selection and visual typography | Implemented but runtime-unverified | The reader chrome and page text pass widget tests, and annotation spans/scroll mapping pass backend tests; real touch handles, theme rendering, scrolling feel, and e-ink refresh need a device. |
| Import through the system picker | Implemented but runtime-unverified | Needs a real Android picker and provider. |
| Home-role request, app discovery, app launch | Implemented but runtime-unverified | Platform channels compile; behaviour needs Android. |
| Keep-screen-on | Implemented but runtime-unverified | Platform channel compiles; behaviour needs Android. |
| Release permission surface | Verified statically | The release manifest declares no `INTERNET` or storage permission. See the audit in the final report. |
| Cloud sync, accounts, analytics | Not implemented | Explicitly out of scope. |
| PDF highlights and annotations | Not implemented | The native PDF path renders bitmaps and does not expose selectable text. |
| Fixed-layout EPUB, DRM, audio/video, MathML, scripting | Not supported | The EPUB path is a bounded reflowable-text reader, not a browser. |
| General file manager / full launcher replacement | Not implemented | Files is SAF-scoped and PaperOS is not a replacement OS. |

## Requirements

- Flutter with Dart `^3.13.0` (the EPUB parser's XML dependency requires it).
  This repository was last analysed, tested, and built with
  **Flutter 3.47.7 / Dart 3.13.5**.
- Android SDK, Java 17 or newer, `minSdk` 24. `compileSdk` and `targetSdk` follow
  the Flutter SDK's pinned versions. The project's Gradle 8.14 wrapper does not
  support Java 25; this checkout built with JDK 21 selected via
  `flutter config --jdk-dir`. If Flutter auto-selects an Android Studio JBR that
  is too new, point it at a JDK 17–24 installation.
- The Flutter Gradle plugin provisions an NDK even though this project compiles
  no native sources. Flutter 3.47.7 pins `ndkVersion` 28.2.13676358, and this
  checkout has that NDK installed through the Android SDK CLI; a build fails
  during configuration if no NDK is present.
- For tests: the `sqlite3` library used by `sqflite_common_ffi` must be available
  through the Dart build hook cache or a system SQLite installation.
- `android/local.properties` must point at the local Android SDK and the Flutter
  SDK. On this Windows checkout it contains:

  ```properties
  sdk.dir=C:/Users/Parwana/AppData/Local/Android/Sdk
  flutter.sdk=C:/DEV/build-cache/flutter
  ```

  Paths are machine-specific; do not copy them blindly.

## Build and test

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to
`build/app/outputs/flutter-apk/app-debug.apk`.

Recorded v1.1.0 debug build (2026-10-30):

- package `dev.paperos.app.debug`, version `1.1.0-debug` (versionCode 2);
- `compileSdk` 36, `targetSdk` 36, `minSdk` 24;
- 196,843,454 bytes (187.72 MiB);
- SHA-256 `6B3E9198637A685315D68D9050707C9B057C1BE22039A77523424B35A9B8711B`.

The final release variant merged manifest was generated after the version bump:
version `1.1.0` (versionCode 2), no `INTERNET` permission, no storage
permission, and only the AndroidX-generated dynamic-receiver permission. The
debug APK above contains `INTERNET` because the Flutter tool adds it to debug
builds.

The suite currently contains **134 passing tests**:

- `test/unit/` — EPUB parsing and archive safety, EPUB pagination/locators,
  text pagination, PDF backend lifetime/navigation, and file-browser channel
  mapping.
- `test/data/` — repositories, filters/sorts, import deduplication, annotations,
  bookmark locators, settings, and the real v1-to-v2 SQLite migration.
- `test/reader/` — EPUB opening, paged/scroll switching, annotation and bookmark
  persistence, and malformed-book recovery.
- `test/widget/` — the real app shell, reader chrome, EPUB library filters and
  sorting, Tasks, Files, the note editor, the search field, and task-result day
  selection in search.

No physical Android device or emulator was connected during this work, so SAF
picker interaction, native PDF rendering, EPUB text-selection handles and e-ink
refresh, the Home role, installed-app discovery and launching, and
keep-screen-on remain runtime-unverified. See the manual checklist below.

Design notes:

- [`docs/architecture.md`](docs/architecture.md) — components, data flow, and
  security boundaries.
- [`docs/reader-engine-decision.md`](docs/reader-engine-decision.md) — why v1.1
  uses a bounded native parser rather than a WebView or Readium.
- [`docs/database-migrations.md`](docs/database-migrations.md) — the additive
  v1-to-v2 migration and recovery expectations.
- [`docs/roadmap.md`](docs/roadmap.md) — completed v1.1 work, later candidates,
  and explicit non-goals.
- [`docs/manual-testing.md`](docs/manual-testing.md) — the device checklist this
  environment could not run.

## Manual phone checklist

1. Install `app-debug.apk` and launch it normally.
2. Import an EPUB 3, an EPUB 2, a PDF, and a `.txt` file through the system
   picker; reopen each after killing and restarting the app.
3. Open the EPUB, use the nested table of contents and in-book search, and
   confirm the chosen passage is reached.
4. Switch between paged and continuous scrolling, change font size, line
   height, margins, page theme, and device orientation. Confirm the same passage
   stays on screen.
5. Select text, add a highlight, an underline, and an attached note; edit and
   delete one; reopen the book and confirm they remain at the same passage.
6. Open the annotation library, jump to a passage, and confirm deletion of a
   document removes its annotations without affecting another book.
7. Bookmark an EPUB passage, leave, return, and confirm both the bookmark and
   the reading position resume at the passage rather than the old page number.
8. Delete the app-private copy of an imported EPUB, re-import the same source,
   and confirm there is still one row with its progress and annotations intact.
9. In Files, add a folder, browse into a subfolder, open a supported document,
   then remove the folder and confirm the grant is released.
10. Read a PDF past page 1, leave, and confirm the resumed page; toggle
    keep-screen-on and confirm the display stays awake.
11. Run a text file to the last page and confirm progress and completion state.
12. Add tasks on Home and on another Tasks day; confirm Home still shows today
    only, and that searching for a dated task opens its day.
13. Write a note, leave immediately, reopen it, and confirm the text and edit
    timestamp; repeat with the system back gesture.
14. Request the Home role in Settings, choose PaperOS as Home, open the app
    drawer, pin an app, and launch it.
15. Change theme, text size, and reader settings; restart and confirm they
    persist.
16. Remove every document and confirm the library is empty and the app remains
    usable.

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
    errors/                 PaperException
    platform/               native bridges (files, PDF, apps, keep-screen-on)
    storage/                SQLite schema/opener, app-private storage
    utils/                  ids, dates, formatting
  features/
    annotations/            highlight, underline and note domain/data
    home/ library/ files/ notes/ tasks/ settings/ launcher/ search/
    reader/
      epub/                 bounded EPUB parser, book model and text backend
  shared/widgets/           design-system widgets
  theme/                    palette, spacing, typography, ThemeData
```

Content lives in one SQLite database (documents, progress, bookmarks,
annotations, notes, tasks, granted folders). EPUB files stay as app-private
files and are never copied into SQLite. Settings live separately in
`shared_preferences` so that reading the theme never opens the content database.
Imported files are copied into app-private storage; the library never depends on
a live SAF grant.

## Design rules

`lib/theme` holds a monochrome palette, a spacing scale, and a typography scale
built on bundled Noto Serif faces. `lib/shared/widgets` provides the reusable
surfaces. The rules are: no colour, no ripple, and no ornament that is not
load-bearing.

## Known limitations

- No device or emulator verification. The native surfaces and touch behaviours
  listed above are compile-checked, unit/widget-tested, and statically reviewed,
  not run on hardware.
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
- `flutter_readium` was not fully prototyped because its current Android
  requirements conflict with the deliberately preserved toolchain; the
  reasoning and fallback options are recorded in
  [`docs/reader-engine-decision.md`](docs/reader-engine-decision.md).
- Release signing is not configured; release builds currently use the debug
  signing key and must not be distributed as-is.
