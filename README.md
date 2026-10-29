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

- Import PDF and plain-text files through the system file picker (Android SAF).
- Copy imports into app-private storage, so a later SAF grant expiry cannot make
  a book disappear.
- List, search, favourite, rename, and remove documents; remove-all moves files
  to the app's trash directory first.
- Read text with Dart-side pagination, adjustable size and spacing, page-turn
  modes, page numbers, and persisted progress.
- Read PDFs through Android's native `PdfRenderer`, with the same persisted
  progress and bookmarks.
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
face, reader size and spacing, page-turn mode, keep-screen-on, Home sections and
clock, app-drawer system-app visibility, pinned apps, storage information,
remove-all, and the bundled font licences. Settings are stored as one JSON
document in `shared_preferences`.

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
| Library/bookmark/note persistence | Verified | Repository tests run against the real SQLite engine. |
| Text pagination | Verified | Unit tests cover empty, short, long, lazy, and fraction cases. |
| PDF native dispose and page bounds | Partially verified | Backend tests cover lifecycle and navigation; actual rendering needs Android. |
| SAF file/folder browsing | Implemented but runtime-unverified | Kotlin channel and Dart service exist; unit tests cover channel mapping. |
| PDF rendering on screen | Implemented but runtime-unverified | Uses `PdfRenderer`; no device or emulator was available. |
| Import through the system picker | Implemented but runtime-unverified | Needs a real Android picker and provider. |
| Home-role request, app discovery, app launch | Implemented but runtime-unverified | Platform channels compile; behaviour needs Android. |
| Keep-screen-on | Implemented but runtime-unverified | Platform channel compiles; behaviour needs Android. |
| Full-device appearance and gestures | Partially verified | Theme widget tests and static analysis pass; no hardware inspection. |
| Cloud sync, accounts, annotations, EPUB | Not implemented | Explicitly out of scope for this MVP. |
| General file manager / full launcher replacement | Not implemented | Files is SAF-scoped and PaperOS is not a replacement OS. |

## Requirements

- Flutter with Dart `>=3.10.7`. This repository was last analysed, tested, and
  built with **Flutter 3.47.7 / Dart 3.13.5**.
- Android SDK, Java 17 or newer, `minSdk` 24. `compileSdk` and `targetSdk` follow
  the Flutter SDK's pinned versions. The project's Gradle 8.14 wrapper does not
  support Java 25; this checkout built with JDK 21 selected via
  `flutter config --jdk-dir`. If Flutter auto-selects an Android Studio JBR that
  is too new, point it at a JDK 17–24 installation.
- The Flutter Gradle plugin provisions an NDK even though this project compiles
  no native sources. This checkout installed `ndk;27.0.12077973` through the
  Android SDK CLI; a build fails during configuration if no NDK is present.
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

The suite currently contains **91 passing tests**:

- `test/unit/` — text pagination, PDF backend lifetime/navigation, file-browser
  channel mapping.
- `test/data/` — repositories and providers against an in-memory SQLite database.
- `test/widget/` — the real app shell, Tasks, Files, the note editor, the search
  field, and task-result day selection in search.

No physical Android device or emulator was connected during this work, so SAF
picker interaction, native PDF rendering, the Home role, installed-app discovery
and launching, and keep-screen-on remain runtime-unverified. See the manual
checklist below.

## Manual phone checklist

1. Install `app-debug.apk` and launch it normally.
2. Import a PDF and a `.txt` file through the system picker; reopen both after
   killing and restarting the app.
3. In Files, add a folder, browse into a subfolder, open a supported document,
   then remove the folder and confirm the grant is released.
4. Read a PDF past page 1, leave, and confirm the resumed page; toggle
   keep-screen-on and confirm the display stays awake.
5. Run a text file to the last page and confirm progress and completion state.
6. Add tasks on Home and on another Tasks day; confirm Home still shows today
   only, and that searching for a dated task opens its day.
7. Write a note, leave immediately, reopen it, and confirm the text and edit
   timestamp; repeat with the system back gesture.
8. Request the Home role in Settings, choose PaperOS as Home, open the app
   drawer, pin an app, and launch it.
9. Change theme, text size, and reader settings; restart and confirm they
   persist.
10. Remove every document and confirm the library is empty and the app remains
    usable.

## Architecture

State is plain Riverpod (`Notifier` / `AsyncNotifier`); there is no code
generation. Navigation is `go_router`, with the five destinations in a
`StatefulShellRoute.indexedStack` and overlays pushed on the root navigator.

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
    home/ library/ reader/ files/ notes/ tasks/ settings/ launcher/ search/
      domain/               pure models and logic
      data/                 repositories over SQLite / files / preferences
      application/          Riverpod providers and controllers
      presentation/         screens and widgets
  shared/widgets/           design-system widgets
  theme/                    palette, spacing, typography, ThemeData
```

Content lives in one SQLite database (documents, progress, bookmarks, notes,
tasks, granted folders). Settings live separately in `shared_preferences` so
that reading the theme never opens the content database. Imported files are
copied into app-private storage; the library never depends on a live SAF grant.

## Design rules

`lib/theme` holds a monochrome palette, a spacing scale, and a typography scale
built on bundled Noto Serif faces. `lib/shared/widgets` provides the reusable
surfaces. The rules are: no colour, no ripple, and no ornament that is not
load-bearing.

## Known limitations

- No device or emulator verification. The native surfaces listed above are
  compile-checked and statically reviewed, not run on hardware.
- Import accepts PDF and plain text only. EPUB, Markdown, HTML, Word, and comic
  containers are recognised by extension but not readable.
- Re-importing a file whose private copy has gone missing can add a second
  library row for the same source URI; the stale row remains visible until
  removed manually.
- Release signing is not configured; release builds currently use the debug
  signing key and must not be distributed as-is.
- The repository is not under version control in this checkout, so there is no
  commit history to diff against.
