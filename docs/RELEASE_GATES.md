# Release Gates

These gates define the minimum evidence required before BG Gremlin APK Recovery is described as production-ready.

## Gate 1 — source and release identity

Confirm:

- version name/code are consistent across source, export preset, documentation, and release records;
- package remains `org.backgroundgremlin.apkrecovery`;
- portrait-only settings remain present;
- no private signing material or credentials are committed;
- release documentation matches the actual implementation.

## Gate 2 — Godot source validation

Using Godot 4.7.2 stable:

- clean import completes;
- GDScript parses/compiles without errors;
- the application scene constructs correctly;
- no release feature is replaced by a placeholder or dead control.

## Gate 3 — package and DEX integrity

For the candidate APK verify:

- ZIP integrity;
- package/version metadata;
- expected ABIs;
- portrait activity orientation;
- unique FileProvider and AndroidX InitializationProvider authorities;
- DEX magic/version, declared size, header size, endian tag, SHA-1, Adler-32, and structural bounds.

## Gate 4 — alignment and signing

Verify with Android Build Tools:

- `zipalign -P 16 -c -v 4`;
- `apksigner verify --verbose --print-certs`;
- required APK Signature Schemes for the release.

Record the signer identity actually used. Do not claim update compatibility unless the candidate was signed with the authorized production key or a supported key-rotation arrangement.

## Gate 5 — recovery-engine behavior

On representative and synthetic APKs verify:

- exact original APK preservation;
- complete non-directory APK tree extraction;
- manifest/resources/DEX rebuild copies;
- DEX string/class/method/code-item exports;
- preservation of obfuscated/minified identifiers;
- source/framework/native/obfuscation/binary evidence export;
- reports, inventories, project manifest, and checksums;
- project ZIP integrity;
- Function Hunt coverage across DEX/text/binary paths.

Source presence alone is not sufficient. Exercise the behavior.

## Gate 6 — Android storage boundary

Verify the implementation:

- primary full-project export routes through Android's native save flow;
- report/project export failures surface as failures;
- no user-facing export silently falls back to app-private `user://`;
- internal staging paths are never presented as the final destination.

## Gate 7 — Android user-visible acceptance

Before production promotion, on a physical Android device or representative emulator:

1. confirm the target with `adb devices -l`;
2. install the candidate using the appropriate signing identity;
3. analyze a representative APK;
4. invoke **Export Full Recovery Project ZIP**;
5. confirm the native save picker appears;
6. save to Downloads or Documents;
7. confirm the ZIP is visible in a standard file manager;
8. inspect/extract it and verify the complete SHA-qualified recovery root;
9. test cancel/failure behavior and confirm no false success or silent private-storage fallback.

Physical-device evidence and emulator evidence must be labeled separately.

## Gate 8 — exact-head evidence

All release claims must identify the exact candidate source/artifact state.

A head-changing correction invalidates affected head-sensitive evidence. Rerun those gates before promotion.

## Gate 9 — release records

Update together:

- `README.md`;
- `CHANGELOG.md`;
- `BUILDING.md`;
- `source/README.md`;
- `release/<version>/README.md`;
- release notes;
- validation record;
- SHA-256 records;
- `docs/HANDOFF.md`.

Do not publish a checksum, validation claim, or release pointer for a different artifact than the one actually validated.
