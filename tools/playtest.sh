#!/usr/bin/env bash
# Runs a scripted playtest with real rendering (software Vulkan under Xvfb).
# Usage: tools/playtest.sh <scenario> [out_dir] [WxH]
#   scenario: name in tests/playtest/scenarios (without .gd) or a res:// path
#   out_dir:  where screenshots go (default: ./.playtest/<scenario>)
# Env: RENDERER=gl_compatibility to test the Compatibility renderer.
set -u
cd "$(dirname "$0")/.."
SCEN="${1:?scenario name required}"
OUT="${2:-$(pwd)/.playtest/$(basename "$SCEN" .gd)}"
RES="${3:-1280x720}"
GODOT="${GODOT:-godot}"
mkdir -p "$OUT"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
EXTRA=()
[ -n "${RENDERER:-}" ] && EXTRA+=(--rendering-method "$RENDERER")
LOG=$(mktemp)
timeout "${PLAYTEST_TIMEOUT:-900}" xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path . --resolution "$RES" "${EXTRA[@]}" res://tests/playtest/playtest.tscn -- --test "--scenario=$SCEN" "--out=$OUT" 2>&1 \
  | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|servers/audio_server|init_output_device" | tee "$LOG"
CODE=${PIPESTATUS[0]}
if grep -q -E "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG"; then
  echo "== Script errors detected =="
  CODE=1
fi
rm -f "$LOG"
exit $CODE
