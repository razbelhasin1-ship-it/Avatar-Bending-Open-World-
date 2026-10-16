#!/usr/bin/env bash
# Exports the Android build (arm64-v8a, Mobile renderer, landscape, immersive) as an APK
# into build/android/. Debug by default (signed with a debug keystore, installable with
# `adb install` or by opening the file on the phone); `release` needs your own keystore:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD (Godot's own env vars).
#
# Usage: tools/export/export_android.sh [debug|release]
#
# Requirements (no Gradle / Android Studio needed: Godot signs its prebuilt APK template):
#   * Godot 4.7.2 export templates (android_debug.apk / android_release.apk)
#   * a JDK 17+ (JAVA_HOME, or `java` on PATH)
#   * Android SDK build-tools with apksigner (ANDROID_HOME / ANDROID_SDK_ROOT).
#     Without an SDK, on Debian/Ubuntu `sudo apt install apksigner zipalign adb` is enough:
#     this script then assembles a minimal SDK layout around those tools.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
MODE="${1:-debug}"
case "$MODE" in debug|release) ;; *) echo "mode must be debug or release" >&2; exit 2 ;; esac
OUT=build/android
mkdir -p "$OUT"
touch build/.gdignore   # keep Godot from importing exported files back into the project

# --- Java -------------------------------------------------------------------------------------
if [ -z "${JAVA_HOME:-}" ]; then
  if command -v javac >/dev/null; then
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
    export JAVA_HOME
  else
    echo "export_android: no JDK found (set JAVA_HOME)" >&2; exit 1
  fi
fi

# --- SDK ----------------------------------------------------------------------------------------
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ] || ! ls "$SDK"/build-tools/*/apksigner >/dev/null 2>&1; then
  if command -v apksigner >/dev/null && command -v zipalign >/dev/null; then
    SDK="${XDG_CACHE_HOME:-$HOME/.cache}/four-nations-android-sdk"
    mkdir -p "$SDK/build-tools/34.0.0" "$SDK/platform-tools" "$SDK/cmdline-tools/latest/bin" "$SDK/platforms"
    ln -sf "$(command -v apksigner)" "$SDK/build-tools/34.0.0/apksigner"
    ln -sf "$(command -v zipalign)" "$SDK/build-tools/34.0.0/zipalign"
    if command -v adb >/dev/null; then ln -sf "$(command -v adb)" "$SDK/platform-tools/adb"; fi
    echo "export_android: using a minimal SDK around the system apksigner at $SDK"
  else
    echo "export_android: no Android SDK build-tools found (set ANDROID_HOME, or apt install apksigner zipalign)" >&2
    exit 1
  fi
fi
export ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK"

# --- Debug keystore ---------------------------------------------------------------------------------
if [ "$MODE" = debug ] && [ -z "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}" ]; then
  KS="${XDG_CACHE_HOME:-$HOME/.cache}/four-nations-debug.keystore"
  if [ ! -f "$KS" ]; then
    "$JAVA_HOME/bin/keytool" -genkeypair -keyalg RSA -keysize 2048 -validity 10000 -alias androiddebugkey \
      -keypass android -storepass android -keystore "$KS" -dname "CN=Android Debug,O=Android,C=US" -deststoretype pkcs12 >/dev/null
  fi
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KS" GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
fi

# Godot reads the SDK / JDK paths from its editor settings; seed them for headless runs.
SETTINGS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$SETTINGS_DIR"
ES="$SETTINGS_DIR/editor_settings-4.7.tres"
if [ ! -f "$ES" ]; then
  printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' > "$ES"
fi
python3 - "$ES" "$SDK" "$JAVA_HOME" <<'PY'
import re, sys
path, sdk, java = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
for key, val in (("export/android/android_sdk_path", sdk), ("export/android/java_sdk_path", java)):
    line = '%s = "%s"' % (key, val)
    if re.search(r'^%s = .*$' % re.escape(key), text, re.M):
        text = re.sub(r'^%s = .*$' % re.escape(key), line, text, flags=re.M)
    else:
        text = text.rstrip("\n") + "\n" + line + "\n"
open(path, "w").write(text)
PY

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
APK="$OUT/avatar-four-nations-$MODE.apk"
rm -f "$APK"
"$GODOT" --headless --path . "--export-$MODE" "Android" "$APK" 2>&1 \
  | grep -v -E "^ALSA|audio_driver_alsa|All audio drivers failed|servers/audio_server|init_output_device|savepack|Storing File" || true
if [ ! -s "$APK" ]; then
  echo "export_android: export failed (see the log above)" >&2
  exit 1
fi
ls -la "$APK"
if command -v apksigner >/dev/null; then apksigner verify --print-certs "$APK" | head -3 || true; fi
echo "export_android: OK -> $APK"
