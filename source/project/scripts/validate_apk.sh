#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s path/to/app.apk\n' "$0" >&2
  exit 64
fi
APK="$1"
[[ -f "$APK" ]] || { printf 'APK not found: %s\n' "$APK" >&2; exit 66; }

need() { command -v "$1" >/dev/null 2>&1 || { printf 'Required tool not found: %s\n' "$1" >&2; exit 69; }; }
need aapt
need apksigner
need zipalign
need unzip
need sha256sum

printf '%s\n' '=== SHA-256 ==='
sha256sum "$APK"
printf '%s\n' '=== ZIP integrity ==='
unzip -t "$APK"
printf '%s\n' '=== APK signature ==='
apksigner verify --verbose --print-certs "$APK"
printf '%s\n' '=== zipalign (4-byte + 16 KiB page-aware) ==='
zipalign -P 16 -c -v 4 "$APK"
printf '%s\n' '=== Package metadata ==='
aapt dump badging "$APK"
printf '%s\n' '=== Manifest providers/category ==='
aapt dump xmltree "$APK" AndroidManifest.xml | grep -E -A4 -B2 'E: provider|A: android:(name|authorities|appCategory|isGame)' || true

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$APK" 'classes*.dex' 'lib/*/*.so' -d "$TMP" || true

if command -v dexdump >/dev/null 2>&1; then
  for dex in "$TMP"/classes*.dex; do
    [[ -f "$dex" ]] || continue
    printf '=== DEX header: %s ===\n' "$(basename "$dex")"
    dexdump -f "$dex" | sed -n '1,28p'
  done
fi

if command -v readelf >/dev/null 2>&1; then
  while IFS= read -r -d '' so; do
    printf '=== ELF LOAD alignment: %s ===\n' "${so#$TMP/}"
    readelf -lW "$so" | awk '/ LOAD /{print}'
  done < <(find "$TMP/lib" -type f -name '*.so' -print0 2>/dev/null || true)
fi
