#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-x11-relative-mouse-game: gives the program its commands as keys and moves the pointer over its
# window "relative-mouse-game" with XTest on $DISPLAY, which must have a window manager. Usage:
#   appkit-x11-relative-mouse-game.sh <command that runs appkit-x11-relative-mouse-game>
# Needs xdotool (the window) and a C compiler with the Xlib and XTest headers (the injector).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xptr" "$here/x11-xtest-pointer.c" -lX11 -lXtst || { echo "FAIL: cannot build the pointer injector"; exit 1; }
X() { "$work/xptr" "$@"; }
key() { X 250 k:$1:1 k:$1:0; }
# The X key codes (evdev) of h s u t d e c a q
h=43 s=39 u=30 t=28 d=40 e=26 c=54 a=38 q=24

"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1.5
win=$(xdotool search --name '^relative-mouse-game$' | head -1)
[ -n "$win" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
eval "$(xdotool getwindowgeometry --shell "$win")"
PX=$((X + 200)) PY=$((Y + 150))
xdotool windowfocus --sync "$win" 2>/dev/null
sleep 0.3

X 100 m:$PX:$PY
key $h; key $s
key $u
X 150 m:$((PX + 5)):$PY m:$PX:$PY
key $t
X 100 m:$PX:$PY
key $d
sleep 0.5
key $e
X 250 m:$((PX + 10)):$PY
X 250 m:$((PX + 15)):$PY
X 250 m:$PX:$((PY + 5))
sleep 0.3
key $c
key $a
key $q

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
