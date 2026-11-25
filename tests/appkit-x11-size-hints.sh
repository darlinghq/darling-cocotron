#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-x11-size-hints.m on $DISPLAY (a window manager is not needed) and checks the
# minimum and maximum size hints (WM_NORMAL_HINTS) it gave its window at each stage.
# Usage: appkit-x11-size-hints.sh <command that runs the test, with DARLING_APPKIT_BACKEND=x11>; the
# command gets the directory the test watches as its last argument, with $GUEST_PATH_PREFIX in front of
# it when the test sees the host's files under a prefix (in a Darling guest: /Volumes/SystemRoot).
# Needs xdotool and xprop.
set -u
out=$(mktemp)
dir=$(mktemp -d)
"$@" "${GUEST_PATH_PREFIX:-}$dir" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$out" "$dir"' EXIT
for _ in $(seq 400); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
id=$(xdotool search --name '^x11-size-hints$' | head -1)
[ -n "$id" ] || { echo "FAIL: no window"; exit 1; }
status=0
hints() { xprop -id "$id" WM_NORMAL_HINTS; }
size() { sed -n "s/.*program specified $1 size: \\([0-9]*\\) by \\([0-9]*\\).*/\\1x\\2/p" <<< "$2"; }
# check <label> <min or none> <max or none>, as WxH
check() {
    local h min max
    h=$(hints); min=$(size minimum "$h"); max=$(size maximum "$h")
    [ -n "$min" ] || min=none
    [ -n "$max" ] || max=none
    if [ "$min" = "$2" ] && [ "$max" = "$3" ]; then echo "PASS: $1 (min $min, max $max)"
    else echo "FAIL: $1: min $min (wanted $2), max $max (wanted $3)"; status=1; fi
}
advance() { touch "$dir/go$1"; for _ in $(seq 100); do grep -q "^STAGE $1\$" "$out" && break; sleep 0.1; done; sleep 0.5; }

check "limits set before the window is shown" 200x150 800x600
advance 1
check "contentMinSize set after minSize is the minimum" 250x180 800x600
advance 2
check "a maximum below the minimum is raised to it" 250x180 250x180
advance 3
check "removed limits leave no hints" none none
advance 4
eval "$(xdotool getwindowgeometry --shell "$id")"
w=$WIDTH h=$HEIGHT
check "a window that is not resizable is fixed at its size" "${w}x${h}" "${w}x${h}"
[ $status = 0 ] && echo "RESULT failures=0" || echo "RESULT failures=1"
exit $status
