#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/coregraphics-state-queries.m with XTest (xdotool) on $DISPLAY. Usage:
#   coregraphics-state-queries-x11.sh <command that runs coregraphics-state-queries>
# for example: coregraphics-state-queries-x11.sh darling shell env DISPLAY=:96 /path/coregraphics-state-queries
# Needs xdotool.
set -u
work=$(mktemp -d)
out=$work/out
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

waitfor() {
    for _ in $(seq 400); do grep -q "^$1" "$out" && return 0; sleep 0.1; done
    echo "FAIL: no $1"; cat "$out"; exit 1
}
waitfor READY
sleep 1
xdotool mousemove 300 200
waitfor PHASE2
sleep 0.3
xdotool keydown shift mousedown 1
waitfor PHASE3
sleep 0.3
xdotool mouseup 1 keyup shift
for _ in $(seq 200); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
