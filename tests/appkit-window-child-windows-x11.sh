#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-child-windows.m on $DISPLAY (with a window manager), then has the window manager
# move the parent window and checks that the attached child window moved by as much, both in the X server
# and in the frame AppKit reports. Usage:
#   appkit-window-child-windows-x11.sh <command that runs "appkit-window-child-windows <seconds>">
# Needs xdotool.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
status=0
grep -q '^READY 0$' "$out" || status=1
parent=$(xdotool search --name '^child-parent$' | head -1)
child=$(xdotool search --name '^child-attached$' | head -1)
if [ -z "$parent" ] || [ -z "$child" ]; then echo "FAIL: windows not found"; status=1
else
    eval "$(xdotool getwindowgeometry --shell "$child")"; cx=$X cy=$Y
    eval "$(xdotool getwindowgeometry --shell "$parent")"
    xdotool windowmove "$parent" $((X + 100)) $((Y + 60))
    for _ in $(seq 100); do grep -q '^moved' "$out" && break; sleep 0.1; done
    sleep 0.5
    eval "$(xdotool getwindowgeometry --shell "$child")"
    got="child X window moved $((X - cx)),$((Y - cy)); AppKit: $(grep '^moved' "$out" | tr '\n' ' ')"
    first=$(grep '^child' "$out" | head -1) last=$(grep '^child' "$out" | tail -1)
    set -- $first; fx=$2 fy=$3; set -- $last
    got="$got, child frame moved $(($2 - fx)),$(($3 - fy))"
    want="child X window moved 100,60; AppKit: moved 100 -60 , child frame moved 100,-60"
    if [ "$got" = "$want" ]; then echo "PASS: $got"; else echo "FAIL: $got; expected $want"; status=1; fi
fi
kill $pid 2>/dev/null; wait $pid 2>/dev/null
grep '^PASS \|^FAIL ' "$out"
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
