# BG Gremlin APK Recovery

**Background Gremlin Group — don't do evil**

BG Gremlin APK Recovery is an offline Android APK disaster-recovery and reconstruction toolkit. It is designed to preserve a target APK exactly, identify where application logic survives, and export as much rebuild-relevant material as the package actually contains.

The current public release is **v1.5.1**, built with **Godot 4.7.2 stable** for Android. The application is **portrait-only** and performs analysis locally on the selected APK.

## Recovery goals

The project is intentionally preservation-first. It keeps the original packaged bytes and builds structured recovery material around them rather than replacing unknown data with guesses.

A recovery project can contain:

- the untouched source APK;
- the complete non-directory APK ZIP tree;
- compiled `AndroidManifest.xml` and `resources.arsc`;
- every `classes*.dex` file;
- complete DEX string tables;
- DEX class descriptors and surviving source-file names;
- DEX method IDs, class descriptors, names, and prototype descriptors;
- encoded-method metadata and exact original 16-bit Dalvik code units for reachable `code_item` entries;
- obfuscated class and member identifiers exactly as present in the APK;
- surviving Java, Kotlin, C#, Dart, JavaScript, TypeScript, web, configuration, SQL, source-map, protocol, and other source/text artifacts;
- Flutter, React Native/Hermes, Unity, Xamarin/.NET, Cordova/Capacitor, and Godot payloads when present;
- native shared libraries organized by ABI;
- printable evidence recovered from native and other binary payloads;
- ProGuard/R8 mappings, source maps, symbols, PDB/MDB/debug material, and other name-recovery artifacts when present;
- human-readable and machine-readable reports, inventories, checksums, and reconstruction guidance.

Obfuscation is not treated as a reason to discard code. If identifiers were renamed or minified, BG Gremlin APK Recovery preserves those identifiers and the underlying bytecode evidence. It does not invent pre-obfuscation names that are absent from the APK.

## Per-project export layout

Each analyzed APK receives a deterministic project workspace:

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

`Export Full Recovery Project` creates the working directory. `Export Project ZIP` packages the same workspace into a portable archive using Android's system save flow.

See [docs/RECOVERY_OUTPUT.md](docs/RECOVERY_OUTPUT.md) for the export contract.

## Stack detection

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

The diagnostics layer checks DEX magic/version, declared file size, header size, endian tag, SHA-1 header signature, Adler-32 checksum, structural table bounds, duplicate provider authorities, APK signing-block markers, JAR/v1 signature metadata, ZIP-entry alignment, native ABI inventory, and ZIP64 metadata.

Release validation additionally uses Android Build Tools such as `apksigner` and `zipalign`.

## Portrait-only Android application

v1.5.1 is intentionally portrait-only.

- Godot project setting: `display/window/handheld/orientation=1`
- runtime request: `DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)`
- Android activity export: portrait orientation

## Repository layout

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
└── source/
    └── project/
```

This public repository contains the sanitized public source and documentation only. Private development history, historical signing material, and internal-only artifacts are not mirrored here.

There are **no GitHub Actions workflows**. Builds are performed locally so repository activity does not consume Actions credits.

## Build requirements

- Godot 4.7.2 stable
- matching Godot 4.7.2 Android export templates
- JDK 17
- Android SDK Platform 36
- Android Build Tools 36.x
- Android Platform Tools

Package: `org.backgroundgremlin.apkrecovery`

Version: `1.5.1`

Android version code: `151`

See [BUILDING.md](BUILDING.md) for the local build and validation procedure.

## Recovery limits

APK recovery is constrained by what was actually shipped. Deleted comments, Git history, source-only files, and pre-obfuscation identifiers that are absent from the package cannot be recreated from nonexistent bytes. BG Gremlin APK Recovery therefore prioritizes exact preservation of packaged DEX/native/framework content and explicit metadata over fabricated source.

## Security and signing

Private signing keys, passwords, tokens, credentials, and internal development history are intentionally excluded from this public repository. Use the protected signing key that owns your Android package when update-signature continuity matters.

See [SECURITY.md](SECURITY.md).

## Project stewardship

BG Gremlin APK Recovery is maintained by **Background Gremlin Group** for legitimate software recovery, interoperability, reverse engineering, security research, and disaster-recovery work where the operator is authorized to analyze the application.

**Background Gremlin Group — don't do evil.**
