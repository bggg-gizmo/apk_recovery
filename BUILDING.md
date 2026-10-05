# Building BG Gremlin APK Recovery v1.5.2

BG Gremlin APK Recovery v1.5.2 is built locally. This repository intentionally does not use GitHub Actions.

## Required toolchain

- Godot 4.7.2 stable
- matching Godot 4.7.2 Android export templates
- JDK 17
- Android SDK Platform 36
- Android Build Tools 36.x
- Android Platform Tools

## Source tree

The complete Godot project is under:

```text
source/project/
```

Start from the repository root:

```bash
cd source/project
```

## Configure Godot

Install the Godot 4.7.2 stable Android export templates in Godot's normal export-template directory. Configure the Android SDK and JDK 17 paths in Godot Editor Settings for the build machine. Machine-specific paths and signing material are not committed.

## Compile-check

```bash
godot --headless --editor --path . --quit
```

The command must complete without a GDScript parse or compile error.

## Export unsigned release APK

```bash
godot --headless --path . --export-release Android build/BGGremlinAPKRecovery-v1.5.2-unsigned.apk
```

The Android export preset targets:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

## Align

With Android Build Tools 36.x:

```bash
zipalign -P 16 -f 4 \
  build/BGGremlinAPKRecovery-v1.5.2-unsigned.apk \
  build/BGGremlinAPKRecovery-v1.5.2-aligned-unsigned.apk
```

## Sign

Sign the aligned APK with the protected production signing key associated with `org.backgroundgremlin.apkrecovery` when update compatibility with installed production builds is required. Production signing material must never be committed to this repository.

## Static validation

Run all of the following against the final signed APK:

```bash
apksigner verify --verbose --print-certs build/BGGremlinAPKRecovery-v1.5.2.apk
zipalign -P 16 -c -v 4 build/BGGremlinAPKRecovery-v1.5.2.apk
unzip -t build/BGGremlinAPKRecovery-v1.5.2.apk
scripts/validate_apk.sh build/BGGremlinAPKRecovery-v1.5.2.apk
```

Confirm the exported Android activity is portrait-only, the three expected ABIs are present, and the FileProvider and AndroidX InitializationProvider authorities are unique.

## Android user-visible export acceptance

A production release is not accepted until this sequence is completed on a physical Android device or a representative Android emulator:

1. Run `adb devices -l` and confirm a test target is attached.
2. Install the candidate build using the appropriate signing identity for the test scenario.
3. Analyze a representative APK.
4. Tap **Export Full Recovery Project ZIP**.
5. Confirm Android's native save picker opens.
6. Choose a normal user-visible destination such as Downloads or Documents.
7. Confirm the resulting ZIP is visible from a standard file manager at that selected destination.
8. Extract or inspect the ZIP and verify the SHA-qualified project root contains `raw_apk/original.apk`, `raw_apk/tree/`, `rebuild/dex/`, `recovered_sources/`, `framework_payloads/`, `native/`, `obfuscation/`, `binary_evidence/`, `reports/`, `inventories/`, `checksums/`, and `project_manifest.json`.
9. Test a failed or cancelled export and confirm the application does not claim success and does not silently redirect the user-facing result into app-private `user://` storage.

The app may use app-private storage internally while constructing a recovery workspace or staging bytes for a `content://` destination. That internal staging path is not the final user-visible export.

## Release evidence and exact-head rule

A validation result applies only to the exact source/artifact state that produced it. If release-relevant code, export, packaging, or storage behavior changes after a gate ran, rerun the affected head-sensitive gates before promotion.

Keep these evidence classes separate:

- source/import/compile evidence;
- package, DEX, ZIP, alignment, and signature evidence;
- emulator or instrumentation evidence;
- physical-device user-visible export evidence.

A lower evidence class never implies a higher one. A successful ZIP build or `content://` code path does not prove that the saved artifact is visible and usable from an Android file manager.

## Release metadata

The v1.5.2 validation record and SHA-256 values are under `release/v1.5.2/`. The record distinguishes static validation from physical-device export validation.

The complete release contract is in [docs/RELEASE_GATES.md](docs/RELEASE_GATES.md). Current operational state is in [docs/HANDOFF.md](docs/HANDOFF.md).
