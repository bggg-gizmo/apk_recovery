# Architecture

BG Gremlin APK Recovery v1.5.2 is a Godot 4.7.2 Android application with two primary implementation layers.

## UI and orchestration

`main.gd` owns portrait startup, Android document selection, analysis threading, Function Hunt interaction, user-visible project ZIP export, report export, and diagnostics presentation.

The selected Android `content://` APK is staged into app-private storage before ZIP analysis. The source APK remains read-only from the recovery engine's perspective.

The v1.5.2 primary export action is **Export Full Recovery Project ZIP**. It opens Android's native save flow and supplies the selected destination to the recovery ZIP writer. Report export follows the same no-silent-fallback rule.

## Recovery engine

`analyzer.gd` implements the APK/ZIP parser, ZIP64 support, binary Android manifest inspection, DEX parsing and integrity checks, DEX code-item recovery, stack detection, obfuscation heuristics, Function Hunt, extraction, inventories, reports, checksums, and project packaging.

The extraction model is preservation-first:

1. preserve the original APK;
2. extract the complete packaged tree safely;
3. copy canonical rebuild inputs;
4. parse DEX metadata without filtering obfuscated identifiers;
5. separate surviving source/framework/native/obfuscation evidence;
6. emit reports and machine-readable inventories;
7. checksum the recovery workspace;
8. package the workspace into a portable ZIP for the selected Android destination.

## Android storage boundary

The analyzer can build its SHA-qualified project workspace under app-private `user://BGGremlinAPKRecovery/Output` as an internal implementation detail. When the selected final destination is a `content://` document, the ZIP writer stages the archive internally and then streams the bytes to that document.

App-private storage is not treated as a successful user-facing export destination. v1.5.2 removed the previous silent fallback behavior: if the selected report or project-ZIP destination cannot be written, the UI reports an export failure instead of claiming success for an app-private path.

## Android export integration

`addons/bgg_android_manifest_fix/` contains the export plugin that prevents the Android provider-authority collision previously observed in prebuilt-template exports. AndroidX Startup/ProfileInstaller is preserved and receives a distinct provider authority.

## Orientation

Portrait mode is enforced in both project configuration and runtime code. The release process verifies the resulting Android activity orientation in the compiled manifest.

## Trust model

Input APKs are data, not executable workloads. The recovery pipeline does not intentionally run target application code. Path sanitization and parser bounds checks are part of the recovery boundary.
