#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-input-no-appkit: types keys, moves the pointer over the program's X window, clicks and
# turns the wheel with XTest on $DISPLAY. Usage:
#   coregraphics-x11-input-no-appkit.sh <command that runs coregraphics-x11-input-no-appkit>
# Needs xdotool (the window geometry and focus) and a C compiler with the Xlib and XTest headers (the injector).
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
xdotool windowfocus --sync "$win" 2>/dev/null
X 100 k:38:1 k:38:0
X 100 b:1:1 b:1:0
X 100 b:4:1 b:4:0 b:5:1 b:5:0 b:6:1 b:6:0 b:7:1 b:7:0
sleep 0.2
X 150 k:39:1 k:39:0
for _ in $(seq 100); do grep -q '^INJECTED' "$out" && break; sleep 0.1; done
grep -q '^INJECTED' "$out" || { echo "FAIL: the raw events were not fed"; cat "$out"; kill $pid; exit 1; }
sleep 0.3
X 150 e:$win:4:7000 e:$win:4:7001
sleep 0.5
xdotool windowfocus --sync "$win" 2>/dev/null
X 150 k:24:1 k:24:0

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
scroll=$(grep '^SCROLL ' "$out" | head -1)
if [ "$scroll" = "SCROLL $PX $PY" ]; then echo "PASS the global location of a wheel notch is the root location ($PX, $PY)"; else echo "FAIL the global location of a wheel notch was '$scroll', expected $PX, $PY"; status=1; fi
exit $status
