#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-menu-popup-positioning.m with XTest (xdotool) on $DISPLAY: opens each case's menu with
# a click on the window, then clicks the item the test names where the program says it is (or outside the
# menu), so that the menu must really be on screen where AppKit put it. Usage:
#   appkit-menu-popup-positioning-x11.sh <command that runs "appkit-menu-popup-positioning <seconds>">
# Needs xdotool and a window manager on $DISPLAY.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
id=$(xdotool search --name '^menu-host$' | head -1)
[ -n "$id" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
eval "$(xdotool getwindowgeometry --shell "$id")"

click() { xdotool mousemove "$1" "$2"; sleep 0.3; xdotool click 1; }

status=0
# case, item to choose (or "outside"), expected result
for spec in "1 1 YES" "2 2 YES" "3 outside NO"; do
    set -- $spec
    n=$1 choose=$2 want=$3
    click $((X + 20)) $((Y + 20))
    for _ in $(seq 100); do grep -q "^OPEN $n\$" "$out" && break; sleep 0.1; done
    grep -q "^OPEN $n\$" "$out" || { echo "FAIL: case $n: no menu"; status=1; break; }
    sleep 0.5
    if [ "$choose" = outside ]; then
        click $((X + 450)) $((Y + 350))
    else
        set -- $(grep "^ITEM $n $choose " "$out")
        click $((X + $4 + 10)) $((Y + $5 + $7 / 2))
    fi
    for _ in $(seq 100); do grep -q "^RESULT $n " "$out" && break; sleep 0.1; done
    got=$(grep "^RESULT $n " "$out")
    if [ "$got" = "RESULT $n $want" ]; then echo "PASS: case $n: $got"
    else echo "FAIL: case $n: '$got', expected RESULT $n $want"; status=1; fi
done
wait $pid
actions=$(grep '^ACTION' "$out" | tr '\n' ' ')
if [ "$actions" = "ACTION Two ACTION Three " ]; then echo "PASS: actions $actions"
else echo "FAIL: actions '$actions', expected ACTION Two ACTION Three"; status=1; fi
grep -q '^PASS clamp' "$out" && grep '^PASS clamp' "$out" || { echo "FAIL: the clamp case did not pass"; status=1; }
grep -q '^FAIL' "$out" && { grep '^FAIL' "$out"; status=1; }
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
