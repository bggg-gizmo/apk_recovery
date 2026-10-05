# Recovery Output Contract

Each analyzed APK is exported beneath:

`BGGremlinAPKRecovery/Output/<apk-name>_<first-12-sha256>/`

The SHA-qualified folder name separates different APK byte streams even when filenames are reused.

## raw_apk

- `raw_apk/original.apk`: exact copy of the analyzed APK.
- `raw_apk/tree/`: all non-directory ZIP entries extracted with sanitized paths.

## rebuild

- `rebuild/AndroidManifest.xml`: compiled manifest exactly as packaged.
- `rebuild/resources/resources.arsc`: compiled resource table exactly as packaged.
- `rebuild/dex/classes*.dex`: every packaged DEX file.
- `rebuild/dex/*.strings.txt`: decoded DEX string tables.
- `rebuild/dex/*.classes.tsv`: class descriptors and surviving source-file names.
- `rebuild/dex/*.methods.tsv`: method IDs, class descriptors, names, and prototype descriptors.
- `rebuild/dex/*.code-items.txt`: reachable encoded methods with exact original Dalvik 16-bit code units and associated metadata.
- `rebuild/REBUILD_GUIDE.txt`: reconstruction guidance generated for the exported project.

Abstract or native methods without a DEX `code_item` are recorded as such; the exporter does not manufacture method bodies.

## recovered_sources

Source-like and text payloads that survived in the APK, including recognized Java, Kotlin, C#, Dart, JavaScript, TypeScript, web, configuration, SQL, map, protocol, and other text formats.

## framework_payloads

Framework-specific rebuild material for supported stacks when present. Native shared libraries remain canonical under `native/` and the raw tree rather than being unnecessarily duplicated.

## native

Exact `.so` libraries grouped by ABI, plus printable string evidence extracted from native binaries.

## obfuscation

Surviving ProGuard/R8 mappings, source maps, symbols, PDB/MDB/debug material, and other artifacts that can help recover naming or source relationships.

## binary_evidence

Printable evidence recovered from additional binary blobs that are not classified as canonical native libraries.

## reports

- `analysis.txt`
- `analysis.html`
- `analysis.json`

## inventories

Machine-readable or tabular inventories for APK structure, recovery artifacts, DEX contents, source-like files, framework payloads, native libraries, and obfuscation/debug artifacts.

## checksums

The source APK SHA-256 and output-file SHA-256 inventory.

## project_manifest.json

Machine-readable recovery-project identity, source APK information, extraction counts, and project metadata.

## Portable project ZIP

`Export Project ZIP` packages the same recovery workspace. On Android, external destinations are selected through the system save flow; `content://` destinations are handled through internal staging and copy-out.
