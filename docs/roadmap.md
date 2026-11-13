# Roadmap

This roadmap records the state after v1.3 and keeps later work honest about the
constraints that shaped the app. It is not a promise of dates or an invitation to
add unrelated product surfaces.

## Completed in v1.3

- Formal four-level navigation hierarchy: Home, primary destinations, child
  surfaces, and Android/system surfaces.
- One shell-level `PopScope` and a pure Back policy. Back closes overlays first,
  steps out of Files folders, returns non-Home destinations to Home, and is
  consumed on Home instead of finishing the activity.
- Router lifetime moved to `appRouterProvider`/`createAppRouter()`, with a
  per-router navigator key so activity recreation and tests do not inherit stale
  route state.
- HOME, LAUNCHER and `ACTION_VIEW` intent classification through
  `SystemIntentChannel`; HOME/LAUNCHER resets the hierarchy, VIEW still opens its
  document. Cold-start stash, warm `onNewIntent`, resume drain and process
  recovery are documented and tested.
- App drawer recents and pinned strips, stable ordering, explicit refresh,
  real/initial icons, system-app visibility, and honest restricted/empty states.
- Home quick actions, pinned apps, optional date, comfortable/compact density,
  HOME-role status and launcher-settings entry.
- Settings launcher section with role status/request, refresh, icons, system
  apps, recents, clear recents and a pinned-app editor.
- 202 automated tests passing, with `dart format` and `flutter analyze` clean.
- v1.3 navigation, launcher, release-manifest and engineering documentation.

## Completed in v1.2

- Local backup and validated replacement restore through SAF, with a safety
  snapshot, checksummed manifest, archive limits and rollback protection.
- Annotation export as Markdown and JSON, including orphan disclosure.
- Standard / E-Ink Friendly display profiles, including reduced motion, static
  progress, 48 dp targets, reader flow and page-turn policy, and a
  policy-driven scroll physics.
- Reader re-pagination when the system text scale changes, so accessibility
  text cannot overflow a measured page.
- Fail-closed release signing, unsigned analysis escape hatch, optimized release
  configuration and a merged-manifest audit procedure.
- 163 automated tests passing, with `dart format` and `flutter analyze` clean.

## Completed in v1.1

### EPUB 2 and EPUB 3

- SAF import and app-private copies.
- Files browsing and library import share the same import service.
- Bounded ZIP/package validation.
- EPUB 3 navigation and EPUB 2 NCX navigation, including nested entries.
- Metadata: title fallback, author, publisher, language, identifier,
  description, and cover.
- Text-first reflowable reading in paged and continuous-scroll modes.
- Nested table of contents and in-book search.
- Font size, line height, margin, page theme, page numbering, and reader-flow
  preferences.
- Reader position preserved across typography and orientation changes.
- Debounced progress writes and flush on reader close.
- Image-only and malformed books fail or placeholder honestly.

### Annotations and anchors

- Highlight, underline, and attached-note kinds.
- Edit and delete.
- Inline rendering on the current page.
- Per-book annotation library with navigation back to the passage.
- Stable chapter-relative locators.
- Orphan detection and recovery without deleting the excerpt or note.
- Cascade deletion when a document is removed.

### Library and import

- All-format and per-format filters.
- Recent, favourites, unread, in-progress, and completed status filters.
- Title, author, and recent sorting.
- Author-aware search.
- SHA-256 content fingerprinting.
- Source URI plus fingerprint deduplication.
- Stale-row relinking that preserves progress, bookmarks, annotations, and user
  titles.

### Persistence and safety

- Additive SQLite schema v2.
- v1-to-v2 migration test with a real populated v1 database.
- EPUB archive size, entry count, per-entry size, total expansion, and text-size
  limits.
- No new permissions and no network dependency.
- Resource disposal tests for the PDF and EPUB backends.

### Documentation and verification

- README updated for v1.1.
- Architecture, reader-engine decision, migration, roadmap, and manual-testing
  documents.
- 134 automated tests passing, with `dart format` and `flutter analyze` clean.
- Debug APK build recorded with size and SHA-256.
- Release manifest audited for permissions.

## Next candidates

These are ordered by risk reduction, not by feature appeal.

### 1. Device and integration validation

Highest priority is closing the gap between automated coverage and Android
behaviour:

- install the debug APK on a physical Android device;
- run the manual checklist in [`manual-testing.md`](manual-testing.md);
- select PaperOS as Home and walk the exact Back hierarchy, including Home
  consuming Back;
- verify warm HOME/LAUNCHER and VIEW intents, duplicate tasks, and process
  death/recreation;
- exercise SAF import through several providers;
- verify native PDF rendering and EPUB selection handles;
- inspect e-ink ghosting, refresh timing, and system font scaling;
- confirm lifecycle behaviour after process death and storage eviction.

No new reader feature should be considered complete before this is done.

### 2. EPUB typography and structural fidelity

Within the text-first model:

- render inline images and figure captions safely, with size bounds;
- preserve simple emphasis (italic/bold) where it can be represented without
  importing publisher CSS wholesale;
- improve footnote links and internal chapter links;
- improve list and blockquote spacing;
- add better chapter-progress labels;
- add EPUB fixtures for right-to-left text, long chapters, and unusual NCX
  structures.

This remains bounded. Fixed layout, MathML, ruby, media overlays, and DRM stay
out of scope unless the engine decision is revisited.

### 3. Annotation ergonomics

- keyboard and accessibility traversal for selection ranges;
- a clearer note editor inside the annotation sheet;
- deterministic ordering and filtering in the per-book annotation library;
- stronger recovery UI for orphaned anchors.

### 4. Local reading data tools

- explicit storage-usage report for documents, covers, and trash;
- a non-destructive "verify library files" action;
- a user-facing list of safety snapshots, or removal of snapshots that cannot be
  restored through the UI.

These are local-only and must not become cloud sync.

### 5. Reader accessibility

- TalkBack labels for reader chrome, search results, TOC rows, and annotations;
- large-text and display-scaling audit;
- reduced-motion alternatives for chrome animation;
- contrast verification across the monochrome paper themes.

### 6. Platform maintenance

If and when the Android toolchain is deliberately upgraded:

- move to compileSdk 37, AGP 9, Gradle 9.3, and Kotlin 2.3 as one controlled
  change;
- re-run the full suite and device checklist;
- evaluate `flutter_readium` again against the custom engine;
- keep the custom parser as a fallback only if it still earns its maintenance
  cost.

## Explicit non-goals

- AI or chatbot features.
- Cloud accounts, social features, or marketplace.
- Ads, subscriptions, or paid content.
- Audiobooks, media-overlay playback, or TTS in the reading path.
- OCR or scanned-PDF text extraction.
- A custom keyboard.
- Full operating-system replacement or lock-screen replacement.
- General-purpose file manager outside the SAF-scoped Files surface.
- A sixth bottom-navigation destination.
- Cloud sync of progress, bookmarks, annotations, or settings.
- Blind dependency or toolchain upgrades solely to claim newer versions.

## Constraints to preserve

- Release manifest without `INTERNET` or broad storage permission.
- Five destinations and the existing visual language.
- Native PDF backend for PDFs.
- Files remains a real SAF browser.
- EPUB files stay outside SQLite.
- Migrations stay additive and preserve user data.
- No broad dependencies without a license, Android-compatibility, security, and
  lifecycle review.
