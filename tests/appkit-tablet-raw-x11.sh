#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-tablet-raw-x11: moves the pointer (XTest) over the window of the program, at the stroke's first position,
# on $DISPLAY, which must be an X server of your own with XInput2. Usage:
#   appkit-tablet-raw-x11.sh <command that runs appkit-tablet-raw-x11>
# Needs a C compiler with the Xlib and XTest headers (the injector).
set -u
work=$(mktemp -d)
out=$work/out
here=$(cd "$(dirname "$0")" && pwd)
cc -o "$work/xptr" "$here/x11-xtest-pointer.c" -lX11 -lXtst || { echo "FAIL: cannot build the pointer injector"; exit 1; }

"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 600); do grep -q -E '^(READY|SKIP)' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { cat "$out"; exit 1; }
sleep 1
# The window is borderless in the top left corner of the screen.
"$work/xptr" 100 m:50:50 m:100:50
for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
