#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
OUT_DIR="${OUT_DIR:-build}"
OUT_APK="${OUT_APK:-$OUT_DIR/BGGremlinAPKRecovery-v1.5.1-unsigned.apk}"

mkdir -p "$OUT_DIR"

"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --export-release Android "$OUT_APK"

printf 'Unsigned APK: %s\n' "$OUT_APK"
sha256sum "$OUT_APK" 2>/dev/null || shasum -a 256 "$OUT_APK"
