# Engineering Agent Contract

This repository is a recovery tool, so preservation, evidence quality, and truthful release claims are part of the product contract.

## Source truth

Use this priority order when sources disagree:

1. explicit current user requirements and physical-device observations;
2. current release contract and release-gate documentation;
3. current source and tests;
4. current release evidence;
5. historical release notes and archived material.

Do not let stale branch notes or an older release record silently override current product behavior.

## Preserve the product

Do not remove, collapse, or replace working functionality merely to make a fix, refactor, or release gate easier.

Preserve unless explicitly changed:

- read-only APK handling;
- exact original APK preservation;
- complete packaged-tree extraction;
- all DEX files and obfuscated identifiers;
- DEX strings/classes/methods/code-item evidence;
- Function Hunt coverage;
- framework/native/obfuscation evidence;
- machine-readable inventories and checksums;
- portrait-only Android behavior;
- unique Android provider authorities;
- user-visible Android project export;
- failure reporting without silent fallback.

A simpler implementation is not acceptable when it weakens evidence or export completeness.

## Android export boundary

App-private `user://` storage may be used as internal staging. It is not a successful user-facing destination.

A release that claims user-visible export must prove the Android native save flow works and that the resulting artifact is visible and usable from an ordinary Android file manager.

Never convert internal staging success into user-facing export success.

## Evidence classes

Keep these distinct:

- source/static evidence;
- build/package evidence;
- emulator/instrumentation evidence;
- physical-device evidence.

A lower class never implies a higher one. Source presence is not behavioral acceptance. A generated ZIP is not proof that Android exposed it to the user.

## Exact-head validation

Validation belongs to the exact source/artifact state that produced it.

If a release-relevant change lands after a gate ran, rerun the affected head-sensitive gates. Do not describe an older artifact or an older commit as proof for a newer head.

## Signing

Android update compatibility depends on signing continuity.

Do not commit production/update signing keys, passwords, aliases, or private key material. A locally signed APK must not be described as update-compatible unless the authorized production signing identity was actually used or an Android-supported rotation arrangement applies.

## Failure handling

Preserve material failures as engineering evidence when they change the release contract or expose a recurring risk. Record:

- symptom;
- root cause;
- affected release/head;
- correction;
- prevention rule;
- validation boundary.

Do not rewrite a failed release as if it had passed.

## Repository hygiene

This public repository must remain sanitized.

Do not commit:

- private signing material;
- credentials or tokens;
- machine-local SDK paths;
- private development history that is intentionally excluded;
- unrelated sensitive artifacts.

The repository intentionally does not use GitHub Actions. Do not add workflows unless the repository owner explicitly changes that policy.

## Handoff

Before ending substantial release or corrective work, update `docs/HANDOFF.md` with:

- current release/head;
- completed work;
- validation actually run;
- validation not run;
- blockers;
- exact next safe action;
- any signing or device boundary that remains unresolved.

The handoff must be usable without the conversation that produced it.
