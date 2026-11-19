#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Checks that tests/appkit-window-set-frame-origin.m put each window's client area where -setFrameOrigin:
# asked, on $DISPLAY with a reparenting window manager that decorates the titled window (xfwm4, for
# example), and that AppKit reports that frame. Usage:
#   appkit-window-set-frame-origin-x11.sh <command that runs "appkit-window-set-frame-origin 3">
# Needs xdotool.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT
for _ in $(seq 300); do grep -q '^moved$' "$out" && break; sleep 0.1; done
grep -q '^moved$' "$out" || { echo "FAIL: the test never printed moved"; cat "$out"; exit 1; }
eval "$(xdotool getdisplaygeometry --shell)"
screen_height=$HEIGHT
status=0
for spec in "titled 400 300 200" "borderless 900 300 200"; do
    set -- $spec
    name=$1 x=$2 y=$3 h=$4
    id=$(xdotool search --name "^$name\$" | head -1)
    [ -n "$id" ] || { echo "FAIL: $name: no window"; status=1; continue; }
    eval "$(xdotool getwindowgeometry --shell "$id")"
    want="$x,$((screen_height - y - h))"
    if [ "$X,$Y" = "$want" ]; then echo "PASS: $name: client window at $X,$Y"
    else echo "FAIL: $name: client window at $X,$Y, expected $want"; status=1; fi
    line=$(grep "^win $name " "$out")
    if [ "$line" = "win $name $x $y 300 $h" ]; then echo "PASS: $name: AppKit reports $x,$y"
    else echo "FAIL: $name: AppKit reports '$line', expected $x,$y"; status=1; fi
done
wait $pid
exit $status
