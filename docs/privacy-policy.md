# PaperOS privacy policy

**App:** PaperOS (`dev.paperos.app`)<br>
**Version covered:** 1.4.0+5<br>
**Effective date:** 16 November 2026<br>
**Status:** Draft for publication. This policy is not yet hosted at a public
URL and does not yet name a developer contact. Both are required before the
Google Play listing can be published. See [Publication status](#publication-status).

PaperOS is a local-first reading environment and an optional Android Home app.
This policy explains what the app stores, what it does not collect, and how you
can delete it. It describes the behaviour of the release build.

## The short version

- PaperOS keeps your library, reading progress, notes, tasks and settings on
  your device.
- The release build has no network permission, no account, no analytics, no
  advertising and no cloud sync.
- PaperOS does not send your documents or reading data to the developer or any
  third party.
- Backups are plain ZIP files. They are **not encrypted or digitally signed**.
  Store them somewhere you trust.
- Uninstalling PaperOS removes its private app data. Backups and files you saved
  elsewhere are not removed.

## What PaperOS stores on your device

PaperOS stores the following in its private application storage:

- **Documents you import.** When you choose a PDF, EPUB or plain-text file,
  PaperOS copies it into its private library folder. The original file stays
  where it was. PaperOS does not re-read the original after the copy.
- **Covers.** A small cover image extracted from an EPUB may be stored so the
  library can show it.
- **Library records.** A private SQLite database holds document titles,
  authors, file names, source references, reading positions, page counts,
  favourite flags, reading time, bookmarks and annotations.
- **Notes and tasks.** Note titles and bodies, task titles, due dates and
  completion state are stored in the same private database.
- **Settings.** Appearance, reader typography, display profile, the custom Home
  title, launcher preferences, and pinned and recent app package names are
  stored in Android app preferences. Granted-folder references are stored as rows
  in the same private SQLite database as the library records.
- **Temporary recovery data.** Deleted library files are held in a private trash
  folder for up to seven days. Restore operations keep up to three private
  safety snapshots. Abandoned backup staging is removed after one day.

This data stays inside PaperOS' private app storage. Other ordinary apps cannot
read it. A rooted device, a debug build, an operating-system backup tool or
malware with equivalent privileges may be able to access it. PaperOS does not
add its own database or archive encryption in 1.4.

## Documents you choose

PaperOS uses Android's Storage Access Framework:

- You choose a file with the Android document picker, or grant a folder in the
  Files screen.
- PaperOS receives access only to what you selected. It does not request broad
  storage access and does not browse outside folders you granted.
- The imported copy is what the library opens. If you later move or delete the
  original, the library copy still works.
- When another app opens a PDF, EPUB or text file with PaperOS, Android gives
  PaperOS a one-time grant for that file. PaperOS copies it into its library in
  the same way.

Removing a granted folder from PaperOS releases that folder reference. It does
not delete the folder or its contents.

## The app drawer

PaperOS can be used as an Android Home app and includes an app drawer. To build
the drawer, PaperOS asks Android for activities that respond to the launcher
intent (`MAIN` + `LAUNCHER`) and for the current Home app. It reads the app's
label, package name, activity name, system-app flag and icon so it can display
and launch the app.

PaperOS does not read other apps' private data, files, accounts or usage history.
It does not request the broad `QUERY_ALL_PACKAGES` permission. The package
visibility declarations in its manifest are Android visibility rules, not
permissions to read app content. Pinned and recent package names are stored
locally as launcher preferences.

## Network access, accounts, analytics and advertising

The release build of PaperOS:

- declares **no `INTERNET` permission**;
- has **no account system**, sign-in, cloud sync or remote backup service;
- contains **no analytics, telemetry, crash-reporting, advertising or
  attribution SDK**;
- does not fetch books, covers, fonts or updates from a network;
- does not sell or share data.

The Android debug build adds the `INTERNET` permission because the Flutter
development tool needs it for debugging and hot reload. Debug builds are not
distributed to users.

Google Play and Android itself may collect install, device or usage information
under their own privacy policies. PaperOS does not control that platform-level
collection and does not receive it.

## Backups

PaperOS can create a `.paperosbackup` file at a destination you choose through
Android's save picker. A backup is an ordinary ZIP archive. It is **not
encrypted** and **not digitally signed**. It contains:

- the full text of every imported book;
- covers;
- the library database contents: documents, reading progress, bookmarks,
  annotations, notes, tasks and granted-folder references;
- settings, including the custom Home title, pinned and recent app package
  names, and display preferences;
- a manifest with sizes and SHA-256 checksums.

The checksums can detect corruption or casual modification. They do not prove
who created the archive and do not make it confidential. Anyone who can read the
file can read the books, notes and reading history inside it. Anyone who can
modify it can build a different archive. Store backups on media you trust. If
you need to move a backup through an untrusted channel, encrypt it with a tool
you trust first; PaperOS cannot open an externally encrypted container directly.

Restoring a backup replaces the current library after validation and after
creating a private safety snapshot. A malicious but structurally valid backup
can still replace the library if you confirm it. Integrity checks are not a
trust decision.

## Deleting your data

You can delete data in these ways:

- **Remove every document:** Settings → Storage → Remove every document deletes
  the library copies and reading data. Notes and tasks are kept.
- **Delete individual items:** remove documents from the library, and delete
  notes and tasks from their screens.
- **Uninstall PaperOS:** Android removes the app's private storage, including
  its database, settings, library copies, covers, trash and safety snapshots.

These actions do **not** delete:

- the original documents you imported;
- backup files you exported to another folder or device;
- files you shared or exported through Android;
- copies made by other apps or by an operating-system backup tool.

PaperOS has no account to delete and no server-side copy to request.

## Children

PaperOS does not create accounts, show advertising or collect personal
information from any user, including children. Documents and notes are supplied
by the user. The Google Play target-audience and content-rating declarations are
completed by the developer in Play Console; this policy does not replace those
declarations.

## Third-party components

PaperOS uses open-source Flutter and Android libraries for local storage, ZIP
handling, cryptography, XML parsing, file selection and user-interface
rendering. They are packaged inside the app and are not configured to collect
analytics or transmit data. The app bundles the Noto Serif font under the SIL
Open Font License 1.1.

## Changes to this policy

This policy describes PaperOS 1.4.0+5. If a later version changes what the app
stores, where it sends data, or how backups work, this policy must be updated
before that version is published. The effective date at the top identifies the
version being described.

## Contact

**Publication blocker:** no verified developer contact has been supplied for
this policy. A real support email address or other contact method must be added
here before the policy is published. Do not publish this draft with an invented
or placeholder address.

## Publication status

**Publication blocker:** this file is a repository draft. It is not hosted at a
public URL, and no public URL has been verified. Google Play requires a publicly
reachable privacy-policy URL before a listing can be published.

Before publication, the developer must:

1. add a real developer contact method to this policy;
2. publish the HTML version at a stable public HTTPS URL;
3. open that URL in a browser and confirm it loads without authentication;
4. enter the verified URL in Play Console and keep it available for as long as
   the app is listed;
5. update the policy whenever the app's data behaviour changes.

Until those steps are complete, the absence of a public policy URL and a
developer contact is a release blocker, not a completed privacy claim.
