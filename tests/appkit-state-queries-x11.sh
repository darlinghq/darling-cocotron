#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-state-queries.m with XTest (xdotool) on $DISPLAY, which must have a window manager.
# Usage: appkit-state-queries-x11.sh <command that runs appkit-state-queries>
# for example: appkit-state-queries-x11.sh darling shell env DISPLAY=:96 /path/appkit-state-queries
# Needs xdotool.
set -u
work=$(mktemp -d)
out=$work/out
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

waitfor() {
    for _ in $(seq 400); do grep -q "^$1" "$out" && return 0; sleep 0.1; done
    echo "FAIL: no $1"; cat "$out"; exit 1
}
waitfor READY
sleep 1.5
id=$(xdotool search --name '^state-queries$' | head -1)
[ -n "$id" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
eval "$(xdotool getwindowgeometry --shell "$id")"
xdotool windowactivate --sync "$id" 2>/dev/null
sleep 0.3
xdotool mousemove $((X + WIDTH / 2 - 20)) $((Y + HEIGHT / 2))
sleep 0.2
xdotool mousemove $((X + WIDTH / 2)) $((Y + HEIGHT / 2))
waitfor PHASE2
sleep 0.3
xdotool keydown shift mousedown 1
waitfor PHASE3
sleep 0.3
xdotool mouseup 1 keyup shift
waitfor PHASE4
sleep 0.3
xdotool mousemove 5 5
for _ in $(seq 200); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
