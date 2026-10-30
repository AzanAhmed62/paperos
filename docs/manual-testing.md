# Manual Android testing

This checklist covers behaviour that automated tests cannot prove: SAF pickers,
native PDF rendering, WebView-free EPUB touch selection, e-ink refresh, keep-
screen-on, Home-role selection, and app launching.

Record the result, the Android version, and the device model for each run. A
check is not "passed" because the app compiled.

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

## Suggested test files

Prepare these before starting:

- a valid EPUB 3 with nested contents;
- a valid EPUB 2 with an NCX;
- an EPUB whose private copy can be deleted and re-imported from the same source;
- an EPUB with an image-only chapter;
- a `.txt` file longer than one screen;
- a PDF longer than one page;
- a random or truncated file for malformed-file handling.

Do not use a purchased or DRM-protected book as a correctness oracle. PaperOS
does not support DRM.

## Checklist

| # | Area | Steps | Expected result | Result |
| --- | --- | --- | --- | --- |
| 1 | Install and launch | Install the APK normally; open it; close it and open it again. | Five destinations appear: Home, Library, Files, Notes, Settings. No debug banner. | Not run |
| 2 | Settings persistence | Change theme, interface text size, reader font size, line height, margins, and flow; force-stop and reopen. | Settings are restored. | Not run |
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
| 25 | Home role and app drawer | Settings → request Home role; choose PaperOS as Home; open the app drawer; pin and launch an app. | The role picker appears; the drawer lists launchable apps; launch returns to the app. | Not run |
| 26 | Process death | While reading an EPUB, remove the task from recents and reopen. | The book remains in the library with its last flushed passage. | Not run |
| 27 | Low storage / permission denial | Deny a picker, then try a file that disappears before import. | The app shows a recoverable message and does not add a broken row. | Not run |
| 28 | Release permissions | Build a release APK and inspect the merged manifest/APK permissions. | No `INTERNET`, no broad storage permission, no unrelated permission. | Not run |

## What to capture for a failure

Include:

- the step number above;
- device model, Android version, and whether the screen is e-ink;
- APK SHA-256;
- the exact document format and whether it opens in another reader;
- a screenshot or a short screen recording;
- logcat around the failure, if available;
- whether the failure survives a force-stop and relaunch.

Do not attach a copyrighted book. A minimal synthetic EPUB is enough to reproduce
most parser and layout issues.

## Current environment result

No Android device or emulator was connected during the v1.1 implementation. All
28 rows above are therefore **not run**. Automated coverage is recorded in the
README and the final report; it is not a substitute for this checklist.
