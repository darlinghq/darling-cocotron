#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-x11-keyboard-no-appkit: gives the program's X window the keyboard focus and types
# into it with XTest (xdotool) on $DISPLAY. Usage:
#   coregraphics-x11-keyboard-no-appkit.sh <command that runs coregraphics-x11-keyboard-no-appkit>
# Needs xdotool (the focus) and a C compiler with the Xlib and XTest headers (the key injector).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xkeys" "$here/x11-xtest-keys.c" -lX11 -lXtst || { echo "FAIL: cannot build the key injector"; exit 1; }
K() { "$work/xkeys" "$@"; }
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
win=$(sed -n 's/^READY //p' "$out" | head -1)
sleep 1
xdotool windowfocus --sync "$win" 2>/dev/null || { echo "FAIL: cannot focus window $win"; cat "$out"; exit 1; }
sleep 0.4

K 150 38:1 38:0
sleep 0.3
K 150 50:1 38:1 38:0 50:0
sleep 0.3
K 150 62:1 62:0
sleep 0.3
K 1500 39:1
K 150 39:0
sleep 0.3
K 150 24:1 24:0

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
