#!/usr/bin/env bash
# Installs Godot (and, with --android, its Android export templates) on a CI
# runner and puts `godot` on the PATH. Re-runs are cheap when ~/godot and the
# templates directory are cached.
#
#   GODOT_VERSION=4.5.1 ops/ci/install-godot.sh [--android]
set -euo pipefail

version=${GODOT_VERSION:?GODOT_VERSION is required}
base="https://github.com/godotengine/godot/releases/download/${version}-stable"
dir="$HOME/godot/$version"
tmp=${RUNNER_TEMP:-/tmp}

if [[ ! -x "$dir/godot" ]]; then
  mkdir -p "$dir"
  curl -sSfL -o "$tmp/godot.zip" "$base/Godot_v${version}-stable_linux.x86_64.zip"
  unzip -q -o "$tmp/godot.zip" -d "$dir"
  mv "$dir/Godot_v${version}-stable_linux.x86_64" "$dir/godot"
  rm "$tmp/godot.zip"
fi
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$dir" >> "$GITHUB_PATH"
fi

if [[ "${1:-}" == "--android" ]]; then
  templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version}.stable"
  if [[ ! -f "$templates/android_debug.apk" ]]; then
    mkdir -p "$templates"
    curl -sSfL -o "$tmp/templates.tpz" "$base/Godot_v${version}-stable_export_templates.tpz"
    # Only the Android templates; the full archive is >1 GB.
    unzip -q -j -o "$tmp/templates.tpz" 'templates/android_*' 'templates/version.txt' -d "$templates"
    rm "$tmp/templates.tpz"
  fi
fi
