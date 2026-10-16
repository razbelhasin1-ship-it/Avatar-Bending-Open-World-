#!/usr/bin/env bash
# Exports the Web build (Compatibility renderer, no threads: runs in every desktop and
# mobile browser without cross-origin isolation) to build/web/.
# Usage: tools/export/export_web.sh [release|debug]   (default: release)
# Then:  python3 tools/export/serve_web.py            (http://localhost:8060)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
MODE="${1:-release}"
case "$MODE" in release|debug) ;; *) echo "mode must be release or debug" >&2; exit 2 ;; esac
OUT=build/web
rm -rf "$OUT"
mkdir -p "$OUT"
# Godot must not import the exported files (index.png ...) back into the project.
touch build/.gdignore
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
LOG=$(mktemp)
"$GODOT" --headless --path . "--export-$MODE" "Web" "$OUT/index.html" 2>&1 | tee "$LOG" | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|servers/audio_server|init_output_device" || true
if [ ! -s "$OUT/index.pck" ] || [ ! -s "$OUT/index.wasm" ]; then
  echo "export_web: export failed (see log above)" >&2
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"
# Pre-compressed copies for servers that can send them (GitHub Pages compresses on its own).
if command -v gzip >/dev/null; then
  for f in "$OUT"/index.wasm "$OUT"/index.pck "$OUT"/index.js; do
    gzip -9 -k -f "$f"
  done
fi
du -sh "$OUT"/* | sort -h
echo "export_web: OK -> $OUT/index.html"
