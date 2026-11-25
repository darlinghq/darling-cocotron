#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-pointer-no-appkit: moves the pointer over the program's X window and presses the buttons
# with XTest on $DISPLAY. Usage:
#   coregraphics-x11-pointer-no-appkit.sh <command that runs coregraphics-x11-pointer-no-appkit>
# Needs xdotool (the window geometry) and a C compiler with the Xlib and XTest headers (the injector).
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
win=$(sed -n 's/^READY //p' "$out" | head -1)
sleep 1
eval "$(xdotool getwindowgeometry --shell "$win")"
PX=$((X + 150)) PY=$((Y + 120))

X 80 m:1850:1050
X 120 m:$((PX - 20)):$((PY - 20)) m:$PX:$PY
X 60 b:1:1 b:1:0 b:1:1 b:1:0
sleep 0.8
X 60 b:3:1 b:3:0 b:2:1 b:2:0
sleep 0.2
X 100 m:$PX:$PY b:1:1 m:$((PX + 10)):$((PY + 5)) m:$((PX + 30)):$((PY + 15)) b:1:0
sleep 0.8
X 100 m:$PX:$PY k:50:1 b:1:1 b:1:0 k:50:0
sleep 0.4
xdotool windowfocus --sync "$win" 2>/dev/null
X 150 k:24:1 k:24:0

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
click=$(grep '^CLICK ' "$out" | head -1)
if [ "$click" = "CLICK $PX $PY" ]; then echo "PASS the global location of a click is the root location ($PX, $PY)"; else echo "FAIL the global location of a click was '$click', expected $PX, $PY"; status=1; fi
exit $status
