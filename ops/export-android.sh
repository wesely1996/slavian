#!/usr/bin/env bash
# Exports a debug APK of the Godot client.
#
#   ops/export-android.sh build/slavian-debug.apk
#
# Push notifications need client/google-services.json and run
# ops/ci/setup-firebase-android.sh first (done here), which needs
# GODOT_VERSION set to the installed Godot's version, e.g. 4.5.1.
#
# Needs `godot` on the PATH (or $GODOT), Godot's Android export templates, an
# Android SDK and JDK 17 (from Godot's editor settings, or ANDROID_HOME and
# JAVA_HOME when the editor settings are fresh, as on CI).
#
# Signing uses GODOT_ANDROID_KEYSTORE_DEBUG_PATH / _USER / _PASSWORD. If they
# are unset, a debug keystore is generated in build/ and reused afterwards.
# VERSION_CODE and VERSION_NAME, when set, override the export preset for
# this export only.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=$(realpath -m "${1:?usage: $0 <output.apk>}")
godot=${GODOT:-godot}
preset="$root/client/export_presets.cfg"

if [[ -z "${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-}" ]]; then
  keystore="$root/build/debug.keystore"
  if [[ ! -f "$keystore" ]]; then
    echo "No keystore given; generating $keystore"
    mkdir -p "$(dirname "$keystore")"
    keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
      -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=Android Debug,O=Android,C=US" > /dev/null
  fi
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$keystore"
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
fi

if [[ -n "${VERSION_CODE:-}" || -n "${VERSION_NAME:-}" ]]; then
  cp "$preset" "$preset.orig"
  trap 'mv "$preset.orig" "$preset"' EXIT
  if [[ -n "${VERSION_CODE:-}" ]]; then
    sed -i "s|^version/code=.*|version/code=$VERSION_CODE|" "$preset"
  fi
  if [[ -n "${VERSION_NAME:-}" ]]; then
    sed -i "s|^version/name=.*|version/name=\"$VERSION_NAME\"|" "$preset"
  fi
fi

"$root/ops/ci/setup-firebase-android.sh"

mkdir -p "$(dirname "$out")"
rm -f "$out"
"$godot" --headless --path "$root/client" --import
"$godot" --headless --path "$root/client" --export-debug Android "$out"
# Godot can log an export error and still exit 0, so check the result.
if [[ ! -s "$out" ]]; then
  echo "Export failed: $out was not created" >&2
  exit 1
fi
echo "Exported $out"
