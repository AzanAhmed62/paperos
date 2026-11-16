# Release process

This document describes how PaperOS 1.4 is versioned, tested, signed, built and
audited. It is also the place to record what was actually produced on a given
machine. A build that fails is not a pass, and a debug APK is not release
evidence.

## Version

`pubspec.yaml` is the source of truth for the Android version:

```yaml
version: 1.4.0+5
```

`lib/config/app_config.dart` must agree:

```dart
static const String appVersion = '1.4.0';
static const int appBuildNumber = 5;
```

The Android application ID remains `dev.paperos.app`. The debug build appends
`.debug` through `applicationIdSuffix`; release does not. The Kotlin package
remains `dev.paperos.app`.

A version bump is a code change:

1. update `pubspec.yaml`;
2. update `PaperConfig.appVersion` and `appBuildNumber`;
3. update this document and the release notes;
4. run `flutter pub get`, analyzer and the full test suite;
5. rebuild every artifact and re-audit its manifest.

## Signing: fail-closed by design

The debug key exists only for debug builds. The release build type never falls
back to it. If release credentials are absent, `assembleRelease` and
`bundleRelease` throw:

```text
PaperOS release signing is not configured. Provide android/key.properties or
PAPEROS_* credentials.
```

Credentials can come from any of these sources, highest priority first:

### 1. Untracked `android/key.properties`

```properties
storeFile=..\\..\\secure\\paperos-release.jks
storePassword=...
keyAlias=paperos
keyPassword=...
```

The file and keystores are git-ignored. `storeFile` is resolved relative to the
`android/` project directory. Do not commit this file, a `.jks`, a `.keystore`, a
`.p12` or a screenshot containing a password.

### 2. Gradle properties

```powershell
.\gradlew.bat assembleRelease `
  -Ppaperos.keyProperties=C:\secure\paperos-release.properties
```

Or supply values directly:

```powershell
-Ppaperos.storeFile=C:\secure\paperos-release.jks
-Ppaperos.storePassword=...
-Ppaperos.keyAlias=paperos
-Ppaperos.keyPassword=...
```

### 3. Environment variables

```powershell
$env:PAPEROS_KEY_PROPERTIES = 'C:\secure\paperos-release.properties'
# or
$env:PAPEROS_STORE_FILE = 'C:\secure\paperos-release.jks'
$env:PAPEROS_STORE_PASSWORD = '...'
$env:PAPEROS_KEY_ALIAS = 'paperos'
$env:PAPEROS_KEY_PASSWORD = '...'
```

PaperOS never generates a keystore, never chooses a password and never prints
credential values. The build only records whether signing was configured.

### Unsigned analysis builds

For APK composition measurement on a machine without production credentials,
there is one explicit escape hatch. Pass the Gradle property through Flutter:

```bash
flutter build apk --release -Ppaperos.allowUnsignedRelease=true
flutter build appbundle --release -Ppaperos.allowUnsignedRelease=true
```

Flutter writes the unsigned APK to `app-release.apk` and the bundle to
`app-release.aab`. Rename the APK to `app-release-unsigned.apk` immediately
after the build; never leave an unsigned artifact under the signed-release name.
Neither artifact is installable or distributable. They are evidence of size and
manifest composition only, and the default release path remains fail-closed.

## Prerequisites

- Flutter SDK matching `pubspec.yaml` (this project was built with Flutter
  3.47.9 / Dart 3.13.7).
- JDK 17 or 21. This repository was built with JDK 21.0.8 (Temurin), Gradle 8.14,
  Android Gradle Plugin 8.11.1 and Kotlin 2.2.20. Gradle 8.14's embedded Kotlin
  DSL does not support JDK 25, so do not point `JAVA_HOME` at a JDK 25
  installation.
- Android SDK with the platform/build-tools required by the Flutter SDK. The RC
  audit used build-tools 36.0.0 and `targetSdkVersion=36`.
- Enough memory for Gradle. This repository lowers the daemon heap to 1.5 GB
  because a 4 GB heap was terminated on a 4 GB build host.

```bash
flutter config --jdk-dir=/usr/lib/jvm/java-21-openjdk-amd64
flutter --version
flutter pub get
flutter doctor -v
```

`android/local.properties` is machine-specific and git-ignored. It is generated
by Flutter and is not part of the release artifact.

## Verification commands

Run from the repository root:

```bash
flutter analyze --no-pub
flutter test --no-pub
```

The 1.4 RC automated baseline is **254 tests**: the original 134, the v1.2
backup, annotation-export, display, settings-envelope and text-scaling tests, the
v1.3 navigation, Back, shell-state, router-recovery, system-intent, launcher and
drawer tests, the v1.4 Home-title, settings-write, note-draft, app-ordering,
palette-contrast, picker-policy and EPUB async/probe tests, and the RC-1
abandoned-`.part` cleanup, EPUB background-failure and in-app privacy tests. All
254 passed in the final RC run; the engineering report records the exact result.
Do not copy an old count.

GitHub Actions runs `dart format --set-exit-if-changed`, `flutter analyze`, the
full test suite and a debug APK build on pushes to `main` and on pull requests.
Remote run `43714869648` passed on commit `8b2e7a7`. CI is a regression gate, not
a substitute for the manual device checklist.

Database tests use the real SQLite engine (`sqflite_common_ffi`), not a fake.
Device-only checks remain in `docs/manual-testing.md` and are not converted to
"passed" by a successful build.

## Build artifacts

After tests and analyzer:

```powershell
# Universal release APK (requires signing credentials)
flutter build apk --release

# Split-ABI release APKs (requires signing credentials)
flutter build apk --release --split-per-abi

# Android App Bundle (requires signing credentials)
flutter build appbundle --release
```

Expected output paths:

```text
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
build/app/outputs/bundle/release/app-release.aab
```

An unsigned analysis build is written to the same names; rename the universal APK
to `app-release-unsigned.apk` and the bundle to `app-release-unsigned.aab` before
recording them. The split-ABI APKs also need `-unsigned` in their names. A signed
build uses the plain names, so the rename is the only reliable distinction on
disk.

If signing is not configured, these commands must fail closed. In that case the
honest result is "signed release artifacts not produced" and the report must say
so. An unsigned analysis artifact may still be produced with the explicit
escape hatch.

For each artifact record:

- path;
- byte size;
- SHA-256;
- signing status (`apksigner verify --print-certs`);
- whether it is debug, unsigned-analysis or production-signed;
- the exact build command and tool versions.

## Merged manifest audit

The hand-written manifest is not enough; Flutter plugins and the Android
manifest merger can add components or permissions. Audit the actual release
artifact.

Merged manifest produced by Gradle:

```powershell
Get-Content build\app\intermediates\merged_manifests\release\AndroidManifest.xml
```

APK badging and permissions:

```bash
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump badging \
  build/app/outputs/flutter-apk/app-release-unsigned.apk
```

Signature:

```bash
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release-unsigned.apk
```

AAB manifest and validation (the bundle is a ZIP and its manifest is protobuf;
do not use `aapt2 dump xmltree` on it):

```bash
java -cp bundletool.jar com.android.tools.build.bundletool.BundleToolMain \
  dump manifest --bundle=build/app/outputs/bundle/release/app-release-unsigned.aab

java -cp bundletool.jar com.android.tools.build.bundletool.BundleToolMain \
  validate --bundle=build/app/outputs/bundle/release/app-release-unsigned.aab
```

`bundletool` is not an app dependency. The RC audit used version 1.18.1 resolved
from the existing Gradle cache; the official shaded jar is available from the
`google/bundletool` GitHub releases page. The plain library jar in the Gradle
cache needs its declared dependencies on the classpath and has no main manifest.

Expected:

- no `android.permission.INTERNET`;
- no `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE` or
  `MANAGE_EXTERNAL_STORAGE`;
- no unrelated permission, service or provider;
- exactly one exported activity, the launcher/Home/VIEW activity;
- the only exported receiver is AndroidX's
  `androidx.profileinstaller.ProfileInstallReceiver`, protected by
  `android.permission.DUMP` (a signature permission held by the system/shell,
  not by ordinary apps). Treat any other exported receiver as a failure;
- `android:allowBackup="false"`.

Record the actual result. A debug manifest containing `INTERNET` is not a
release failure if the release manifest does not; it is also not release
evidence.

## Size and composition

Use the release artifact, not debug:

```powershell
Get-Item build\app\outputs\flutter-apk\*.apk,
         build\app\outputs\bundle\release\*.aab |
  Select-Object FullName, Length

Get-FileHash build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256
```

APK composition can be inspected with Android Studio's APK Analyzer or
`apkanalyzer` from `cmdline-tools`. Record the largest entries (Flutter engine
and AOT snapshot, assets, fonts, native libraries) and whether `libapp.so` is
per-ABI. Do not describe a debug APK's size as release size.

Split-ABI APKs reduce device download size because each contains one Flutter
engine ABI. A universal APK contains all three and is expected to be larger.
The AAB lets Play split by ABI and screen density; it is not directly installed.

## Release checklist

1. Version and build number match in `pubspec.yaml` and `PaperConfig`.
2. `flutter analyze --no-pub` is clean.
3. Full `flutter test --no-pub` passes; exact count recorded.
4. New v1.4 Home-title, note-draft, app-ordering, palette, picker, EPUB
   async/probe, RC-1 cleanup/isolate and privacy tests pass, alongside the v1.3
   navigation/launcher and v1.2 backup/export/display/settings tests.
5. `flutter build apk --release` succeeds with user-owned credentials.
6. `flutter build apk --release --split-per-abi` succeeds.
7. `flutter build appbundle --release` succeeds.
8. Merged release manifest audited with the commands above; confirm package,
   `versionCode=5`, `versionName=1.4.0`, `minSdk=24`, `targetSdk=36`, no
   `INTERNET` and no broad storage permission.
9. AAB validated with `bundletool validate` and its manifest decoded with
   `bundletool dump manifest`.
10. APK signatures verified; the certificate is the owner's, not the debug key.
11. Artifact sizes and SHA-256 recorded.
12. `docs/manual-testing.md` updated with device results and explicit statuses.
13. Privacy policy has a verified developer contact and a public HTTPS URL that
    loads without authentication; the Play listing uses that exact URL.
14. Play Console Data Safety, ads, content rating, target audience and testing
    track are completed by the owner.
15. Known bugs and unverified paths listed in the final report.
16. Release notes do not claim device validation that did not happen.

## Manual testing gate

Compiling and passing unit/widget tests is not Android validation. Before a
public release, run all cases in `docs/manual-testing.md` on at least one physical
Android device, including the v1.4 Home title, draft notes, unified app ordering,
Ink palette and EPUB import/open path, the RC-1 privacy sheet and abandoned-import
cleanup, plus the v1.3 Back hierarchy, HOME-role selection, warm intents,
duplicate tasks, process-death recovery, SAF save/restore, native PDF, EPUB
selection, keep-awake and E-Ink appearance. No device was attached for the v1.4
or RC-1 verification, so rows 49–62 remain "Not run"; the partial v1.3 OnePlus 6T
run is historical evidence only.

The current RC assessment, artifact hashes and exact owner actions are in
`docs/release/paperos-1.4-rc-readiness.md`.
