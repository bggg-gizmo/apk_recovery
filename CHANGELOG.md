# Changelog

## 1.5.2 — 2026-10-05

- Fixed the production Android export defect where `Export Full Recovery Project` wrote only to Godot `user://` app-private storage.
- The primary recovery export now opens Android's native save flow and produces the complete recovery project as a user-visible ZIP at the destination selected by the user.
- Removed silent fallback behavior that could report success after redirecting report or project ZIP output into app-private storage. Export failures are surfaced as failures.
- App-private storage remains only as temporary working/staging space while assembling the recovery project; the user-facing result is copied to the selected Android document destination.
- Increased Android `versionCode` to `152` and release name to `1.5.2`.
- Restored a repository-contained application icon asset so the public Godot source checkout is self-contained.

## 1.5.1 — 2026-10-04

- Reworked the Android application around rebuild-oriented recovery rather than report-only analysis.
- Added `Export Full Recovery Project` with a dedicated `BGGremlinAPKRecovery/Output/` root and SHA-qualified per-APK subfolders.
- Added exact preservation of the selected APK as `raw_apk/original.apk`.
- Added complete non-directory APK ZIP payload extraction with traversal-safe output paths.
- Added rebuild-oriented copies of `AndroidManifest.xml`, `resources.arsc`, and every `classes*.dex`.
- Added complete DEX string-table export.
- Added DEX class-table export with surviving source-file names.
- Added DEX method-table export with class descriptors and prototype descriptors.
- Added encoded-method traversal through DEX `class_data_item` structures.
- Added exact Dalvik `code_item` export with access flags, offsets, register/input/output/try counts, debug-info offsets, instruction counts, and original 16-bit code units.
- Preserved obfuscated class/member identifiers exactly rather than filtering short or minified names.
- Added recovery of source-like and text files into `recovered_sources/`.
- Added framework payload collection for Flutter, React Native/Hermes, Unity, Xamarin/.NET, Cordova/Capacitor, and Godot.
- Added ABI-separated native-library export and native printable string evidence.
- Added obfuscation/debug artifact export for mappings, source maps, symbols, PDB, and MDB material.
- Added binary string-evidence export for additional binary payloads.
- Added TXT, HTML, JSON, recovery-artifact CSV, APK-structure CSV, and DEX-inventory CSV outputs.
- Added `project_manifest.json` and SHA-256 output inventory.
- Changed Recovery ZIP into a complete project ZIP mirroring the working recovery directory.
- Locked the Android UI to portrait through both project configuration and runtime orientation request.
- Preserved the Android manifest provider-authority repair that keeps AndroidX Startup/ProfileInstaller while assigning a unique provider authority.
- Retained ZIP64 parsing, DEX integrity validation, APK signing-marker diagnostics, ABI inventory, ZIP alignment diagnostics, `content://` staging, and Function Hunt.
- Increased Android `versionCode` to `151` and release name to `1.5.1`.

## 1.5.0

Last known-good baseline before the rebuild-oriented v1.5.1 extraction expansion.

## 1.0.2

Added DEX integrity diagnostics and repaired the duplicated Android provider authority in Godot prebuilt-template exports.