#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-event-tap-real-input.m with XTest (xdotool) on $DISPLAY, which must have a window
# manager: types "a" and clicks in the middle of the window "tap-real-input". Usage:
#   appkit-event-tap-real-input-x11.sh <command that runs appkit-event-tap-real-input>
# for example: appkit-event-tap-real-input-x11.sh darling shell /path/appkit-event-tap-real-input
# Needs xdotool.
set -u
work=$(mktemp -d)
out=$work/out
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1

id=$(xdotool search --name '^tap-real-input$' | head -1)
[ -n "$id" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
eval "$(xdotool getwindowgeometry --shell "$id")"
xdotool windowactivate --sync "$id" 2>/dev/null
xdotool windowfocus --sync "$id" 2>/dev/null
sleep 0.3
xdotool key --window "$id" --clearmodifiers a 2>/dev/null || xdotool key a
sleep 0.3
xdotool mousemove $((X + WIDTH / 2)) $((Y + HEIGHT / 2))
sleep 0.2
xdotool click 1

# Part two: while the program does not read, move twice, click, and move twice again
for _ in $(seq 100); do grep -q '^PHASE2' "$out" && break; sleep 0.1; done
grep -q '^PHASE2' "$out" || { echo "FAIL: no second part"; cat "$out"; exit 1; }
mx=$((X + WIDTH / 2)) my=$((Y + HEIGHT / 2))
xdotool mousemove $((mx - 60)) $my mousemove $((mx - 45)) $my mousemove $((mx - 30)) $my click 1 \
    mousemove $((mx + 30)) $my mousemove $((mx + 60)) $my

for _ in $(seq 150); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
