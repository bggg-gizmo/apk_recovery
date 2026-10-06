# v1.5.2 Source

The complete public Godot project is in `source/project/`.

Toolchain:

- Godot 4.7.2 stable
- matching Godot 4.7.2 Android export templates
- JDK 17
- Android SDK Platform 36
- Android Build Tools 36.x
- Android Platform Tools

The project contains the portrait recovery UI, APK/ZIP/DEX analyzer, rebuild-oriented exporter, Android manifest export fix, local build/validation scripts, project configuration, and application artwork.

v1.5.2 changes the Android user-facing storage boundary: **Export Full Recovery Project ZIP** opens the native save flow and writes the complete SHA-qualified recovery workspace to the destination selected by the user. App-private `user://` storage is internal staging only and is not a successful user-facing export destination.

Private production/update signing keys, passwords, tokens, machine-specific SDK paths, internal development history, and private build artifacts are not part of this public source tree.

Static/headless validation does not substitute for Android save-picker and file-manager acceptance. The release gates explicitly separate source/package checks, emulator/device behavior, and physical-device acceptance.

See the repository-level [BUILDING.md](../BUILDING.md), [CHANGELOG.md](../CHANGELOG.md), [AGENTS.md](../AGENTS.md), [Release Gates](../docs/RELEASE_GATES.md), [Current Handoff](../docs/HANDOFF.md), and [SECURITY.md](../SECURITY.md).
