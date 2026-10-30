# PaperOS architecture

PaperOS is a Flutter Android application that behaves like a quiet reading
environment. It is not an operating-system replacement: it can be selected as an
Android Home app, but it still runs inside Android and keeps using the platform
for file access, PDF rendering, app launching, and keep-screen-on.

This document describes the v1.1 architecture. The reader-engine choice and its
trade-offs are recorded separately in
[`reader-engine-decision.md`](reader-engine-decision.md).

## Design constraints

- Five primary destinations only: Home, Library, Files, Notes, Settings. There
  is no bottom-navigation destination for the task checklist, search, the app
  drawer, or the reader.
- Local-first. There are no accounts, cloud sync, analytics, ads, downloads, or
  network calls in the content path.
- The release manifest declares no `INTERNET` permission and no broad storage
  permission.
- PDFs remain on the native Android `PdfRenderer` path. EPUB and text share a
  Dart-side reflowable path.
- Imported files are copied into app-private storage. A revoked SAF grant must
  not make an existing library entry unreadable.
- Persistence is additive. A schema upgrade must not drop documents, progress,
  bookmarks, annotations, notes, tasks, or settings.
- EPUB content stays in files. SQLite stores metadata, progress, and anchors,
  never the book itself.
- Malformed, hostile, or unsupported documents must fail honestly. The app does
  not execute EPUB scripts or load remote resources.

## Runtime structure

```
main()
  └─ ProviderScope(sharedPreferences override)
       └─ PaperApp
            ├─ go_router StatefulShellRoute (five destinations)
            └─ root-navigator overlays
                 reader, tasks, search, note editor, app drawer
```

State is plain Riverpod: `Provider`, `Notifier`, and `AsyncNotifier`, with no code
generation. Navigation is `go_router`, with the primary surfaces kept in a
stateful indexed shell and overlays pushed on the root navigator.

```
lib/
  app/          bootstrap, router, destination shell, dependency wiring
  config/       file-size limits, database version, timing constants
  core/
    errors/     PaperException and user-facing error kinds
    platform/   native bridges: SAF/files, PDF, app catalog, keep-awake
    storage/    SQLite schema/opener, app-private directories
    utils/      ids, dates, formatting, streaming fingerprint
  features/
    annotations/  annotation model, repository, providers
    home/         paper home and section settings
    library/      import, probes, metadata, filters, library UI
    reader/       reader session/UI + PDF, text and EPUB backends
      epub/       bounded parser, book model, locator backend
    files/        SAF folder grants and browser
    notes/        notes repository and editor
    tasks/        dated checklist
    settings/     JSON settings in shared_preferences
    launcher/     installed-app cache and app drawer
    search/       cross-surface search
  shared/widgets/ design-system widgets
  theme/          monochrome palette, spacing, typography
```

Feature folders follow the same practical split where they need it:
`domain/` holds pure models and rules, `data/` owns persistence or platform
I/O, `application/` owns Riverpod state, and `presentation/` owns widgets.

## Data ownership

| Store | Contents | Owner |
| --- | --- | --- |
| SQLite `paperos.db` | documents, progress, bookmarks, annotations, notes, tasks, granted folders | `AppDatabaseOpener` and the repositories |
| `shared_preferences` | appearance, reader preferences, Home sections, launcher settings, trusted folder metadata | `SettingsRepository` |
| App documents directory | imported originals and generated EPUB covers | `AppStorage` and `LibraryService` |
| App trash directory | files awaiting removal | `AppStorage` / `LibraryService` |

Settings are deliberately separate from SQLite: changing the theme must not
require opening the content database.

SQLite foreign keys are enabled with `PRAGMA foreign_keys = ON`. Bookmarks and
annotations reference `documents(id)` with `ON DELETE CASCADE`, so deleting a
document removes its dependent rows in the same operation. Notes and tasks are
independent user data and are never cascaded from a document.

## Import pipeline

`LibraryService.importFile` is the single import path used by the Library and
Files surfaces.

1. Reject unknown or unreadable extensions, files above
   `PaperConfig.maxImportBytes`, missing sources, and empty files.
2. Look up the exact SAF `sourceUri`. If a row exists and its private copy is
   still present, return it unchanged. Re-import is a no-op.
3. Compute a streaming SHA-256 content fingerprint. If no source match exists,
   look up the fingerprint. A live match is returned unchanged.
4. Copy the source into app-private storage with a fixed-size streaming buffer;
   the whole file never becomes one Dart allocation.
5. Probe the copied file:
   - PDF: ask the native service for a page count; unreadable files are kept but
     marked `unreadable`.
   - EPUB: run the bounded parser; use package metadata when present, write a
     private cover if safe, and otherwise retain the file-name title.
   - TXT: keep the file-name title and leave pagination to the reader.
6. If an existing row was found by source URI or fingerprint but its private copy
   was missing, relink the row instead of creating a second one. The row id stays
   the same, which preserves progress, bookmarks, annotations, and a custom
   title. Only file-backed fields and metadata are replaced.
7. Insert a new row only when neither identity check found a match.

This closes the stale-file duplicate bug in both directions: the same source
cannot create two rows, and identical content imported through a different
provider URI is recognised by its fingerprint.

## EPUB pipeline

The EPUB path deliberately has no WebView and no JavaScript runtime.

```
.epub file
  → bounded ZIP validation
  → META-INF/container.xml
  → package document (.opf)
  → metadata + manifest + spine + TOC
  → per-spine XHTML → safe plain text + anchors
  → composite text + chapter offsets
  → TextPaginator
  → EpubReaderBackend
  → reader UI (paged or scrolling)
```

Validation happens before content is treated as a book:

- the archive must be a readable ZIP with a container and package document;
- path traversal and absolute paths are rejected;
- archive entry count, per-entry size, total uncompressed size, and source size
  are bounded by `PaperConfig`;
- scripts, styles, `head`, `nav`, SVG, MathML, objects, and iframes are excluded
  from text extraction;
- external resources are never fetched;
- declared non-EPUB types and malformed packages fail with
  `EpubParseException`, which the reader converts into a recoverable
  `PaperException.corruptDocument`;
- an image-only spine item becomes an explicit placeholder, not invented prose.

EPUB 3 navigation is read from the nav document; EPUB 2 navigation is read from
the NCX. Both retain nested entries and fragment targets. The table of contents
can point inside a chapter rather than only at a spine boundary.

Text extraction collapses inline whitespace without inserting partial UTF-16
characters. Block elements and `<br>` create paragraph and line breaks. A
chapter's extracted text becomes part of one composite book string with offsets,
which keeps search, pagination, and page spans deterministic.

## Reader session and progress

`ReaderSession` is an auto-disposed `AsyncNotifier<ReaderState>` keyed by document
id. It owns the active backend, bookmarks, annotations, viewport geometry, the
current page, and the write-behind progress store.

- PDF and text use the same page-oriented reader contract.
- EPUB adds locator navigation, nested contents, in-book search, annotation
  ranges, and scroll-fraction mapping.
- The selected `ReaderFlow` (`paged` or `scroll`) is persisted in settings.
  PDFs remain page-oriented; only reflowable documents can scroll continuously.
- A viewport change repaginates a reflowable book and restores the page containing
  the saved locator. Font, margin, line-height, theme, and orientation changes
  therefore keep the passage rather than the old page number.
- Progress writes are debounced while the reader is active and flushed when it
  closes. The disposal callback uses a captured state snapshot and repository
  instance because Riverpod forbids reading `ref` or provider `state` during
  disposal.
- Reader loading does not use Riverpod's automatic retry. Opening a local file is
  deterministic; retrying a corrupt file would leave the screen loading instead
  of showing the recoverable error.
- The native PDF handle and the EPUB paginator are disposed with the backend.
  Page bitmaps are rendered on demand and cached only around the visible page.

## Locators and annotations

PaperOS uses a deliberately documented CFI-style locator:

```
epub:spine=<spine index>;char=<chapter-relative UTF-16 offset>
```

It is stable across typography changes because it does not address a page,
pixel, DOM node, or CSS selector. It is not a literal EPUB CFI; the app renders
extracted text rather than a DOM. The format is therefore stable inside PaperOS
and not interchangeable with another EPUB application's bookmark format.

Annotations store:

- `start_locator` and `end_locator`;
- chapter index and chapter title when known;
- the selected excerpt;
- the optional note;
- an `orphaned` flag.

When a stored anchor cannot be resolved, the row is not deleted. The UI keeps
the excerpt and note, marks the anchor orphaned, and offers navigation only when
it can be resolved. This makes a parser change or a moved passage recoverable
instead of silently losing the user's work.

## Library views

`LibraryScope` covers all documents, EPUB, PDF, TXT, recent, favourites, unread,
in-progress, and completed. `LibrarySort` is limited to title, author, and
recently opened. Search matches title, author, source name, and file name.

The Home screen reuses the same document repository for the last-read and recent
sections. It does not maintain a second index, so a rename or progress update is
visible everywhere.

## Security and privacy boundaries

- No `INTERNET` permission in the release manifest.
- No storage permission; SAF grants are per-selection and PaperOS never re-reads
  the original after import.
- No network client in the EPUB parser or reader.
- EPUB scripts are not executed because no scripting engine is present.
- External CSS, fonts, images, audio, and video are not loaded.
- Archive expansion is bounded before extraction.
- Provider-supplied file names are sanitised before cache files are created.
- SQLite queries use bound parameters.
- The app does not claim to be a browser, a DRM client, or an EPUB conformance
  renderer.

## Failure model

User-facing failures use `PaperException` kinds such as `missingFile`,
`corruptDocument`, `unsupportedFormat`, `storage`, and `permission`. The reader
shows a recoverable error surface instead of an endless spinner. Library rows
whose files vanish are marked missing, and unreadable probes are shown as
unreadable rather than as books with a page count of zero.

The migration path is explicit and additive. See
[`database-migrations.md`](database-migrations.md).

## Verification boundaries

The automated suite runs against the real SQLite engine and exercises the parser,
pagination, locator restore, annotation ranges, import deduplication, migration,
and real widget surfaces. It does not prove Android runtime behaviour. SAF
picker interaction, native PDF rasterisation, EPUB selection handles, e-ink
refresh, Home-role selection, and app launching remain device checks. The manual
checklist is in [`manual-testing.md`](manual-testing.md).
