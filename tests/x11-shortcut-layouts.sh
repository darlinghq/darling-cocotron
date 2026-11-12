#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cc "$root/tests/x11-shortcut-characters.c" -lX11 -o "$temp/probe"
# Keep keyboard changes alive between clients; each run owns its X server.
xvfb-run -a -s '-screen 0 800x600x24 -noreset' bash -c '
    set -e
    setxkbmap -layout us
    "$1"
    setxkbmap -layout fr
    "$1" ampersand ampersand 1 0
    setxkbmap -layout us,de
    "$1" y y Y 0
    "$1" y z Z 1
' bash "$temp/probe"
