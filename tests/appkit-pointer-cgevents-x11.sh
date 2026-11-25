#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-pointer-cgevents-x11: moves the pointer and presses the buttons with XTest on $DISPLAY, which
# must have a window manager, over the window "ptr-cgevents-x11". Usage:
#   appkit-pointer-cgevents-x11.sh <command that runs appkit-pointer-cgevents-x11>
# Needs xdotool (the window) and a C compiler with the Xlib and XTest headers (the injector).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xptr" "$here/x11-xtest-pointer.c" -lX11 -lXtst || { echo "FAIL: cannot build the pointer injector"; exit 1; }
X() { "$work/xptr" "$@"; }

"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1.5

win=$(xdotool search --name '^ptr-cgevents-x11$' | head -1)
[ -n "$win" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
xdotool windowactivate --sync "$win" 2>/dev/null
sleep 0.5
eval "$(xdotool getwindowgeometry --shell "$win")"   # X, Y, WIDTH, HEIGHT of the window's client area
PX=$((X + 200)) PY=$((Y + 200))
SHIFT=50 CONTROL=37 SUPER=133

# The pointer starts outside the window; the first phase is three moves inside it
X 80 m:1850:1050
X 120 m:$((PX - 40)):$((PY - 40)) m:$((PX - 30)):$((PY - 30)) m:$((PX - 20)):$((PY - 20))
# a click, then moves (the window accepts mouse moved events by now), and back
X 80 m:$PX:$PY b:1:1 b:1:0
sleep 0.3
X 100 m:$((PX + 10)):$((PY + 10)) m:$((PX + 25)):$((PY + 15)) m:$PX:$PY
sleep 1.3
# a triple click
X 60 b:1:1 b:1:0 b:1:1 b:1:0 b:1:1 b:1:0
sleep 1.3
# a click after the interval, one 2 pixels away (count continues), one 40 pixels away (starts over)
X 60 b:1:1 b:1:0 m:$((PX + 2)):$((PY + 2)) b:1:1 b:1:0 m:$((PX + 40)):$((PY + 2)) b:1:1 b:1:0
sleep 1.3
# left, right and middle at once
X 60 b:1:1 b:1:0 b:3:1 b:3:0 b:2:1 b:2:0
sleep 1.3
# drags with each button
X 100 m:$PX:$PY b:1:1 m:$((PX + 10)):$((PY + 5)) m:$((PX + 30)):$((PY + 15)) b:1:0
sleep 1.3
X 100 m:$PX:$PY b:3:1 m:$((PX + 10)):$((PY + 5)) m:$((PX + 30)):$((PY + 15)) b:3:0
sleep 1.3
X 100 m:$PX:$PY b:2:1 m:$((PX + 10)):$((PY + 5)) m:$((PX + 30)):$((PY + 15)) b:2:0
sleep 1.3
# clicks with modifiers
X 100 m:$PX:$PY k:$SHIFT:1 b:1:1 b:1:0 k:$SHIFT:0
sleep 1.3
X 100 k:$CONTROL:1 b:1:1 b:1:0 k:$CONTROL:0
sleep 1.3
X 100 k:$SUPER:1 b:1:1 b:1:0 k:$SUPER:0
sleep 0.6
# the end: the key q
xdotool windowfocus --sync "$win" 2>/dev/null
X 150 k:24:1 k:24:0

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
# Where the first click was, as the CGEvent says: the global location is the root location here (the primary
# monitor is at the origin and the scale is 1)
click=$(grep '^CLICK ' "$out" | head -1)
if [ "$click" = "CLICK $PX $PY" ]; then echo "PASS the global location of a click is the root location ($PX, $PY)"; else echo "FAIL the global location of a click was '$click', expected $PX, $PY"; status=1; fi
exit $status
