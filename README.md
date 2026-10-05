# BG Gremlin APK Recovery

**Background Gremlin Group — don't do evil**

BG Gremlin APK Recovery is an offline Android APK disaster-recovery and reconstruction utility. Its job is to preserve and extract as much rebuild-relevant material as an APK actually contains before any repair, patching, or repackaging work begins.

The current development release is **v1.5.1**, built with **Godot 4.7.2 stable** for Android. The application is **portrait-only** and operates locally on the selected APK.

## What it recovers

BG Gremlin APK Recovery preserves exact packaged bytes first and builds structured recovery material around them. The recovery project can include:

- the untouched source APK;
- the complete non-directory APK ZIP tree;
- compiled `AndroidManifest.xml` and `resources.arsc`;
- every `classes*.dex` file;
- complete DEX string tables;
- DEX class descriptors and surviving source-file names;
- DEX method IDs, class descriptors, names, and prototype descriptors;
- encoded method metadata and exact original 16-bit Dalvik code units for reachable `code_item` entries;
- obfuscated class and member identifiers exactly as they exist in the APK;
- surviving Java, Kotlin, C#, Dart, JavaScript, TypeScript, web, configuration, SQL, map, protocol, and other text/source-like files;
- Flutter, React Native/Hermes, Unity, Xamarin/.NET, Cordova/Capacitor, and Godot payloads when present;
- native shared libraries organized by ABI;
- printable evidence recovered from native and other binary payloads;
- ProGuard/R8 mappings, source maps, symbols, PDB/MDB/debug material, and other name-recovery artifacts when present;
- human-readable and machine-readable analysis reports, inventories, checksums, and reconstruction guidance.

Obfuscation is not treated as a reason to discard code. If identifiers were minified or renamed, the application keeps those identifiers and the underlying packaged bytecode evidence. It does not invent pre-obfuscation names that are not recoverable from the APK.

## Per-project export layout

Every analyzed APK receives its own deterministic workspace:

```text
BGGremlinAPKRecovery/
└── Output/
    └── <apk-name>_<first-12-sha256>/
        ├── raw_apk/
        │   ├── original.apk
        │   └── tree/
        ├── rebuild/
        │   ├── AndroidManifest.xml
        │   ├── resources/
        │   ├── dex/
        │   └── REBUILD_GUIDE.txt
        ├── recovered_sources/
        ├── framework_payloads/
        ├── native/
        ├── obfuscation/
        ├── binary_evidence/
        ├── reports/
        ├── inventories/
        ├── checksums/
        └── project_manifest.json
```

`Export Full Recovery Project` creates the working directory. `Export Project ZIP` packages the same recovery workspace into a portable archive using Android's save flow.

See [docs/RECOVERY_OUTPUT.md](docs/RECOVERY_OUTPUT.md) for the full export contract.

## Stack detection and Function Hunt

The analyzer recognizes:

- native Android / Java / Kotlin;
- Jetpack Compose;
- Godot Engine;
- Flutter;
- React Native / Hermes;
- Unity Mono / IL2CPP;
- Xamarin / .NET MAUI;
- Cordova / Ionic / Capacitor;
- native-heavy APKs.

Function Hunt searches DEX class descriptors, method names, DEX strings, filenames, source/text assets, case-insensitive ASCII remnants, and UTF-16LE remnants in binary payloads.

## Diagnostics

The diagnostics layer checks DEX magic/version, declared size, header size, endian tag, SHA-1 header signature, Adler-32 checksum, structural table bounds, duplicate provider authorities, APK signing-block markers, JAR/v1 signature metadata, stored ZIP-entry alignment, native ABI inventory, and ZIP64 metadata.

Static signing-marker inspection is not a replacement for Android Build Tools verification. Release validation uses `apksigner`, `zipalign`, ZIP integrity tests, and APK metadata inspection.

## Portrait-only Android application

v1.5.1 is intentionally portrait-only.

- Godot project setting: `display/window/handheld/orientation=1`
- Runtime request: `DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)`
- Exported Android activity: `android:screenOrientation="portrait"`

## Repository layout

The active repository tracks the v1.5.1 project documentation and source package. The repository state that existed before this migration is retained under `old_builds/` for auditability and historical reference.

```text
.
├── README.md
├── BUILDING.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── docs/
├── release/
│   └── v1.5.1/
├── source/
└── old_builds/
```

There are **no active GitHub Actions workflows**. Builds are performed locally with the documented Godot/Android toolchain so repository activity does not consume Actions credits.

## Build requirements

- Godot 4.7.2 stable
- matching Godot 4.7.2 Android export templates
- JDK 17
- Android SDK Platform 36
- Android Build Tools 36.x
- Android Platform Tools

Package name: `org.backgroundgremlin.apkrecovery`

Version: `1.5.1`

Android version code: `151`

See [BUILDING.md](BUILDING.md) for the complete local build and validation procedure.

## Release validation

The v1.5.1 build record is stored under [release/v1.5.1](release/v1.5.1/). The signed build validated APK Signature Scheme v2/v3, 16 KiB-aware alignment, ZIP integrity, portrait enforcement, unique provider authorities, three packaged ABIs, DEX header integrity, and the full recovery/export integration path.

The signed v1.5.1 APK SHA-256 is:

```text
47ba6fb9e6b220a0b0be7945d2eaa9282bc5da38a7349f6f4e2202e623d20b3f
```

## Recovery limits

APK recovery is constrained by what was shipped. Deleted comments, Git history, source-only files, and pre-obfuscation identifiers that are absent from the package cannot be recreated from nonexistent bytes. BG Gremlin APK Recovery therefore prioritizes exact preservation of packaged DEX/native/framework content and explicit metadata over fabricated source.

## Security and signing

Private signing keys do not belong in the active source tree. Use the protected key that owns your Android package when update-signature continuity matters. See [SECURITY.md](SECURITY.md).

## Project stewardship

BG Gremlin APK Recovery is maintained by **Background Gremlin Group** for legitimate software recovery, interoperability, reverse engineering, security research, and disaster-recovery work where the operator is authorized to analyze the application.

**Background Gremlin Group — don't do evil.**
