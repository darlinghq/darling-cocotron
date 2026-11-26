#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-overlay-pointer-input.m with XTest (xdotool) on $DISPLAY. Usage:
#   appkit-overlay-pointer-input-x11.sh <command that runs appkit-overlay-pointer-input>
# for example: appkit-overlay-pointer-input-x11.sh darling shell env DISPLAY=:96 /path/appkit-overlay-pointer-input
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
waitfor 'READY\|SKIP'
if grep -q '^SKIP' "$out"; then cat "$out"; exit 0; fi
read -r _ X Y W H < <(grep '^READY' "$out")
sleep 1.5
xdotool mousemove $((X + 100)) $((Y + 100))
sleep 0.3
xdotool mousemove $((X + 200)) $((Y + 150))
waitfor PHASE2
sleep 0.3
xdotool mousemove $((X + 230)) $((Y + 130))
waitfor PHASE3
sleep 0.3
xdotool mousemove $((X + 240)) $((Y + 130))
xdotool mousemove $((X + 240)) $((Y + 160))
waitfor PHASE4
waitfor PHASE5
sleep 0.5
xdotool mousemove_relative 12 5
for _ in $(seq 200); do grep -q -E '^(PASS|FAIL)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
