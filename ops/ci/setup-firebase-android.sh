#!/usr/bin/env bash
# Prepares client/ for an Android export with push notifications: installs the
# pinned godot-x/firebase plugin, enables it, installs Godot's Gradle build
# template and adds the Google Services Gradle plugin to it. Everything it
# creates is git-ignored (client/android/, client/addons/), so it is safe to
# run again.
#
#   GODOT_VERSION=4.5.1 ops/ci/setup-firebase-android.sh
#
# Needs the Android export templates (ops/ci/install-godot.sh --android).
set -euo pipefail

version=${GODOT_VERSION:?GODOT_VERSION is required}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
client="$root/client"
tmp=${RUNNER_TEMP:-/tmp}

# 1.8.0 is the release built for Godot 4.5 (2.x targets 4.6 and later).
plugin_version=1.8.0
plugin_sha256=6669a61e83f6482c33cf990d56a464806b3338194d3613d7d2e016658deb24a5
google_services_plugin=4.4.4

if [[ ! -f "$client/google-services.json" ]]; then
  echo "client/google-services.json is missing (download it from the Firebase console)" >&2
  exit 1
fi

# --- Firebase plugin --------------------------------------------------------
if [[ ! -f "$client/addons/godotx_firebase/plugin.cfg" ]]; then
  curl -sSfL -o "$tmp/godotx_firebase.zip" \
    "https://github.com/godot-x/firebase/releases/download/${plugin_version}/godotx_firebase.zip"
  echo "${plugin_sha256}  $tmp/godotx_firebase.zip" | sha256sum -c -
  # The zip holds addons/, android/ and ios/ (possibly inside a top folder);
  # only the first two are used.
  extracted="$tmp/godotx_firebase"
  rm -rf "$extracted"
  unzip -q -o "$tmp/godotx_firebase.zip" -d "$extracted"
  src=$(dirname "$(find "$extracted" -type d -name addons -print -quit)")
  [[ -d "$src/addons/godotx_firebase" && -d "$src/android" ]]     || { echo "Unexpected layout in the Firebase plugin zip" >&2; find "$extracted" -maxdepth 3 >&2; exit 1; }
  mkdir -p "$client/android"
  cp -r "$src/addons" "$client/"
  cp -r "$src/android/." "$client/android/"
  rm -rf "$extracted" "$tmp/godotx_firebase.zip"
fi

if ! grep -q '^\[editor_plugins\]' "$client/project.godot"; then
  printf '\n[editor_plugins]\n\nenabled=PackedStringArray("res://addons/godotx_firebase/plugin.cfg")\n' \
    >> "$client/project.godot"
fi

# --- Gradle build template ---------------------------------------------------
templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version}.stable"
build="$client/android/build"
if [[ ! -f "$client/android/.build_version" ]]; then
  mkdir -p "$build"
  unzip -q -o "$templates/android_source.zip" -d "$build"
  touch "$build/.gdignore"
  echo "${version}.stable" > "$client/android/.build_version"
fi

gradle="$build/build.gradle"
if ! grep -q 'com.google.gms:google-services' "$gradle"; then
  awk -v dep="        classpath 'com.google.gms:google-services:${google_services_plugin}'" '
    !done && /^[[:space:]]*dependencies[[:space:]]*\{/ { print; print dep; done = 1; next }
    { print }
  ' "$gradle" > "$gradle.new"
  mv "$gradle.new" "$gradle"
  printf "\napply plugin: 'com.google.gms.google-services'\n" >> "$gradle"
fi
grep -q "classpath 'com.google.gms:google-services" "$gradle" \
  || { echo "Could not add the Google Services plugin to $gradle" >&2; exit 1; }

echo "Firebase plugin ${plugin_version} and the Gradle template are ready in client/"
