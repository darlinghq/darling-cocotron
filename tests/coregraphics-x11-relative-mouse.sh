#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-relative-mouse: gives the program its commands as keys (XTest) and moves the pointer
# over its X window on $DISPLAY, which must have a window manager. Usage:
#   coregraphics-x11-relative-mouse.sh <command that runs coregraphics-x11-relative-mouse>
# Needs xdotool (the window geometry and focus) and a C compiler with the Xlib and XTest headers (the injector).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xptr" "$here/x11-xtest-pointer.c" -lX11 -lXtst || { echo "FAIL: cannot build the pointer injector"; exit 1; }
X() { "$work/xptr" "$@"; }
# The X key codes of the command letters (evdev): h s f d e c g w a x y z v q
key() { X 250 k:$1:1 k:$1:0; }
h=43 s=39 f=41 d=40 e=26 c=54 g=42 w=25 a=38 x=53 y=29 z=52 v=55 q=24

"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
win=$(sed -n 's/^READY //p' "$out" | head -1)
sleep 1
eval "$(xdotool getwindowgeometry --shell "$win")"
PX=$((X + 150)) PY=$((Y + 120))
xdotool windowfocus --sync "$win" 2>/dev/null
sleep 0.3

X 80 m:$PX:$PY
key $h; key $h; key $s; key $s; key $h; key $f
X 100 m:$PX:$PY
key $d
sleep 0.5
key $e
X 250 m:$((PX + 10)):$PY
X 250 m:$((PX + 15)):$PY
X 250 m:$PX:$((PY + 5))
sleep 0.3
key $c
key $g
key $e
key $w
sleep 0.3
key $a
sleep 0.3
X 100 m:$PX:$PY
key $e
key $x
X 100 m:$((PX + 60)):$PY m:$((PX + 80)):$PY
sleep 1.0
X 100 m:$((PX + 90)):$PY
sleep 0.3
key $y
key $e
key $z
X 100 m:$((PX + 40)):$((PY + 30))
sleep 0.3
key $v
key $q

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
