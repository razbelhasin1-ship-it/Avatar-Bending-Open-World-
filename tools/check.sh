#!/usr/bin/env bash
# Fast static check: imports the project and parses every GDScript file.
# Prints any parse/compile errors. Usage: tools/check.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG=$(mktemp)
"$GODOT" --headless --path . --import 2>&1 | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|servers/audio_server|init_output_device" > "$LOG"
timeout 300 "$GODOT" --headless --path . --script res://tools/check_scripts.gd 2>&1 | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|servers/audio_server|init_output_device" >> "$LOG"
cat "$LOG" | grep -E "ERROR|Error|error|WARNING: .*gd|CHECK" | head -200
if grep -q -E "SCRIPT ERROR|Parse Error|Failed to load|CHECK FAILED" "$LOG"; then
  rm -f "$LOG"; exit 1
fi
rm -f "$LOG"
echo "check: OK"
