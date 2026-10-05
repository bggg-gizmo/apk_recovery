# Building BG Gremlin APK Recovery v1.5.1

BG Gremlin APK Recovery v1.5.1 is built locally. This repository intentionally does not use GitHub Actions.

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

Install the Godot 4.7.2 stable Android export templates in Godot's normal export-template directory.

In Godot Editor Settings, configure the Android SDK path and JDK 17 path for your machine. Machine-specific SDK and Java paths are not committed.

## Compile-check

```bash
godot --headless --editor --path . --quit
```

The command must complete without a GDScript parse or compile error.

## Export unsigned release APK

```bash
godot --headless --path . --export-release Android build/BGGremlinAPKRecovery-v1.5.1-unsigned.apk
```

The Android export preset targets:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

## Align

With Android Build Tools 36.x:

```bash
zipalign -P 16 -f 4 \
  build/BGGremlinAPKRecovery-v1.5.1-unsigned.apk \
  build/BGGremlinAPKRecovery-v1.5.1-aligned-unsigned.apk
```

## Sign

Use the protected private signing key associated with the Android package if in-place update compatibility matters.

```bash
apksigner sign \
  --ks /secure/path/to/keystore \
  --ks-key-alias YOUR_ALIAS \
  --out build/BGGremlinAPKRecovery-v1.5.1.apk \
  build/BGGremlinAPKRecovery-v1.5.1-aligned-unsigned.apk
```

Do not commit production or update-compatible private signing material.

## Validate

```bash
apksigner verify --verbose --print-certs build/BGGremlinAPKRecovery-v1.5.1.apk
zipalign -P 16 -c -v 4 build/BGGremlinAPKRecovery-v1.5.1.apk
unzip -t build/BGGremlinAPKRecovery-v1.5.1.apk
scripts/validate_apk.sh build/BGGremlinAPKRecovery-v1.5.1.apk
```

Confirm the exported Android activity is portrait-only.

## Validate recovery export

Analyze a representative APK and run `Export Full Recovery Project`. Confirm that the SHA-qualified project directory contains:

- `raw_apk/original.apk`
- `raw_apk/tree/`
- `rebuild/dex/`
- `recovered_sources/`
- `framework_payloads/`
- `native/`
- `obfuscation/`
- `binary_evidence/`
- `reports/`
- `inventories/`
- `checksums/`
- `project_manifest.json`

Run `Export Project ZIP`, copy it through Android's save flow, and verify the resulting archive with a ZIP integrity checker.

## Release metadata

The v1.5.1 validation record and SHA-256 values are under `release/v1.5.1/`.
