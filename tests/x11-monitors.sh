#!/usr/bin/env bash
# Runs tests/x11-monitors.c on its own Xvfb (never the user's session).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cc -Wall -Wextra "$root/tests/x11-monitors.c" -lX11 -lXrandr -lm -o "$temp/probe"
xvfb-run -a -s '-screen 0 1280x720x24' "$temp/probe"
