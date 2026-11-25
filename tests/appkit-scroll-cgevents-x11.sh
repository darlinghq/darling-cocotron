#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-scroll-cgevents-x11: moves the pointer and presses the wheel buttons with XTest on $DISPLAY, which
# must have a window manager, over the window "scroll-cgevents-x11". Usage:
#   appkit-scroll-cgevents-x11.sh <command that runs appkit-scroll-cgevents-x11>
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

win=$(xdotool search --name '^scroll-cgevents-x11$' | head -1)
[ -n "$win" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
xdotool windowactivate --sync "$win" 2>/dev/null
sleep 0.5
eval "$(xdotool getwindowgeometry --shell "$win")"   # X, Y, WIDTH, HEIGHT of the window's client area
PX=$((X + 200)) PY=$((Y + 200))
SHIFT=50

X 80 m:1850:1050
X 120 m:$((PX - 30)):$((PY - 30)) m:$PX:$PY
sleep 0.3
# a click, the four wheel buttons, three notches, a notch with Shift, a click (a second click state), a notch
X 30 b:1:1 b:1:0
X 25 b:4:1 b:4:0 b:5:1 b:5:0 b:6:1 b:6:0 b:7:1 b:7:0 b:4:1 b:4:0 b:4:1 b:4:0 b:4:1 b:4:0
X 25 k:$SHIFT:1 b:4:1 b:4:0 k:$SHIFT:0
X 30 b:1:1 b:1:0
X 25 b:4:1 b:4:0
sleep 0.3
# the key s: the program feeds the raw events of a smooth scrolling device (the key is typed into the window)
xdotool windowfocus --sync "$win" 2>/dev/null
X 150 k:39:1 k:39:0
for _ in $(seq 100); do grep -q '^INJECTED' "$out" && break; sleep 0.1; done
grep -q '^INJECTED' "$out" || { echo "FAIL: the raw events were not fed"; cat "$out"; kill $pid; exit 1; }
sleep 0.3
# presses sent to the window with the time of the last raw event (7000) and the next one
X 150 e:$win:4:7000 e:$win:4:7001
sleep 0.5
X 150 k:24:1 k:24:0

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
# Where the first wheel notch was, as the CGEvent says: the global location is the root location here (the primary
# monitor is at the origin and the scale is 1)
scroll=$(grep '^SCROLL ' "$out" | head -1)
if [ "$scroll" = "SCROLL $PX $PY" ]; then echo "PASS the global location of a wheel notch is the root location ($PX, $PY)"; else echo "FAIL the global location of a wheel notch was '$scroll', expected $PX, $PY"; status=1; fi
exit $status
