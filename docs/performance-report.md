# Performance and artifact report

This document records what was actually measured for PaperOS 1.2.0+3 on the
machine that produced the release candidates. It deliberately separates
**artifact measurements** (sizes, checksums, manifest contents, build time) from
**runtime performance**, which was not measured because no Android device or
emulator was available.

A number in this document is either measured on this checkout or marked as not
measured. No device benchmark is inferred from a desktop test run.

## Environment

| Item | Value |
| --- | --- |
| Host | Ubuntu 24.04.5 LTS, x86_64 |
| CPU | Intel Core i5-6200U, 2 cores / 4 threads |
| Memory | 7.6 GiB RAM, 3.7 GiB swap |
| Disk free during build | approximately 3.8 GiB at the end of the run |
| Flutter | 3.47.9 stable, engine `89c39edfdf` |
| Dart | 3.13.7 |
| Java | OpenJDK 17.0.20.1 (selected with `flutter config --jdk-dir`) |
| Gradle | 8.14 |
| Android Gradle Plugin | 8.11.1 |
| Kotlin | 2.2.20 |
| Android SDK | compileSdk 36, targetSdk 36, minSdk 24 |
| Application ID | `dev.paperos.app` |
| Version | `1.2.0` (`versionCode` 3) |

The host was shared with other work during the run and had little free disk
space. Build times below are therefore upper bounds for a normal developer
machine, not a benchmark of Flutter or Gradle.

## Commands and results

```bash
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
flutter build apk --release -Ppaperos.allowUnsignedRelease=true
flutter build apk --release --split-per-abi -Ppaperos.allowUnsignedRelease=true
flutter build appbundle --release -Ppaperos.allowUnsignedRelease=true
```

| Command | Result |
| --- | --- |
| `flutter pub get` | Succeeded |
| `dart format --set-exit-if-changed lib test` | Clean (0 changed) |
| `flutter analyze --no-fatal-infos` | No issues found |
| `flutter test` | 163 tests passed (203.75 s cold run; 95 s final re-run) |
| Unsigned universal release APK | Succeeded in 432.9 s |
| Unsigned split-ABI release APKs | Succeeded in 648.4 s |
| Unsigned release AAB | Succeeded in 90.2 s |
| Debug APK | Succeeded in 212.3 s (debug-signed; not a release artifact) |

The debug build succeeded after a retry with a stable network. It is signed with
the local debug key, uses the `dev.paperos.app.debug` package and the
`1.2.0-debug` version name, and includes `INTERNET` for Flutter development
tooling. It is not release evidence and its size is not comparable to a release
artifact. The release builds compiled the same Dart/Kotlin source with AOT
compilation and R8 enabled.

## Artifact measurements

The release artifacts below are **unsigned analysis artifacts**. They are not
installable, not distributable and not a Play Store release.

| Artifact | Bytes | MiB | SHA-256 |
| --- | ---: | ---: | --- |
| `build/app/outputs/flutter-apk/app-release-unsigned.apk` | 58,274,172 | 55.57 | `ad48a3fa072b1b052e23c9ef49fa28194ff509eeaeda21f5582159c45fb34434` |
| `build/app/outputs/flutter-apk/app-armeabi-v7a-release-unsigned.apk` | 18,730,094 | 17.86 | `7cdba93b9f8d65655930db77289d3605ee907d9f5a3c43ed6dd8a2f569c3af75` |
| `build/app/outputs/flutter-apk/app-arm64-v8a-release-unsigned.apk` | 21,130,514 | 20.15 | `07d38eb1c7ab571c2689c7f7822e815dd6d97852883774b857d833009f0a84f3` |
| `build/app/outputs/flutter-apk/app-x86_64-release-unsigned.apk` | 22,621,974 | 21.57 | `c0c783e0b2f90a9d55abf67b3f69ded2dae1d792292fc88ca912eec0c42172c6` |
| `build/app/outputs/bundle/release/app-release.aab` | 57,002,083 | 54.36 | `845ff866785ab58ebd53291f4b903143aebd9bbd9ab821f67cd2378c714949e3` |

A debug artifact was also built for development and future device installation:

| Artifact | Bytes | MiB | SHA-256 | Signature |
| --- | ---: | ---: | --- | --- |
| `build/app/outputs/flutter-apk/app-debug.apk` | 193,945,651 | 184.96 | `d8269c92a72aada2ea94fa1e09936f8381bdccf8686a59b25e3d80fc32b5cf22` | Debug key, APK Signature Scheme v2 |

The debug APK is package `dev.paperos.app.debug`, version `1.2.0-debug`, and
declares `INTERNET` for Flutter tooling. It is not installable as a production
release, is not signed with an owner key, and its 184.96 MiB size must not be
quoted as a release size.

`apkanalyzer apk download-size` estimated transport-compressed download sizes:

| Artifact | Download-size estimate |
| --- | ---: |
| Universal APK | 26,780,949 bytes (25.54 MiB) |
| `armeabi-v7a` APK | 9,907,364 bytes (9.45 MiB) |
| `arm64-v8a` APK | 10,315,736 bytes (9.84 MiB) |
| `x86_64` APK | 10,494,466 bytes (10.01 MiB) |

These are estimates, not Play delivery measurements.

Signature verification of the unsigned release APKs with `apksigner verify`
reports:

```text
DOES NOT VERIFY
ERROR: Missing META-INF/MANIFEST.MF
```

That is the expected result for an unsigned analysis build. The AAB has no
JAR-signature entries either. The debug APK verifies with the local Android debug
certificate (`CN=Android Debug`), which is not a production key. A
production-signed artifact must be verified with the owner's certificate before
distribution; see `release-process.md`.

## APK composition

The universal APK contains all three Flutter engine ABIs. Native libraries are
stored uncompressed (`android:extractNativeLibs="false"`), which is why the
universal APK is larger than its compressed download estimate.

| Group | Uncompressed bytes | MiB | Notes |
| --- | ---: | ---: | --- |
| `lib/x86_64` | 20,472,872 | 19.52 | Flutter engine, AOT snapshot, JNI helpers |
| `lib/arm64-v8a` | 18,980,512 | 18.10 | Primary phone ABI |
| `lib/armeabi-v7a` | 16,592,800 | 15.82 | Older 32-bit phones |
| `assets/flutter_assets` | 1,987,606 | 1.90 | Bundled Noto Serif faces, shaders, notices |
| `classes.dex` | 1,653,868 | 1.58 | Kotlin/Java code after R8 |
| `res` | 221,127 | 0.21 | Icons and XML resources |
| `META-INF` | 11,547 | 0.01 | Build metadata |
| Other | 483,569 | 0.46 | Manifest, baseline profile, native metadata |

The APK contains no `kernel_blob.bin`: the Dart code is AOT-compiled into
`libapp.so` for each ABI. R8/resource shrinking is enabled for the release
build. The bundle additionally contains debug symbols under `BUNDLE-METADATA`
(about 81.5 MiB uncompressed); Play uses them for symbolication and does not
ship them as app content.

## Release manifest audit

The merged release manifest and the APK manifest were inspected, not just the
hand-written source manifest.

| Check | Result |
| --- | --- |
| Package | `dev.paperos.app` |
| Version | `1.2.0`, code 3 |
| `minSdk` / `targetSdk` / `compileSdk` | 24 / 36 / 36 |
| `INTERNET` permission | Absent |
| Storage permissions (`READ_*`, `WRITE_*`, `MANAGE_EXTERNAL_STORAGE`) | Absent |
| Other permissions | Only `dev.paperos.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, an app-defined `signature` permission added by AndroidX for non-exported dynamic receivers |
| Exported activity | Exactly one: `dev.paperos.app.MainActivity` (launcher, Home role, VIEW PDF/text) |
| Exported receiver | One: `androidx.profileinstaller.ProfileInstallReceiver`, protected by `android.permission.DUMP` |
| Other components | `androidx.startup.InitializationProvider` is not exported |
| `android:allowBackup` | `false` |
| `android:fullBackupContent` | `false` |

The exported profile-installer receiver is standard AndroidX infrastructure and
is guarded by a signature permission held by the system/shell, not by ordinary
apps. It is recorded here instead of being hidden; any additional exported
component would be a release blocker.

## Test and analysis cost

The full automated suite runs on the Flutter test runner with the real SQLite
engine for repository and backup tests. It covered the original 134-test
baseline plus v1.2 backup, annotation-export, display-profile,
settings-envelope, malformed-manifest and text-scaling regressions.

| Check | Result |
| --- | --- |
| Test files | 28 |
| Tests | 163 passed (203.75 s cold run; 95 s final re-run) |
| Analyzer | No issues |
| Formatting | Clean |
| Device/emulator tests | None run |

The suite is a correctness gate, not a performance benchmark. Widget tests use
the Flutter test font and a synthetic frame loop; their duration does not
predict on-device frame time.

## Runtime performance

**Not measured.** No Android device or emulator was attached, so this report
does not claim startup time, frame time, jank, memory use, PDF rasterisation
latency, EPUB pagination latency, SAF transfer throughput or E-Ink refresh
behaviour.

The implementation does include performance-oriented choices that are
observable in code and tests:

- EPUB and text pagination are lazy: only the pages reached are measured.
- The E-Ink profile removes route/sheet/dialog animations, disables fling and
  overscroll decoration, and uses a one-shot clock timer at minute boundaries.
- Backup/restore streams payloads through files instead of holding books in
  memory, with explicit entry/document/byte limits.
- Progress writes are debounced while reading and flushed on close.
- Release builds use R8, resource shrinking and per-ABI AOT snapshots.

These are implementation properties, not measured speedups. A device run is
required before quoting any runtime number.

## Reproducing the measurements

```bash
cd /home/aizen/Data/FlutterProjects/paperos
flutter --version
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
flutter build apk --release -Ppaperos.allowUnsignedRelease=true
flutter build apk --release --split-per-abi -Ppaperos.allowUnsignedRelease=true
flutter build appbundle --release -Ppaperos.allowUnsignedRelease=true

# Flutter writes unsigned APKs under the signed-release names. Rename them
# immediately so an unsigned artifact cannot be mistaken for a release.
mv build/app/outputs/flutter-apk/app-release.apk    build/app/outputs/flutter-apk/app-release-unsigned.apk
for abi in armeabi-v7a arm64-v8a x86_64; do
  mv "build/app/outputs/flutter-apk/app-$abi-release.apk"      "build/app/outputs/flutter-apk/app-$abi-release-unsigned.apk"
done

sha256sum build/app/outputs/flutter-apk/app-release-unsigned.apk
sha256sum build/app/outputs/flutter-apk/app-*-release-unsigned.apk
sha256sum build/app/outputs/bundle/release/app-release.aab

/home/aizen/Android/Sdk/build-tools/37.0.0-rc1/aapt2 \
  dump badging build/app/outputs/flutter-apk/app-release-unsigned.apk
/home/aizen/Android/Sdk/build-tools/37.0.0-rc1/aapt2 \
  dump permissions build/app/outputs/flutter-apk/app-release-unsigned.apk
/home/aizen/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer \
  apk download-size build/app/outputs/flutter-apk/app-release-unsigned.apk
```

The exact build-tools path may differ on another machine; use the newest
installed build-tools.

## Limits of this report

- The release APK and AAB are unsigned analysis artifacts, not a production
  release.
- The debug APK is debug-signed and includes `INTERNET`; it is not release
  evidence.
- No device or emulator was available; all runtime rows remain unverified.
- Build times are from a shared, memory-constrained host and are upper bounds.
- The universal APK is not the Play-delivered size; split/AAB delivery is
  smaller.
- A signed release must be rebuilt and re-audited after owner credentials are
  supplied. Do not reuse these hashes for a distributed artifact.
