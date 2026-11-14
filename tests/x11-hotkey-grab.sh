#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs tests/x11-hotkey-grab.c on its own Xvfb (never the user's session). Needs xdotool.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cc -Wall -Wextra "$root/tests/x11-hotkey-grab.c" -lX11 -lpthread -o "$temp/probe"
xvfb-run -a -s '-screen 0 1280x720x24' "$temp/probe"
