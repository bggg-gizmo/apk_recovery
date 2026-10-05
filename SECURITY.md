# Security Policy

BG Gremlin APK Recovery processes APKs locally and is designed to avoid modifying the selected source APK in place.

## Public repository hygiene

This public repository intentionally excludes:

- Android signing keystores and private keys;
- signing passwords and aliases tied to private keys;
- API keys, access tokens, session credentials, and service secrets;
- private development history;
- internal-only build artifacts;
- machine-specific SDK and Java paths.

If a credential is ever committed accidentally, removing it from the latest tree is not sufficient. Revoke or rotate the credential and purge it from repository history before treating the repository as safe for public use.

## Signing keys

Production, update-compatible, or otherwise sensitive Android signing keys must never be committed.

For an Android package that must update an existing installation, sign the aligned unsigned APK with the protected private key that owns that package identity.

## Untrusted APK input

Treat analyzed APKs as untrusted input. Recovery logic should:

- avoid executing packaged code;
- sanitize extracted paths;
- prevent ZIP path traversal;
- bound parser offsets and lengths before reading;
- preserve original bytes when parsing is incomplete;
- report malformed structures instead of fabricating replacements.

## Reporting security issues

When reporting a security defect, include the affected version, relevant parser/export path, reproducible input characteristics, and expected versus observed behavior. Do not include private signing keys, credentials, or unrelated sensitive application data in a report.
