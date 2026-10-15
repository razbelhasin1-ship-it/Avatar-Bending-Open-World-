#!/usr/bin/env bash
# Runs automated tests headless. Usage: tools/test.sh [filter]
# Exit code is non-zero if any test fails or the engine reports script errors.
set -u
cd "$(dirname "$0")/.."
FILTER="${1:-}"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
LOG=$(mktemp)
ARGS=(--test)
[ -n "$FILTER" ] && ARGS+=("--filter=$FILTER")
timeout "${TEST_TIMEOUT:-600}" "$GODOT" --headless --path . res://tests/run_tests.tscn -- "${ARGS[@]}" 2>&1 | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|servers/audio_server|init_output_device" | tee "$LOG"
CODE=${PIPESTATUS[0]}
if grep -q -E "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG"; then
  echo "== Script errors detected =="
  CODE=1
fi
rm -f "$LOG"
exit $CODE
