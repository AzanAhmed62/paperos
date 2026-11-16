# PaperOS 1.4 RC readiness

**Release:** PaperOS 1.4.0+5 (`dev.paperos.app`)
**Branch:** `feat/paperos-1.4-polish-performance`
**Commit under review:** `8b2e7a7`
**Report date:** 16 November 2026
**Assessment:** **Conditionally ready for RC testing. Not production-ready.**

This report records the actual repository, CI, build and manifest state observed
on 16 November 2026. It does not convert an automated test, a build or a static
manifest audit into a physical-device pass, a Play Console result or a
performance measurement.

## Executive assessment

The RC-phase automated gate is green: formatting and analysis are clean, all 254
tests pass, all four Android build types succeed, and the merged release manifest
has the expected package, version, target SDK, filters and permission set.

The release is **not** ready for production or for a Play upload:

- there is no owner upload keystore, so the release APK and AAB are unsigned
  analysis artifacts;
- no Android device or emulator is attached, so every v1.4/RC-1 device scenario
  is **Not run**;
- the privacy policy has no verified developer contact and no public HTTPS URL;
- no Play Console account was used, so Data Safety, content rating, target
  audience, listing assets and testing tracks are incomplete;
- the uncommitted RC-phase changes have not run on remote CI.

RC testing can begin with the debug APK for UI-only cases, but a signed artifact
is required before any installable release candidate or internal-track upload
can be evaluated.

## Repository state

| Item | Observed state |
| --- | --- |
| Branch | `feat/paperos-1.4-polish-performance` |
| HEAD | `8b2e7a7` (`8b2e7a7d276f4514ad8b5ad3f569c4a16ac3707a`) |
| `origin/main` | `b333155` (`b333155a3d7d59e450ee04b8a49527ccfedda8f9`) |
| Pull request | [#1](https://github.com/AzanAhmed62/paperos/pull/1), open, not draft, mergeable, not merged |
| PR diff at `8b2e7a7` | 48 files changed, +2,756 / −527 |
| Remote CI | Run `43714869648` on `8b2e7a7`: format/analyse/test **success**, Android debug build **success** |
| Working tree | 17 files: 11 modified, 6 new (including this report); uncommitted; nothing pushed |
| Remote CI coverage | Does **not** include the uncommitted RC-phase changes |

No commit, push, merge, release, GitHub setting change or remote branch change
was performed during this audit.

## RC-phase work completed

### Abandoned import partials

- Added `AppStorage.purgeAbandonedImports({Duration maxAge = const Duration(days: 1)})`.
- It removes only regular files ending in `.part` directly inside `library/`.
  It does not recurse, does not touch completed library files and swallows
  filesystem errors so maintenance never blocks startup.
- `cleanupDisposableStorage()` now calls it alongside the existing trash and
  backup-staging cleanup. `main()` already runs that method unawaited.
- A fresh partial is assumed to belong to a running import and is preserved.
- `test/unit/app_storage_test.dart` covers stale removal, fresh preservation,
  completed-file preservation, non-recursion and the startup hook.

### EPUB background failure policy

- Added an injectable `EpubIsolateRunner` seam; production still uses
  `Isolate.run`.
- Only `UnsupportedError` falls back to the calling isolate. Any other isolate
  startup or execution failure becomes a recoverable `EpubParseException`
  instead of silently re-running a large parse on the UI isolate.
- The shared serialised queue releases after a failure, so the next book can
  still open.
- Four tests cover parse failure, probe failure, unsupported-isolate fallback and
  queue recovery.

### Privacy and Play Store preparation

- `docs/privacy-policy.md` and `docs/privacy-policy.html` describe the shipped
  local-first behaviour, including unencrypted backups and deletion paths. Both
  mark the missing developer contact and public URL as publication blockers.
- Settings → About → Privacy shows a short local statement with no URL or
  contact placeholder. It is widget-tested.
- `docs/play-store-release-checklist.md` records positioning, description
  drafts, implemented features, honest limitations, a Data Safety draft, ads,
  reviewer access, content rating, assets, signing, testing tracks and the exact
  owner actions still required.

## Verification table

Status values are deliberately narrow. **PASS** means the stated check was run
and succeeded on this checkout. **BLOCKED** means an external credential,
account, device or owner decision is required. **NOT RUN** means no evidence was
produced.

| Check | Status | Evidence |
| --- | --- | --- |
| Dart formatting | **PASS** | `dart format --output=none --set-exit-if-changed lib test`: 128 files, 0 changed |
| Static analysis | **PASS** | `flutter analyze --no-pub`: no issues found |
| Full automated suite | **PASS** | 254 tests passed in 102.24 s |
| Debug APK build | **PASS** | `app-debug.apk`, 197,526,652 bytes, debug-signed |
| Unsigned universal release APK | **PASS** | `app-release-unsigned.apk`, 58,651,176 bytes |
| Unsigned split-ABI release APKs | **PASS** | armeabi-v7a, arm64-v8a and x86_64 built |
| Unsigned release AAB | **PASS** | `app-release-unsigned.aab`, 57,270,392 bytes |
| AAB structural validation | **PASS** | `bundletool 1.18.1 validate`: one `base` feature module, exit 0 |
| AAB manifest decode | **PASS** | `bundletool dump manifest`: package, version, SDK and filters verified |
| Release permission audit | **PASS** | No `INTERNET`, no storage permission; only the app-defined signature permission |
| `targetSdkVersion` | **PASS** | 36 in the merged AAB manifest and APK badging |
| Release signing | **BLOCKED** | No owner keystore or credentials; release artifacts are unsigned |
| Release APK signature verification | **FAIL (expected)** | `apksigner verify`: `DOES NOT VERIFY — Missing META-INF/MANIFEST.MF` |
| AAB signature verification | **FAIL (expected)** | `jarsigner -verify`: `jar is unsigned` |
| Debug signature | **PASS (debug only)** | Android Debug certificate, SHA-256 `13a339f3…82f99` |
| Physical-device checklist | **NOT RUN** | No Android device or emulator; rows 49–62 not run |
| Performance/runtime claims | **NOT RUN** | No device benchmark; no runtime numbers claimed |
| In-app privacy sheet on device | **NOT RUN** | Widget test passes; device layout/large-text check not run |
| Privacy-policy publication | **BLOCKED** | No verified developer contact or public HTTPS URL |
| Play Console declarations/listing | **BLOCKED** | No Play Console access; owner actions outstanding |
| Remote CI on RC-phase changes | **NOT RUN** | Changes are uncommitted; only `8b2e7a7` is remotely verified |

## Artifact evidence

All release artifacts are **unsigned analysis artifacts**. They are not
installable, uploadable or distributable.

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` | 197,526,652 | `7264422456ab8dbf9765b72303b394e3df140d360bad30b2b606e13a0c00add0` |
| Universal release APK | `build/app/outputs/flutter-apk/app-release-unsigned.apk` | 58,651,176 | `ccc0a2f9ebe3cf5525844c30a9682b07b2f11de0a55554895911ce60ff4e209e` |
| `armeabi-v7a` release APK | `build/app/outputs/flutter-apk/app-armeabi-v7a-release-unsigned.apk` | 18,844,954 | `9d582a771b4efebbc07ecea46f9c2097ddb3b98063989a07cada4fe5e9d5509f` |
| `arm64-v8a` release APK | `build/app/outputs/flutter-apk/app-arm64-v8a-release-unsigned.apk` | 21,261,762 | `c66c18a45f2fd33dc32651aa9937420fad5f1347ae7cfaad39985371584a791a` |
| `x86_64` release APK | `build/app/outputs/flutter-apk/app-x86_64-release-unsigned.apk` | 22,753,222 | `082248af9d2ca4df8bdc881037b34268bdbbdb0d9d2ad45ac99a43c4063c3358` |
| Release AAB | `build/app/outputs/bundle/release/app-release-unsigned.aab` | 57,270,392 | `7f46e5cc9f0cc1033453ad84e47d9af424bb8c3eea7edc65a437547240b1e83b` |

Build commands:

```bash
flutter build apk --debug --no-pub
flutter build apk --release --no-pub -Ppaperos.allowUnsignedRelease=true
flutter build apk --release --split-per-abi --no-pub -Ppaperos.allowUnsignedRelease=true
flutter build appbundle --release --no-pub -Ppaperos.allowUnsignedRelease=true
```

Measured build wall times: debug 141.1 s, universal release 160.6 s, split-ABI
release 221.5 s, AAB 154.0 s. These are build-host durations, not runtime or
performance benchmarks.

The universal APK contains the RC error string
`PaperOS could not start a background reader for this EPUB.` in
`lib/arm64-v8a/libapp.so`, confirming it was built from the current tree rather
than a cached earlier build.

## Manifest evidence

The merged AAB manifest was decoded with `bundletool 1.18.1 dump manifest`; the
universal APK was checked with `aapt2 dump badging`:

- package `dev.paperos.app`;
- `versionCode=5`, `versionName=1.4.0`;
- `minSdkVersion=24`, `targetSdkVersion=36`, `compileSdkVersion=36`;
- no `android.permission.INTERNET`;
- no `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`,
  `MANAGE_EXTERNAL_STORAGE` or `ACCESS_MEDIA_LOCATION`;
- the only permission is the app-defined signature permission
  `dev.paperos.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`;
- `android:allowBackup="false"`, `android:fullBackupContent="false"`;
- `android:enableOnBackInvokedCallback="true"`;
- one exported activity, `dev.paperos.app.MainActivity`, with MAIN/LAUNCHER,
  MAIN/HOME and VIEW filters for `application/pdf`, `application/epub+zip` and
  `text/plain` on `content` and `file` schemes;
- one exported receiver, AndroidX `ProfileInstallReceiver`, protected by
  `android.permission.DUMP`;
- `bundletool validate` exited 0 and reported a single `base` feature module.

The debug APK is package `dev.paperos.app.debug`, version `1.4.0-debug` (5), and
adds `android.permission.INTERNET` for Flutter tooling. That is not release
evidence.

## Blockers and owner actions

| Blocker | Current state | Owner action required |
| --- | --- | --- |
| Production signing | No `android/key.properties`, keystore or `PAPEROS_*` credentials. Release tasks fail closed. | Supply an owner-controlled upload keystore outside the repository, configure credentials, build and verify a signed AAB. Decide on Play App Signing. |
| Physical-device validation | `adb devices` empty; `flutter emulators` reports none. Rows 49–62 are Not run. | Attach a physical Android device (preferably Android 15+ and an e-ink device for the display cases) and run `docs/manual-testing.md`. |
| Privacy-policy publication | Draft only; no verified contact or public URL. | Add a real monitored contact, host `docs/privacy-policy.html` at a stable public HTTPS URL, verify it loads without authentication, and enter that URL in Play Console. |
| Play Console declarations | No account access was used. | Complete Data Safety, ads, content rating, target audience and all other app-content declarations in Play Console. |
| Store listing assets | No Play-ready screenshots, feature graphic or icon export. | Capture real screenshots and create the feature graphic from the shipped build; do not stage features that do not exist. |
| Testing track | Not started. | Upload the signed AAB to internal testing, install from the track on a device and repeat the core checklist. |
| Remote CI coverage | RC-phase changes are uncommitted. | Review the diff, commit and push to PR #1, and wait for remote CI to pass on the new commit. |

## Exact next step

**Review the uncommitted RC diff (17 files: 11 modified, 6 new, including this
report) and authorize a commit and push to PR #1 so remote CI verifies the
RC-phase changes.** This is the only remaining local verification gap. Do not
upload the unsigned artifacts, publish the privacy draft with a placeholder, or
describe the build as device-tested or production-signed.

After that CI run passes, the release sequence is:

1. supply owner signing credentials and build a signed AAB;
2. verify the signature and install the signed build on a physical device;
3. run rows 49–62 plus the core rows in `docs/manual-testing.md`;
4. add the verified privacy contact/URL and complete Play Console declarations;
5. upload the signed AAB to internal testing and validate the installed build.

## What is explicitly not claimed

- No physical-device pass for v1.4 or RC-1.
- No performance, memory, battery or startup measurement.
- No production signature, Play upload, review, rating, install count or release.
- No encryption of the database, backups or app-private storage.
- No network, account, analytics, advertising or cloud-sync behaviour in the
  release build.
- No claim that the unsigned APK/AAB can be installed or distributed.
- No claim that the privacy policy is published or that a developer contact has
  been verified.
