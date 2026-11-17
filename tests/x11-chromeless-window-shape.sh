#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
#
# X11 harness: runs tests/appkit-window-transparent-titlebar-chrome.m (built as $1, in the Darling guest) and
# checks the bounding shape of its windows: the windows that show no frame ("chromeless", "late-transparent")
# have their corners cut, the others ("plain", "fullsize-opaque-bar") keep them. DISPLAY names the X server.
# Usage: x11-chromeless-window-shape.sh <guest program path inside the guest>
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cc -Wall "$root/tests/x11-chromeless-window-shape.c" -lX11 -lXext -o "$temp/shape"
(timeout -s KILL 60 darling shell "$1" 14 </dev/null >"$temp/guest.out" 2>&1 &)
sleep 9
"$temp/shape" | sort >"$temp/shapes"
cat "$temp/shapes"
fail=0
grep -qx 'chromeless: corners cut' "$temp/shapes" || { echo "FAIL: chromeless corners not cut"; fail=1; }
grep -qx 'late-transparent: corners cut' "$temp/shapes" || { echo "FAIL: late-transparent corners not cut"; fail=1; }
grep -qx 'plain: corners whole' "$temp/shapes" || { echo "FAIL: plain corners cut"; fail=1; }
grep -qx 'fullsize-opaque-bar: corners whole' "$temp/shapes" || { echo "FAIL: fullsize-opaque-bar corners cut"; fail=1; }
[ $fail = 0 ] && echo PASS
exit $fail
