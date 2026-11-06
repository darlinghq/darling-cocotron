#!/usr/bin/env bash
# Runs tests/x11-input-shape.c on its own Xvfb (never the user's session).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cc -Wall -Wextra "$root/tests/x11-input-shape.c" -lX11 -lXext -o "$temp/probe"
xvfb-run -a -s '-screen 0 800x600x24' "$temp/probe"
