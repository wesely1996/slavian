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

# Godot's template uses the plugins DSL (no buildscript block): declare the
# Google Services plugin's version in settings.gradle and apply it in the
# app's plugins block.
settings="$build/settings.gradle"
gradle="$build/build.gradle"
# Adds a line at the end of the first plugins { } block (after the Android
# plugin, which Google Services needs applied first).
add_to_plugins() { # file, line to add, marker that it is already there
  grep -q "$3" "$1" && return
  awk -v line="$2" '
    !done && /^[[:space:]]*plugins[[:space:]]*\{/ { inside = 1 }
    inside && /^[[:space:]]*\}/ { print line; inside = 0; done = 1 }
    { print }
  ' "$1" > "$1.new"
  mv "$1.new" "$1"
}
add_to_plugins "$settings" "        id 'com.google.gms.google-services' version '${google_services_plugin}'" "com.google.gms.google-services"
add_to_plugins "$gradle" "    id 'com.google.gms.google-services'" "com.google.gms.google-services"
grep -q "id 'com.google.gms.google-services' version" "$settings" && grep -q "id 'com.google.gms.google-services'" "$gradle" \
  || { echo "Could not add the Google Services plugin to the Gradle template in $build" >&2; exit 1; }

echo "Firebase plugin ${plugin_version} and the Gradle template are ready in client/"
