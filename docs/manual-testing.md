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

For v1.2 backup cases, also install a signed release (or a debug build if no
release credentials exist) and prepare a destination folder through the Android
document picker. Do not use a path on the development machine as a substitute.

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

All rows below are written for the v1.2.0+3 build. Status values are explicit:
**Not run** means no Android device or emulator was available in this
environment.

| # | Area | Steps | Expected result | Result |
| --- | --- | --- | --- | --- |
| 1 | Install and launch | Install the APK normally; open it; close it and open it again. | Five destinations appear: Home, Library, Files, Notes, Settings. No debug banner in release. | Not run — no device |
| 2 | Settings persistence | Change theme, interface text size, reader font size, line height, margins, flow, and display profile; force-stop and reopen. | Settings are restored, including the display profile. | Not run — no device |
| 3 | EPUB 3 import | Library → import → choose the EPUB 3 file. | One row appears with metadata title/author/cover when present, or a file-name title when absent. | Not run — no device |
| 4 | EPUB 2 import | Import the EPUB 2 file. | It opens; nested NCX contents are visible. | Not run — no device |
| 5 | Reopen after restart | Open each EPUB, force-stop the app, reopen it, open the book from the library. | The same passage is restored, not page 1. | Not run — no device |
| 6 | Paged navigation | Read into the book; use tap zones, previous/next controls, and page numbers. | Pages advance, page count is coherent, no blank chapter. | Not run — no device |
| 7 | Continuous scrolling | Switch flow to scroll; scroll into the book; switch back to paged. | Position is retained; no jump to the start or end. | Not run — no device |
| 8 | Typography and orientation | Change font size, line height, margins, page theme, and rotate the device. | The same passage remains on screen after each change. | Not run — no device |
| 9 | Contents | Open the TOC, expand nested entries, choose a subchapter. | The reader lands at the requested chapter/section. | Not run — no device |
| 10 | In-book search | Search for a phrase that occurs more than once; choose the second result. | Results show excerpts; opening one lands on that passage. | Not run — no device |
| 11 | Bookmarks | Bookmark a passage; leave and reopen the book; use the bookmark. | Bookmark label/chapter is correct and returns to the passage after typography changes. | Not run — no device |
| 12 | Selection | Long-press and drag to select text; try highlight, underline, and add note. | Native selection handles work; the user can choose all three actions; no script or browser UI appears. | Not run — no device |
| 13 | Annotation editing | Tap an annotation; edit its note; remove the note; delete the annotation. | The note is saved/cleared; the highlight/underline remains until explicitly deleted. | Not run — no device |
| 14 | Annotation library | Open the annotation library; jump to one passage; return. | The passage is reached; orphaned rows remain visible with their excerpt/note. | Not run — no device |
| 15 | Cascade deletion | Create annotations in two books; delete one book; open the other. | Deleted book's annotations are gone; the other book's annotations remain. | Not run — no device |
| 16 | Stale re-import | Import an EPUB; delete its app-private copy; import the same source again. | Still one library row; progress, bookmarks, annotations, and custom title survive. | Not run — no device |
| 17 | Duplicate content | Import the same file through two different provider URIs. | The SHA-256 fingerprint recognises it; there is still one row. | Not run — no device |
| 18 | Malformed EPUB | Import random bytes with an `.epub` extension and a truncated EPUB. | A recoverable error is shown; no endless spinner; no crash. | Not run — no device |
| 19 | Image-only chapter | Open the image-only EPUB. | An explicit placeholder appears; PaperOS does not invent prose. | Not run — no device |
| 20 | PDF | Import and read a multi-page PDF; leave and resume; toggle keep-screen-on. | Native rendering works, page position resumes, display stays awake while enabled, and turning it off restores normal sleep. | Not run — no device |
| 21 | Text | Read a long TXT file to the last page. | Pagination, progress, and completed status are correct. | Not run — no device |
| 22 | SAF folder browsing | Files → add folder; browse into a subfolder; open a supported file; remove the folder. | The folder is browsable only after the grant; removal releases the grant; the library copy still opens. | Not run — no device |
| 23 | Tasks | Add a task on Home and on another Tasks day; search for a dated task. | Home still shows today only; the search result selects the task's day. | Not run — no device |
| 24 | Notes | Write a note, leave immediately, reopen it. | Final keystrokes are flushed; the body and edit timestamp are intact. | Not run — no device |
| 25 | Home role and app drawer | Settings → request Home role; choose PaperOS as Home; open the app drawer; pin and launch an app. | The role picker appears; the drawer lists launchable apps; launch returns to the app. | Not run — no device |
| 26 | Process death | While reading an EPUB, remove the task from recents and reopen. | The book remains in the library with its last flushed passage. | Not run — no device |
| 27 | Low storage / permission denial | Deny a picker, then try a file that disappears before import. | The app shows a recoverable message and does not add a broken row. | Not run — no device |
| 28 | Release permissions | Build a release APK and inspect the merged manifest/APK permissions. | No `INTERNET`, no broad storage permission, no unrelated permission. | Static audit passed on the unsigned analysis APK; install not run — no device or signing credentials |
| 29 | Full backup | With the populated library, Settings → Create a backup, choose a folder through SAF, save a `.paperosbackup`, then inspect it with a ZIP tool. | Save picker appears; progress completes; archive contains `manifest.json`, `manifest.sha256`, `database.json`, `settings.json`, `books/`, and any covers; books are not in SQLite. | Not run — no device |
| 30 | Restore replacement | Change some progress/settings, then restore the backup from case 29 through SAF. Confirm the warning. | Preview counts and warnings appear; after restore, documents, covers, progress, bookmarks, annotations, notes, tasks, folder references, reading locators, and display profile match the backup exactly. | Not run — no device |
| 31 | Restore rejection and safety | Try a truncated archive, a modified payload, a traversal-name archive, a future-version manifest, and a wrong password-looking ZIP. Then restore a valid backup. | Each bad archive is rejected before the live library changes; no partial rows remain; a valid restore still succeeds; a safety snapshot exists. | Not run — no device |
| 32 | Restore cancellation | Begin a restore of a large archive and cancel before the final commit. Afterwards reopen the library. | Cancel is acknowledged, staging/copies are cleaned up, and the previous library/settings are unchanged. | Not run — no device |
| 33 | Annotation export | Open a book with annotations; export Markdown and JSON through the system save picker. | Files contain title, author, export date, chapters, excerpts, notes, annotation type, bookmarks, locations, and an explicit orphan notice when needed. Empty books export safely. | Not run — no device |
| 34 | E-Ink profile | Switch Settings → Display profile → E-Ink Friendly; browse Home, Library, Files, Notes and Settings; open an EPUB; select text; turn pages; wait for the clock minute. | Motion is still, pages are readable, selection is visible, chrome stays until dismissed, reader uses paged/tap zones with enlarged text/spacing, clock updates once a minute, and no vendor flash is claimed. | Not run — no e-ink device |
| 35 | Release artifact and signature | Build with user-owned credentials, verify the APK with `apksigner`, and install the universal and split-ABI APKs on a device. | Signature is the owner's certificate, not debug; universal and ABI-specific builds install; AAB is produced for Play; without credentials the release task fails closed. | Not run — no signing credentials were supplied |
| 36 | Responsive and empty states | Use a narrow phone in portrait, a tablet-width window, Android large text, and a library with zero documents. | No overflow; long titles wrap or ellipsize; empty/error states are readable and actionable; touch targets remain usable. | Not run — no device |

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

No Android device or emulator was connected during the v1.2 implementation. All
36 rows above are therefore **not run**; rows that require a release signature
also lack owner-supplied credentials. A debug APK was built successfully
(`dev.paperos.app.debug`, debug-signed, SHA-256
`d8269c92a72aada2ea94fa1e09936f8381bdccf8686a59b25e3d80fc32b5cf22`), but it was
not installed or exercised. Automated coverage is recorded in the final report
and README; it is not a substitute for this checklist.
