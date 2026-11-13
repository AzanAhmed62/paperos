# Manual Android testing

This checklist covers behaviour that automated tests cannot prove: SAF pickers,
native PDF rendering, WebView-free EPUB selection, backup and restore through a
real document provider, annotation exports, e-ink appearance, keep-screen-on,
Home-role selection, signing, and app launching.

Record the result, the Android version, the device model and whether the panel is
e-ink for each run. A check is not "passed" because the app compiled or because a
unit test passed. A debug APK is not a release artifact.

## Build under test

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

APK:

```
build/app/outputs/flutter-apk/app-debug.apk
```

The debug manifest contains `INTERNET` for the Flutter development tool. The
release manifest must be audited separately for a release build. Do not test
network behaviour against the debug manifest and call it a release result.

For v1.3 launcher cases, install the debug APK and, if possible, a signed release
or unsigned analysis build. For backup cases, prepare a destination folder
through the Android document picker. Do not use a path on the development machine
as a substitute.

## Suggested test files

Prepare these before starting:

- a valid EPUB 3 with nested contents;
- a valid EPUB 2 with an NCX;
- an EPUB whose private copy can be deleted and re-imported from the same source;
- an EPUB with an image-only chapter;
- a `.txt` file longer than one screen;
- a PDF longer than one page;
- a random or truncated file for malformed-file handling;
- a library with at least two books, a cover, a bookmark, two annotations, a
  note, a dated task, an undated task, and a custom display profile;
- a copy of a valid `.paperosbackup`, plus a truncated copy and a copy whose
  payload byte was changed.

Do not use a purchased or DRM-protected book as a correctness oracle. PaperOS
does not support DRM.

## Checklist

All rows below are written for the v1.3.0+4 build. Status values are explicit:
**Not run** means the case was not exercised in the current run. A physical
OnePlus 6T run on 11 November 2026 covered the rows marked **Passed** or
**Partial**; everything else still needs a device pass.

| # | Area | Steps | Expected result | Result |
| --- | --- | --- | --- | --- |
| 1 | Install and launch | Install the APK normally; open it; close it and open it again. | Five destinations appear: Home, Library, Files, Notes, Settings. No debug banner in release. | Passed on OnePlus 6T (Android 11): debug build installed, launched, five destinations and Paper Home rendered; Settings showed `PaperOS 1.3.0 (4) · schema v2`. |
| 2 | Settings persistence | Change theme, interface text size, reader font size, line height, margins, flow, and display profile; force-stop and reopen. | Settings are restored, including the display profile. | Not run |
| 3 | EPUB 3 import | Library → import → choose the EPUB 3 file. | One row appears with metadata title/author/cover when present, or a file-name title when absent. | Not run |
| 4 | EPUB 2 import | Import the EPUB 2 file. | It opens; nested NCX contents are visible. | Not run |
| 5 | Reopen after restart | Open each EPUB, force-stop the app, reopen it, open the book from the library. | The same passage is restored, not page 1. | Not run |
| 6 | Paged navigation | Read into the book; use tap zones, previous/next controls, and page numbers. | Pages advance, page count is coherent, no blank chapter. | Not run |
| 7 | Continuous scrolling | Switch flow to scroll; scroll into the book; switch back to paged. | Position is retained; no jump to the start or end. | Not run |
| 8 | Typography and orientation | Change font size, line height, margins, page theme, and rotate the device. | The same passage remains on screen after each change. | Not run |
| 9 | Contents | Open the TOC, expand nested entries, choose a subchapter. | The reader lands at the requested chapter/section. | Not run |
| 10 | In-book search | Search for a phrase that occurs more than once; choose the second result. | Results show excerpts; opening one lands on that passage. | Not run |
| 11 | Bookmarks | Bookmark a passage; leave and reopen the book; use the bookmark. | Bookmark label/chapter is correct and returns to the passage after typography changes. | Not run |
| 12 | Selection | Long-press and drag to select text; try highlight, underline, and add note. | Native selection handles work; the user can choose all three actions; no script or browser UI appears. | Not run |
| 13 | Annotation editing | Tap an annotation; edit its note; remove the note; delete the annotation. | The note is saved/cleared; the highlight/underline remains until explicitly deleted. | Not run |
| 14 | Annotation library | Open the annotation library; jump to one passage; return. | The passage is reached; orphaned rows remain visible with their excerpt/note. | Not run |
| 15 | Cascade deletion | Create annotations in two books; delete one book; open the other. | Deleted book's annotations are gone; the other book's annotations remain. | Not run |
| 16 | Stale re-import | Import an EPUB; delete its app-private copy; import the same source again. | Still one library row; progress, bookmarks, annotations, and custom title survive. | Not run |
| 17 | Duplicate content | Import the same file through two different provider URIs. | The SHA-256 fingerprint recognises it; there is still one row. | Not run |
| 18 | Malformed EPUB | Import random bytes with an `.epub` extension and a truncated EPUB. | A recoverable error is shown; no endless spinner; no crash. | Not run |
| 19 | Image-only chapter | Open the image-only EPUB. | An explicit placeholder appears; PaperOS does not invent prose. | Not run |
| 20 | PDF | Import and read a multi-page PDF; leave and resume; toggle keep-screen-on. | Native rendering works, page position resumes, display stays awake while enabled, and turning it off restores normal sleep. | Not run |
| 21 | Text | Read a long TXT file to the last page. | Pagination, progress, and completed status are correct. | Not run |
| 22 | SAF folder browsing | Files → add folder; browse into a subfolder; open a supported file; remove the folder. | The folder is browsable only after the grant; removal releases the grant; the library copy still opens. | Not run |
| 23 | Tasks | Add a task on Home and on another Tasks day; search for a dated task. | Home still shows today only; the search result selects the task's day. | Not run |
| 24 | Notes | Write a note, leave immediately, reopen it. | Final keystrokes are flushed; the body and edit timestamp are intact. | Not run |
| 25 | Home role and app drawer | Settings → request Home role; choose PaperOS as Home; open the app drawer; pin and launch an app. | The role picker appears; the drawer lists launchable apps; launch returns to the app. | Partial: the role dialog appeared after the `startActivityForResult` fix but was cancelled, so the role stayed unchanged. The drawer listed 45 apps with real icons; pin, unpin, launch and recents persistence worked. |
| 26 | Process death | While reading an EPUB, remove the task from recents and reopen. | The book remains in the library with its last flushed passage. | Not run |
| 27 | Low storage / permission denial | Deny a picker, then try a file that disappears before import. | The app shows a recoverable message and does not add a broken row. | Not run |
| 28 | Release permissions | Build a release APK and inspect the merged manifest/APK permissions. | No `INTERNET`, no broad storage permission, no unrelated permission. | Static audit passed on the unsigned analysis APK; install not run — no device or signing credentials |
| 29 | Full backup | With the populated library, Settings → Create a backup, choose a folder through SAF, save a `.paperosbackup`, then inspect it with a ZIP tool. | Save picker appears; progress completes; archive contains `manifest.json`, `manifest.sha256`, `database.json`, `settings.json`, `books/`, and any covers; books are not in SQLite. | Not run |
| 30 | Restore replacement | Change some progress/settings, then restore the backup from case 29 through SAF. Confirm the warning. | Preview counts and warnings appear; after restore, documents, covers, progress, bookmarks, annotations, notes, tasks, folder references, reading locators, and display profile match the backup exactly. | Not run |
| 31 | Restore rejection and safety | Try a truncated archive, a modified payload, a traversal-name archive, a future-version manifest, and a wrong password-looking ZIP. Then restore a valid backup. | Each bad archive is rejected before the live library changes; no partial rows remain; a valid restore still succeeds; a safety snapshot exists. | Not run |
| 32 | Restore cancellation | Begin a restore of a large archive and cancel before the final commit. Afterwards reopen the library. | Cancel is acknowledged, staging/copies are cleaned up, and the previous library/settings are unchanged. | Not run |
| 33 | Annotation export | Open a book with annotations; export Markdown and JSON through the system save picker. | Files contain title, author, export date, chapters, excerpts, notes, annotation type, bookmarks, locations, and an explicit orphan notice when needed. Empty books export safely. | Not run |
| 34 | E-Ink profile | Switch Settings → Display profile → E-Ink Friendly; browse Home, Library, Files, Notes and Settings; open an EPUB; select text; turn pages; wait for the clock minute. | Motion is still, pages are readable, selection is visible, chrome stays until dismissed, reader uses paged/tap zones with enlarged text/spacing, clock updates once a minute, and no vendor flash is claimed. | Not run — no e-ink device |
| 35 | Release artifact and signature | Build with user-owned credentials, verify the APK with `apksigner`, and install the universal and split-ABI APKs on a device. | Signature is the owner's certificate, not debug; universal and ABI-specific builds install; AAB is produced for Play; without credentials the release task fails closed. | Not run — no signing credentials were supplied |
| 36 | Responsive and empty states | Use a narrow phone in portrait, a tablet-width window, Android large text, and a library with zero documents. | No overflow; long titles wrap or ellipsize; empty/error states are readable and actionable; touch targets remain usable. | Not run |

### v1.3 launcher and navigation cases

These rows are the device counterpart to `docs/navigation-architecture.md` and
the v1.3 automated tests.

| # | Area | Steps | Expected result | Result |
| --- | --- | --- | --- | --- |
| 37 | Back from primary surfaces | Open Library, then Back; repeat for Files, Notes and Settings. | Each Back returns to Paper Home. No tab-history surprise, no blank route, no activity finish. | Partial: Library → Back returned to Paper Home. Files, Notes and Settings were not individually repeated. |
| 38 | Back on Paper Home | From Home, press Back repeatedly. | Home remains visible; the activity does not finish and no other launcher or wallpaper appears. | Passed on OnePlus 6T (Android 11): Back was consumed, Home stayed visible and the activity remained alive. |
| 39 | Overlay Back order | From Home open the app drawer, Search, Tasks, a note editor and a reader; press Back in each. | The overlay closes and reveals its owner. Back does not switch the underlying destination first. | Partial: drawer, Search and Tasks closed to their owner. With a focused search field the first Back dismissed the IME and the second closed the overlay. Reader and note editor were not exercised. |
| 40 | Files folder Back | Grant a folder, open it, open a subfolder, then press Back three times. | First Back returns to the location root; second returns to the granted-folder list; third returns to Paper Home. | Not run |
| 41 | Home quick actions and layout | Tap Search, Apps, New note and New task; toggle Date; switch Comfortable/Compact; check launcher status. | Each action opens the right surface; date appears/disappears under the clock; density changes spacing without shrinking text; role status is accurate. | Partial: Search, Apps, New note and New task opened the right surfaces; launcher status matched the unset role. Date and density toggles were not exercised. |
| 42 | HOME role selection | Settings/Home → set PaperOS as the home app; confirm the system dialog. | The role dialog appears; after confirmation, pressing Home from another app opens Paper Home. | Partial: the system dialog appeared and was cancelled; the role stayed unchanged. Confirmation and launcher replacement were not tested. |
| 43 | Warm HOME press | While reading a document, press the system Home button. | PaperOS shows Paper Home, not the reader page; the reader is not left as the visible surface. | Not run |
| 44 | Launcher icon warm start | While PaperOS is running in a child surface, tap its launcher icon from the home screen/recents. | The hierarchy resets to Paper Home through `onNewIntent`; no duplicate PaperOS task is created. | Partial: repeated `am start` with `MAIN+LAUNCHER` reused one task and one `MainActivity`, and reset a child surface to Paper Home. A real launcher icon was not used. |
| 45 | VIEW vs HOME | Open a PDF and a `.txt` from another app with PaperOS; then press Home. | VIEW imports/opens the document; pressing Home resets to Paper Home. A VIEW intent is not mistaken for a launcher reset. | Not run |
| 46 | Duplicate tasks and process recovery | Launch PaperOS repeatedly from the icon, Recents and Home; remove the task from Recents while reading, then reopen. | One task is reused; the app returns to Paper Home after recreation; the library/progress remains intact after the flushed write. | Partial: repeated `am start` reused one task; force-stop and relaunch returned to Paper Home. Process death while reading was not tested. |
| 47 | Drawer recents, pins and refresh | Launch several apps, reopen the drawer, pin/unpin, clear recents, toggle system apps and icons, refresh. | Recents are newest-first and bounded; pins persist and reorder; refresh re-reads the catalogue; hidden system apps stay hidden; a restricted result is explained. | Partial: 45 apps enumerated with real icons; launch, recents persistence across force-stop, pin/unpin and clear-recents worked. System-app/icon toggles, refresh and the restricted state were not exercised. |
| 48 | Predictive Back | Enable predictive Back in system developer options if needed; gesture Back on an overlay and on Home. | The overlay preview closes; Home does not animate an exit and remains visible. | Not run — Android 11 does not provide the predictive-Back preview |

## What to capture for a failure

Include:

- the step number above;
- device model, Android version, and whether the screen is e-ink;
- APK SHA-256 and whether it was debug, unsigned analysis or production-signed;
- the exact document format and whether it opens in another reader;
- a screenshot or a short screen recording;
- logcat around the failure, if available;
- whether the failure survives a force-stop and relaunch.

Do not attach a copyrighted book. A minimal synthetic EPUB is enough to reproduce
most parser and layout issues. Do not attach a real library backup containing
personal notes; reduce it to synthetic content first.

## Current environment result

A physical OnePlus 6T (`ONEPLUS A6010`, Android 11 / API 30) was attached for a
partial v1.3 run on 11 November 2026. The debug build
(`dev.paperos.app.debug`, version 1.3.0+4, debug-signed, SHA-256
`98a465920e1018b034225054c468015c90f9fffbff5f0bb012663e45df637e30`) was
installed and exercised: install/launch, Library → Back, Back consumed on Home,
app-drawer enumeration and launch, recents persistence, pin/unpin,
clear-recents, warm `am start` HOME/LAUNCHER resets, repeated-launch task reuse,
force-stop recovery, and the HOME-role dialog. The role was cancelled, so
launcher replacement was not tested.

Rows 1, 38 and parts of 25, 37, 39, 41, 42, 44, 46 and 47 record that run.
Everything else remains **not run**, including role confirmation, the system Home
button while the role is held, real-launcher warm intents, OEM duplicate tasks,
predictive Back, process death while reading, SAF document-provider flows,
`ACTION_VIEW`, backup transfer, native PDF rendering and E-Ink visuals. An
unsigned release analysis APK was also built (`dev.paperos.app`, version
1.3.0+4, SHA-256
`24bc261016c63b345b77058b595798c66bf4509994074df1bac51c0628fa9f41`); it is not
installable or distributable, and production signing remains blocked by missing
owner credentials. Automated coverage is recorded in the v1.3 engineering report
and README; it is not a substitute for this checklist.
