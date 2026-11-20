#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-standard-buttons.m on $DISPLAY (with a window manager), then clicks the close,
# miniaturize and zoom buttons of three windows with XTest (xdotool) where the program says they are, and
# checks that each click did what the button is for. Usage:
#   appkit-window-standard-buttons-x11.sh <command that runs "appkit-window-standard-buttons <seconds>">
# Needs xdotool.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1

status=0
grep -q '^READY 0$' "$out" || status=1
for spec in "btn-close close CLOSED" "btn-mini miniaturize MINIATURIZING" "btn-zoom zoom ZOOMED"; do
    set -- $spec
    name=$1 kind=$2 want=$3
    id=$(xdotool search --name "^$name\$" | head -1)
    [ -n "$id" ] || { echo "FAIL: $name: no window"; status=1; continue; }
    eval "$(xdotool getwindowgeometry --shell "$id")"
    set -- $(grep "^BUTTON $name $kind " "$out")
    xdotool mousemove $((X + $4 + $6 / 2)) $((Y + $5 + $7 / 2))
    sleep 0.3
    xdotool click 1
    for _ in $(seq 30); do grep -q "^$want $name\$" "$out" && break; sleep 0.1; done
    if grep -q "^$want $name\$" "$out"; then echo "PASS: $name: the $kind button: $want"
    else echo "FAIL: $name: clicking the $kind button did nothing"; status=1; fi
done
kill $pid 2>/dev/null
wait $pid 2>/dev/null
grep '^PASS\|^FAIL' "$out"
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
