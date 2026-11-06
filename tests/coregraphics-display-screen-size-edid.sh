#!/usr/bin/env bash
# Host test: compiles screenSizeFromEDID() straight out of CGDirectDisplay.m.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
awk '/^static bool screenSizeFromEDID/{p=1} p{print} p&&/^}/{exit}' \
    "$root/CoreGraphics/CGDirectDisplay.m" > "$temp/screen-size-edid-extract.inc"
test -s "$temp/screen-size-edid-extract.inc"
cc -Wall -Wextra -I"$temp" "$root/tests/coregraphics-display-screen-size-edid.c" -o "$temp/probe"
"$temp/probe"
