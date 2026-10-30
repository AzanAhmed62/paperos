# EPUB reader-engine decision

Status: accepted for PaperOS v1.1.

Date of package review: 2026-10-30.

## Decision

PaperOS implements a small, bounded EPUB 2/3 parser and a Dart-side reflowable
reader instead of embedding a browser engine or adopting Readium. The parser
reads the package document, spine, EPUB 3 navigation or EPUB 2 NCX, metadata, and
cover. It reduces each spine item to safe plain text and feeds that text through
the same pagination model already used by TXT.

The reader adds:

- nested table of contents;
- in-book search;
- paged and continuous-scroll flow;
- font, line-height, margin, and page-theme controls;
- bookmarks;
- text selection for highlight, underline, and attached note;
- chapter-relative `epub:spine=<n>;char=<n>` locators;
- orphan-preserving annotation recovery.

The decision is intentionally narrower than a general EPUB engine. PaperOS does
not claim to reproduce publisher CSS, fixed layout, images, ruby, MathML, audio,
video, media overlays, or DRM. Those are recorded limitations, not silently
rendered blank pages.

## Alternatives considered

The review used the package metadata and documentation available on pub.dev on
2026-10-30. Versions move; pin and re-check before any future adoption.

| Option | Version reviewed | License | Android fit | Selection / annotations | Network and script surface | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| `flutter_readium` | 0.8.0 | BSD-3-Clause | Requires Flutter 3.44.8+, `compileSdk` 37, AGP 9.1.1+, Gradle 9.3.1+, Kotlin 2.3+, and `FlutterFragmentActivity` | Strong: highlights, decorations, progress, search | Native Readium toolkit; large dependency surface | Rejected for v1.1 because adopting it would require the disruptive Android toolchain upgrade the brief forbids |
| `flutter_epub_viewer` | 2.2.1 | BSD-3-Clause according to pub metadata; the README also calls the project MIT | Android supported; WebView/epub.js; `flutter_inappwebview` and `http` dependencies | Good API: CFI restore, search, highlights, underlines, context menu | WebView + epub.js; scripts default off, but the rendering engine and remote-resource policy need extra hardening | Viable fallback, not chosen for deterministic local-only testing and a smaller runtime |
| `epub_view` | 3.3.0 | MIT | Pure Flutter, Android supported; depends on `flutter_html`, `epubx`, `http` | CFI generation and TOC are documented; text selection, highlights, notes, and search are not a supported API | HTML rendering in Flutter; still a sizeable dependency tree | Rejected: annotation and anchor behaviour would need a fork or a second layer |
| Custom bounded parser + paginator | PaperOS v1.1 | App code; `archive` MIT, `xml` MIT, `crypto` BSD-3-Clause | No new Android toolchain requirement; no WebView | Selection is `SelectableText`; annotations and ranges are first-class and unit-tested | No script execution and no external-resource fetch by construction | Chosen |

### Why `flutter_readium` was not adopted

`flutter_readium` is the strongest feature match on paper. It already supports
EPUB 2/3, CFI-like progress, highlights, search, themes, and scrolling. It was
still rejected for this release for one concrete reason: its Android
requirements conflict with the preserved build toolchain.

At the reviewed version it requires:

- `compileSdk` 37 or newer;
- Android Gradle Plugin 9.1.1 or newer;
- Gradle 9.3.1 or newer;
- Kotlin Gradle Plugin 2.3 or newer;
- `FlutterFragmentActivity` instead of the current `FlutterActivity`;
- core-library desugaring.

PaperOS deliberately stays on the verified toolchain: Flutter 3.47.7 / Dart
3.13.5, JDK 21, Android SDK 36, Gradle 8.14.0, AGP 8.11.1, Kotlin 2.2.20. Moving
all of those at once would be an unrelated, high-risk platform migration. A full
Readium proof of concept was therefore not run; the incompatibility is a
build-system blocker, not a judgement about Readium's quality.

If a later release performs the Android toolchain migration, Readium should be
re-evaluated first. The migration should be a separate change with its own APK
and device validation.

### Why the WebView options were not adopted

`flutter_epub_viewer` is a capable WebView wrapper around epub.js. It can open a
local file, restore a CFI, search, and expose selection and highlight APIs. It is
a reasonable fallback. It was not selected because:

- the reader would depend on WebView behaviour that this environment cannot
  inspect on a device;
- script execution and external-resource loading become policy decisions inside
  a browser engine rather than structural guarantees;
- native WebView selection handles and e-ink refresh are harder to test than a
  Flutter `SelectableText`;
- the package pulls `flutter_inappwebview` and `http`, increasing the dependency
  and permission-review surface;
- published known issues include whole-book page count, scrolled-flow
  navigation, and Android snap relocation behaviour.

`epub_view` is attractive because it is pure Flutter and MIT-licensed, but its
documented API stops at CFI navigation and TOC. Selection, highlights, notes,
search, and anchor recovery would need a fork or a second annotation layer. That
would provide less control than the custom parser while retaining a large
HTML-rendering dependency tree.

## What was prototyped

The custom path was prototyped before it became the shipped reader:

| Check | Result |
| --- | --- |
| Open an app-private EPUB file after restart | Automated parser/backend tests and reader-session tests pass |
| EPUB 3 navigation document | Parsed, including nested entries |
| EPUB 2 NCX navigation | Parsed, including nested entries |
| Package metadata and cover | Import test reads title/metadata and writes a private cover |
| Local-only security | No network client or script engine in the parser; external resources excluded |
| Malformed/random/non-EPUB input | Rejected with recoverable errors |
| Unsafe ZIP path | Rejected before content is opened |
| Declared unbounded ZIP entry | Rejected |
| Image-only spine item | Honest placeholder, no invented text |
| Paged navigation and scroll mapping | Backend tests pass |
| Locator restore across typography change | Restores the page containing the locator |
| In-book search | Backend tests pass |
| Text selection ranges and annotation spans | Backend tests pass |
| Orphaned annotation recovery | Backend tests pass; row is retained |
| Reader lifecycle and paginator disposal | Tests pass |
| Reader chrome and real page viewport | Widget test passes |
| Physical Android selection and e-ink refresh | Not verified; no device or emulator available |

## Consequences

Benefits:

- deterministic local parsing and no browser runtime;
- no network path in the reader at all;
- selection, search, locators, and annotations are testable as ordinary Dart;
- one pagination model for TXT and EPUB;
- small, permissively licensed dependencies;
- stable positions across font, margin, theme, and orientation changes.

Costs:

- publisher CSS, images, fixed layout, ruby, MathML, media overlays, and DRM are
  not rendered;
- PaperOS locators are CFI-style but not literal DOM CFIs, so they are not
  portable to other EPUB applications;
- a malformed book that relies on browser error recovery may be rejected rather
  than partially displayed;
- the parser and locator format are now maintained application code and need
  regression fixtures when they change.

## Revisit triggers

Re-open this decision if any of these become true:

1. The Android toolchain is intentionally upgraded to compileSdk 37, AGP 9,
   Gradle 9.3, and Kotlin 2.3. Readium becomes the first candidate.
2. A device-validated requirement appears for fixed-layout EPUB, publisher CSS,
   MathML, ruby, or media overlays.
3. EPUB interoperability requires literal EPUB CFI export/import.
4. The custom parser's regression surface grows beyond what the focused fixtures
   and tests can cover.

Until then, the bounded parser is the deliberate, documented choice.
