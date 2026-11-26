#!/usr/bin/env bash
# Exports the Windows build of the Godot client: one Slavian.exe with the
# game packed inside, zipped.
#
#   ops/export-windows.sh build/slavian-0.23.1-windows.zip
#
# Needs `godot` on the PATH (or $GODOT) and Godot's Windows export templates
# (ops/ci/install-godot.sh --windows). VERSION_NAME, when set, is written
# into the exe's file properties.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=$(realpath -m "${1:?usage: $0 <output.zip>}")
godot=${GODOT:-godot}
preset="$root/client/export_presets.cfg"
work=$(mktemp -d)
trap 'rm -rf "$work"; [[ -f "$preset.orig" ]] && mv "$preset.orig" "$preset"' EXIT

if [[ -n "${VERSION_NAME:-}" ]]; then
  cp "$preset" "$preset.orig"
  sed -i "s|^application/product_version=.*|application/product_version=\"$VERSION_NAME\"|; s|^application/file_version=.*|application/file_version=\"$VERSION_NAME\"|" "$preset"
fi

"$godot" --headless --path "$root/client" --import
"$godot" --headless --path "$root/client" --export-release "Windows Desktop" "$work/Slavian.exe"
# Godot can log an export error and still exit 0, so check the result.
if [[ ! -s "$work/Slavian.exe" ]]; then
  echo "Export failed: Slavian.exe was not created" >&2
  exit 1
fi
mkdir -p "$(dirname "$out")"
rm -f "$out"
(cd "$work" && zip -q -9 "$out" Slavian.exe)
echo "Wrote $out"
