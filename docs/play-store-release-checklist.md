# PaperOS Play Store release-preparation checklist

**Release:** PaperOS 1.4.0+5 (`dev.paperos.app`)<br>
**Prepared:** 16 November 2026<br>
**Status:** repository-side preparation only. No Play Console access was used,
no listing was created, and no artifact was uploaded.

This document lists what can be prepared in the repository and what still
requires the owner's Play Console account, signing key, device evidence and
decisions. It does not invent ratings, reviews, user counts, screenshots or
performance claims.

## 1. App identity and positioning

- **App name:** PaperOS (30-character Play title limit; the name fits).
- **Package:** `dev.paperos.app`.
- **Category:** Books & Reference is the closest fit. Tools or Productivity are
  alternatives if the owner wants to emphasise the optional Home-app role.
- **Positioning:** a quiet, local-first reading environment for Android that can
  also serve as an optional Home screen. It is a single app, not an operating
  system, and it does not replace Android.
- **Differentiators that are actually implemented:** no account, no ads, no
  analytics, no network permission in the release build, a text-first EPUB
  reader without a WebView, local notes/tasks, and a validated local backup.

## 2. Short description proposal

Play's short-description limit is 80 characters. Proposed text:

> A quiet, local-first reader and optional Home screen for PDF, EPUB and text.

This is 76 characters including spaces. It makes no performance, privacy or
feature claim that the code does not support. The owner may revise the wording,
but must keep it accurate.

## 3. Full description proposal

The following is a draft, not a claim of device validation:

```text
PaperOS is a quiet, local-first reading environment for Android.

Read PDF, EPUB 2/3 and plain-text documents in a monochrome, paper-inspired
interface. Import a file through Android's document picker; PaperOS keeps a
private copy so the book stays in your library even if the original moves.
Organise the library, track reading progress, add bookmarks, highlight or
underline EPUB text, attach notes, and export annotations as Markdown or JSON.

PaperOS also includes local notes, a dated task list, a Files browser for
folders you grant, and an optional app drawer. It can be selected as an Android
Home app if you want a quieter home screen; it still runs inside Android and
does not replace the operating system.

Everything the app stores stays on your device. The release build has no
account, no cloud sync, no analytics, no advertising and no network permission.
You can create a local backup archive and restore it later.

PaperOS is a text-first reader. It does not support DRM, fixed-layout EPUB,
comic panels, audio/video, MathML, scripting or publisher CSS. PDF pages are
rendered as images and do not support text selection or annotation. Backups are
plain ZIP files and are not encrypted or digitally signed; store them somewhere
you trust.

PaperOS is an independent app. It is not affiliated with or endorsed by Google
or Android.
```

Do not add "fastest", "best", "secure", "private" as an absolute claim, download
counts, awards, testimonials or device-validation claims.

## 4. Feature list for the listing

Only list features that exist in 1.4.0+5:

- Local library for PDF, EPUB 2/3 and plain-text files.
- Import through Android's Storage Access Framework; private copy kept in the
  app.
- EPUB reading without a WebView: table of contents, in-book search, paged and
  scrolling modes, typography controls, bookmarks, highlights, underlines and
  attached notes.
- PDF reading through Android's native `PdfRenderer` with persisted page
  progress and bookmarks.
- Plain-text reading with local pagination.
- Notes with title-only and body-only documents, draft-first creation and
  debounced saves.
- Dated task list, including undated tasks.
- Files browser for folders the user grants.
- Optional Android Home-app role and app drawer with pinned and recent apps.
- Local `.paperosbackup` create/restore with validation and a safety snapshot.
- Annotation export as Markdown or JSON.
- Standard and E-Ink Friendly display profiles (software-only; no vendor refresh
  API).
- No account, no ads, no analytics and no network permission in the release
  build.

Do not list cloud sync, text-to-speech, PDF annotation, DRM support, EPUB
fixed-layout, comic support, cross-device sync, widgets, or a "secure vault".
None is implemented.

## 5. Offline and local-first explanation

Use wording like:

> PaperOS is designed to work without an account or a connection. Books,
> reading progress, notes, tasks and settings are stored in the app's private
> storage on the device. The release build declares no INTERNET permission.
> Backups are files you choose to create and save; they are not uploaded by
> PaperOS.

Do not say "military-grade encryption", "zero data", "anonymous" or "untraceable".
The app does not encrypt its database or backups, and Android/Google Play may
process platform-level data under their own policies.

## 6. Known limitations to disclose honestly

- EPUB support is text-first. No DRM, fixed-layout pages, comic panels, audio,
  video, MathML, ruby, scripting or publisher CSS.
- PDF pages are rendered as bitmaps. No PDF text selection, highlights or
  annotations.
- Backups are unencrypted and unsigned plain ZIP files. Checksums detect damage,
  not authorship.
- Restore replaces the library; there is no merge mode.
- The E-Ink profile is software-only; no vendor panel-refresh API is used.
- The app drawer depends on Android package visibility and OEM launcher
  behaviour.
- No v1.4 physical-device validation has been recorded in this repository yet.
  Do not claim device-tested behaviour in the listing until it is.
- The app is not a full operating system and does not replace Android.

## 7. Privacy-policy publication requirement

A public privacy-policy URL is mandatory for a Play listing.

Repository draft: `docs/privacy-policy.md` and `docs/privacy-policy.html`.

Before the URL can be entered in Play Console:

1. Add a real developer contact method to the policy.
2. Publish the HTML at a stable public HTTPS URL.
3. Open the URL in a normal browser and confirm it loads without authentication.
4. Confirm the policy text matches the shipped app version.
5. Enter the verified URL in Play Console.

**Current status: BLOCKED.** No developer contact and no public hosting URL have
been supplied or verified. Do not enter a placeholder URL.

## 8. Data Safety questionnaire draft

This is a source-code-based draft, not a substitute for the owner's review of
Play Console's current definitions.

- **Does the app collect or share any required user data type?** Draft answer:
  **No.** The release manifest has no `INTERNET` permission, the code contains
  no network client, and no analytics, advertising, crash-reporting or
  attribution SDK is configured.
- **Data stored only on the device:** imported documents, covers, reading
  progress, bookmarks, annotations, notes, tasks, settings, pinned/recent app
  package names and granted-folder references. Local storage is not
  "collection" when it is not transmitted off the device, but the owner should
  confirm the current Play definition.
- **Data shared with third parties:** none by PaperOS. Google Play and Android
  may process platform-level data under their own policies.
- **Encryption in transit:** not applicable to PaperOS because it does not
  transmit app data. Backups are user-initiated files and are not encrypted.
- **Data deletion:** users can remove documents, notes and tasks in the app, and
  uninstall the app to remove private storage. There is no account and no
  server-side copy. Exported backups remain wherever the user saved them.
- **Ads or analytics:** none.
- **Third-party SDKs:** open-source local libraries only; none configured for
  analytics or data transmission.

The owner must complete the actual Play Console form and keep it consistent with
the privacy policy and the shipped build.

## 9. Ads declaration

- **Contains ads:** No.
- No AdMob, advertising ID, attribution or mediation SDK is present.
- No `com.google.android.gms.permission.AD_ID` permission is declared.
- Do not enable "Contains ads" merely because the app can display user-imported
  content.

## 10. App access instructions for reviewers

- No login, account, invite code or paid entitlement is required.
- All primary surfaces are reachable from the five bottom destinations: Home,
  Library, Files, Notes and Settings.
- The app can be reviewed without selecting PaperOS as the Home app. The Home
  role is optional and requested only when the reviewer taps the relevant
  setting.
- To test import, the reviewer can use any PDF, EPUB or `.txt` file already on
  the test device, or push a synthetic file with `adb push`.
- To test backup, the reviewer needs a document provider that can create a file;
  Android's Files app or a cloud provider available on the test device works.
- No reviewer credentials should be placed in the listing.

## 11. Content rating and target audience

These are owner decisions, not repository facts.

- **Content rating:** complete the IARC questionnaire in Play Console. The app
  has no ads, no user-to-user communication, no public content feed and no
  network. It can open arbitrary user-supplied documents, so the owner must
  answer the questionnaire for the actual shipped behaviour. Do not guess a
  rating in the listing.
- **Target audience:** the owner must choose the age groups. A conservative
  starting point is a general audience that is not child-directed, because the
  app can display arbitrary user-imported content and has no child-safety or
  parental-control features. This is a recommendation, not a completed
  declaration.
- **News app / COVID / financial / health declarations:** not applicable unless
  the owner's listing content changes.
- **Government app declaration:** not applicable.
- **Data safety:** see section 8.

## 12. Required store-listing assets

Prepare real assets, not mockups of features that do not exist:

- **App icon:** 512 × 512 PNG, 32-bit, under 1 MB. Use the shipped launcher
  identity, not a new fictional brand.
- **Feature graphic:** 1024 × 500 PNG or JPEG, no transparency, under 15 MB.
- **Phone screenshots:** at least 2, up to 8. Use 16:9 or 9:16, minimum 320 px,
  maximum 3840 px on the long edge. Capture from the actual app.
- **7-inch tablet screenshots:** required if the listing targets tablets;
  capture from the actual app at tablet width.
- **10-inch tablet screenshots:** same condition.
- **Chromebook screenshots:** only if the owner targets Chromebooks.
- **Promotional video:** optional; do not use a video that shows features the app
  does not have.
- **Short description:** section 2.
- **Full description:** section 3.
- **Privacy-policy URL:** blocked until section 7 is complete.
- **Contact email:** owner must provide a real, monitored address.
- **Contact website / phone:** optional; do not invent.

No screenshots, feature graphics or videos exist in this repository as Play-ready
assets. Do not use AI-generated or staged images that depict features the app
does not implement.

## 13. Screenshots to capture from the actual app

Capture these after the device checklist passes. Use synthetic books and notes,
not copyrighted or personal content:

1. Paper Home with the custom title, clock, quick actions and a pinned app.
2. Library with a few synthetic PDF/EPUB/TXT rows and progress.
3. EPUB reader page with the table of contents or search sheet open.
4. EPUB selection with a highlight or attached note visible.
5. Notes list or editor with a short synthetic note.
6. Tasks screen with a dated and an undated task.
7. Settings → About → Privacy sheet, showing the local-first statement.
8. Backup/restore preview with synthetic counts.

Do not show a fake "0 trackers" badge, a fake encryption claim, a fake device
frame, or a screenshot of a feature that is not in the build.

## 14. Upload signing status

**Current status: BLOCKED.**

- No owner upload keystore or `android/key.properties` is present in this
  checkout.
- Release builds fail closed without owner-supplied credentials.
- The unsigned release APKs/AAB produced for structural analysis are **not
  installable or uploadable**.
- The debug APK is debug-signed and is not a Play artifact.

Owner actions before upload:

1. Decide whether to use Play App Signing (recommended; confirm current Play
   Console flow).
2. Create or supply an owner-controlled upload keystore outside the repository.
3. Store credentials in an untracked `android/key.properties` or `PAPEROS_*`
   environment variables. Never commit them.
4. Build a signed AAB with `flutter build appbundle --release`.
5. Verify the signature with `apksigner verify --print-certs`.
6. Upload the signed AAB to the chosen testing track.

Do not generate a production key on the owner's behalf, and do not print
keystore passwords or secret properties.

## 15. Testing-track recommendation

1. **Internal testing** first: upload the signed AAB, install from the internal
   track on at least one physical device, and run `docs/manual-testing.md`.
2. **Closed testing** if the owner wants a wider device/OEM sample or if the
   Play Console account requires it. Confirm the current tester-count and
   duration requirements in Play Console; they can change.
3. **Production** only after device validation, signing verification, privacy
   publication and Play Console declarations are complete.

Do not use a production rollout as the first device test.

## 16. Exact Play Console steps still requiring the owner

1. Sign in to the Play Console account that will own the app.
2. Create the app with name `PaperOS`, default language, app/game selection and
   free/paid selection.
3. Complete the app-content declarations: privacy policy, ads, content rating,
   target audience, news, data safety and any government/financial/health
   declarations that apply.
4. Add the verified privacy-policy URL and a real contact email.
5. Upload the signed AAB to internal testing.
6. Add internal testers and install from the track on a physical device.
7. Capture real screenshots and the feature graphic from that build.
8. Complete the store listing: title, short description, full description,
   graphics, screenshots, category and contact details.
9. Resolve any Play Console warnings or policy flags.
10. Promote to closed testing if needed, then to production only after the
    release gates in `docs/release/paperos-1.4-rc-readiness.md` are closed.

## 17. Release gate summary

| Gate | Status | Required action |
| --- | --- | --- |
| Version and package | Ready | `1.4.0+5`, `dev.paperos.app` |
| Automated tests and analysis | Passed on the working tree | Rerun after every change |
| Signed AAB | Blocked | Owner keystore and upload |
| Physical-device checklist | Not run | Attach a device and run the checklist |
| Privacy policy URL | Blocked | Add contact, host, verify |
| Data Safety declaration | Draft only | Owner completes in Play Console |
| Content rating / target audience | Not decided | Owner completes |
| Listing text | Draft | Owner reviews and approves |
| Screenshots and graphics | Not created | Capture from the real build |
| Ads declaration | No ads | Owner confirms in Play Console |
| Testing track | Not started | Internal testing after signing |
