# Release process

This document describes how PaperOS 1.2 is versioned, tested, signed, built and
audited. It is also the place to record what was actually produced on a given
machine. A build that fails is not a pass, and a debug APK is not release
evidence.

## Version

`pubspec.yaml` is the source of truth for the Android version:

```yaml
version: 1.2.0+3
```

`lib/config/app_config.dart` must agree:

```dart
static const String appVersion = '1.2.0';
static const int appBuildNumber = 3;
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
- JDK 17 or 21. This repository was built with JDK 17.0.20.1, selected through
  `flutter config --jdk-dir`. Gradle 8.14's embedded Kotlin DSL does not support
  JDK 25, so do not point `JAVA_HOME` at a JDK 25 installation.
- Android SDK with the platform/build-tools required by the Flutter SDK.
- Enough memory for Gradle. This repository lowers the daemon heap to 1.5 GB
  because a 4 GB heap was terminated on a 4 GB build host.

```powershell
flutter config --jdk-dir=/usr/lib/jvm/java-17-openjdk-amd64
flutter --version
flutter pub get
flutter doctor -v
```

`android/local.properties` is machine-specific and git-ignored. It is generated
by Flutter and is not part of the release artifact.

## Verification commands

Run from the repository root:

```powershell
flutter analyze
flutter test
```

The 1.2 automated baseline is **163 tests**: the original 134 plus the new
backup, annotation-export, display, settings-envelope and text-scaling tests.
All 163 passed in the final release run; the final report records the exact
result. Do not copy an old count.

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

An unsigned analysis build is written to
`build/app/outputs/flutter-apk/app-release.apk`; rename it to
`app-release-unsigned.apk` before recording it. A signed build uses the same
`app-release.apk` name, so the rename is the only reliable distinction on disk.

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

```powershell
$buildTools = Get-ChildItem "$env:ANDROID_HOME\build-tools" -Directory |
  Sort-Object Name -Descending | Select-Object -First 1
& "$($buildTools.FullName)\aapt.exe" dump badging build\app\outputs\flutter-apk\app-release.apk
& "$($buildTools.FullName)\aapt.exe" dump permissions build\app\outputs\flutter-apk\app-release.apk
```

Signature:

```powershell
& "$($buildTools.FullName)\apksigner.bat" verify --verbose --print-certs `
  build\app\outputs\flutter-apk\app-release.apk
```

AAB manifest (the bundle is a ZIP; extract the base manifest or use the bundle
tool):

```powershell
& "$($buildTools.FullName)\aapt2.exe" dump xmltree `
  build\app\outputs\bundle\release\app-release.aab `
  --file base/manifest/AndroidManifest.xml
```

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
2. `flutter analyze` is clean.
3. Full `flutter test` passes; exact count recorded.
4. New backup, export, display and settings tests pass on real SQLite.
5. `flutter build apk --release` succeeds with user-owned credentials.
6. `flutter build apk --release --split-per-abi` succeeds.
7. `flutter build appbundle --release` succeeds.
8. Merged release manifest audited with the commands above.
9. APK signatures verified; the certificate is the owner's, not the debug key.
10. Artifact sizes and SHA-256 recorded.
11. `docs/manual-testing.md` updated with device results and explicit statuses.
12. Known bugs and unverified paths listed in the final report.
13. Release notes do not claim device validation that did not happen.

## Manual testing gate

Compiling and passing unit/widget tests is not Android validation. Before a
public release, run all cases in `docs/manual-testing.md` on at least one physical
Android device, including SAF save/restore, native PDF, EPUB selection,
process-death recovery, Home role, keep-awake, E-Ink appearance and the release
manifest audit. No device was attached during this repository's 1.2
verification, so those rows remain "Not run".
