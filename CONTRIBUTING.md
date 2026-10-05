# Contributing

BG Gremlin APK Recovery is maintained by Background Gremlin Group.

Contributions should preserve the project's core recovery guarantees:

1. Never modify the selected source APK in place.
2. Preserve exact packaged bytes before attempting higher-level reconstruction.
3. Do not discard code merely because identifiers are obfuscated or minified.
4. Keep recovery output deterministic and separated by APK/project.
5. Keep the Android application portrait-only unless the project requirement is explicitly changed.
6. Avoid placeholder exporters, dead controls, invented source, or silent parser fallbacks.
7. Keep private signing material out of the active source tree.
8. Add validation coverage for parser, export, or packaging changes.

## Development workflow

This repository uses one active branch, `main`, and intentionally does not use GitHub Actions. Run compile, export, signature, alignment, ZIP, DEX, and recovery-export validation locally before committing a release change.

## Change documentation

User-visible recovery changes belong in `CHANGELOG.md`. Release validation evidence belongs under `release/<version>/`. Structural changes to exported recovery projects should also update `docs/RECOVERY_OUTPUT.md`.
