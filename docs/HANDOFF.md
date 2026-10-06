# Current Handoff

## Current release line

BG Gremlin APK Recovery v1.5.2 is the current public source/release line.

Package: `org.backgroundgremlin.apkrecovery`  
Version code: `152`  
Engine: Godot 4.7.2 stable  
Android UI: portrait-only

## Corrective context

v1.5.1 exposed a production Android storage-boundary defect: the primary full-project export could complete into Godot app-private `user://` storage, which is not a normal user-visible Android Files/Downloads destination.

v1.5.2 corrects the user-facing boundary:

- the primary action is **Export Full Recovery Project ZIP**;
- Android's native save flow selects the final destination;
- the complete SHA-qualified recovery project is written as a portable ZIP;
- report/project export failures do not silently redirect into app-private storage;
- `user://` remains internal staging only.

## Validation already recorded

The v1.5.2 release record documents successful static/package checks, including:

- Godot source/import validation;
- portrait configuration;
- package/version checks;
- unique provider authorities;
- ZIP integrity;
- 16 KiB-capable alignment;
- APK Signature Scheme verification;
- recovery-export implementation checks.

See `release/v1.5.2/BGGremlinAPKRecovery-v1.5.2-VALIDATION.txt`.

## Evidence boundary

No physical Android target was attached during the recorded v1.5.2 validation run.

Therefore the repository does **not** claim that physical-device user-visible export acceptance passed.

Static/package success does not substitute for:

- native save-picker interaction;
- Downloads/Documents visibility;
- standard file-manager access;
- cancel/failure user experience;
- physical-device behavior.

## Signing boundary

The protected production signing private key was not available in the recorded v1.5.2 validation environment.

The locally signed APK is not claimed to be update-compatible with an installed production build. The aligned unsigned candidate must be signed with the authorized production key when update compatibility is required.

## Next safe action

Run Gate 7 from `docs/RELEASE_GATES.md` on a physical Android device or representative emulator, preserving the exact candidate identity used for the test.

If that test exposes any code or packaging defect:

1. correct the defect;
2. treat the changed head/artifact as a new candidate;
3. rerun every affected head-sensitive gate;
4. update this handoff and the release validation record.

Do not promote physical-device acceptance by inference from existing static evidence.
