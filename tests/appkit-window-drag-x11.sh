#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drags the windows of tests/appkit-window-drag.m with XTest (xdotool) on $DISPLAY, which must have a
# window manager, and checks which of them moved, both in the window manager's view and in the frame
# AppKit reports. Usage:
#   appkit-window-drag-x11.sh <command that runs "appkit-window-drag <seconds>">
# for example: appkit-window-drag-x11.sh darling shell /path/appkit-window-drag 30
# Needs xdotool.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2

DX=80 DY=60
status=0
# name, press point in the window (from its top left corner), whether it should move
for spec in "perform-drag 150 100 yes" "not-movable 150 100 no" "titlebar 150 10 yes" \
            "below-titlebar 150 60 no" "frame-subclass 150 40 yes" "background 150 100 yes"; do
    set -- $spec
    name=$1 px=$2 py=$3 moves=$4
    id=$(xdotool search --name "^$name\$" | head -1)
    [ -n "$id" ] || { echo "FAIL: $name: no window"; status=1; continue; }
    eval "$(xdotool getwindowgeometry --shell "$id")"
    x0=$X y0=$Y
    cocoa0=$(grep "^frame $name " "$out" | tail -1)
    x=$((x0 + px)) y=$((y0 + py))
    xdotool mousemove $x $y
    sleep 0.3
    xdotool mousedown 1
    sleep 0.3
    for i in 1 2 3 4 5 6 7 8; do
        xdotool mousemove $((x + DX * i / 8)) $((y + DY * i / 8))
        sleep 0.05
    done
    sleep 0.3
    xdotool mouseup 1
    sleep 1
    eval "$(xdotool getwindowgeometry --shell "$id")"
    cocoa1=$(grep "^frame $name " "$out" | tail -1)
    set -- $cocoa0; cx0=$3 cy0=$4
    set -- $cocoa1; cx1=$3 cy1=$4
    got="X moved $((X - x0)),$((Y - y0)), frame moved $((cx1 - cx0)),$((cy1 - cy0))"
    if [ $moves = yes ]; then want="X moved $DX,$DY, frame moved $DX,$((-DY))"
    else want="X moved 0,0, frame moved 0,0"; fi
    if [ "$got" = "$want" ]; then echo "PASS: $name: $got"
    else echo "FAIL: $name: $got; expected $want"; status=1; fi
done
wait $pid
[ $status = 0 ] || { echo "--- test output:"; grep -v "^frame " "$out"; }
exit $status
