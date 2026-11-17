#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
#
# X11 harness: runs tests/appkit-window-left-edge.m (built as $1, in the Darling guest), waits until the
# window has been flushed many times and checks with tests/x11-window-left-edge.c that its outline is one pixel
# wide along the whole left and right edge. DISPLAY names the X server.
# Usage: x11-window-left-edge.sh <guest program path inside the guest>
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cc -Wall "$root/tests/x11-window-left-edge.c" -lX11 -o "$temp/edge"
(timeout -s KILL 60 darling shell "$1" 16 </dev/null >"$temp/guest.out" 2>&1 &)
sleep 12
"$temp/edge"
