#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-open-panel-pointer-navigation.m with real pointer events (xdotool) on $DISPLAY: a double-click on
# the first row enters a folder, and a double-click at the same place of each new listing, made 0.9, 0.3 and 1.0
# seconds after the previous one, enters the next folder (the window system counts them as clicks 3 and 4, 5 and 6...).
# Exactly one level is entered per double-click, nothing is selected in a listing reached by double-click, the panel
# never accepts a folder as a file, and a third click right after a double-click enters nothing.
# Usage: appkit-open-panel-pointer-navigation-x11.sh <command that runs "appkit-open-panel-pointer-navigation <dir> modal|sheet 40">
# The command must be given the folder as its first argument by this script. Needs xdotool.
set -u
status=0
for mode in modal sheet; do
    out=$(mktemp); tree=${TMPDIR:-/tmp}/opn-$$-$mode
    "$@" "$tree" $mode 40 > "$out" 2>&1 < /dev/null &
    pid=$!
    for _ in $(seq 200); do grep -q '^DIR ' "$out" && break; sleep 0.1; done
    sleep 1.5
    click() { read -r x y <<< "$(grep '^ROW 0' "$out" | tail -1 | awk '{print $3, $4}')"; xdotool mousemove "$x" "$y"; sleep 0.15
              xdotool click --repeat "$1" --delay 90 1; }
    click 2; sleep 0.9; click 2; sleep 0.3; click 2; sleep 1.0; click 2; sleep 1.2
    levels=$(grep -c '^DIR ' "$out")
    if [ "$levels" = 5 ]; then echo "PASS: $mode: four double-clicks entered four folders"; else echo "FAIL: $mode: $levels directories shown (want 5)"; status=1; fi
    if grep -q '^ENDED' "$out"; then echo "FAIL: $mode: the panel accepted something"; status=1; fi
    click 3; sleep 1.2
    after=$(grep -c '^DIR ' "$out")
    if [ "$after" = 6 ]; then echo "PASS: $mode: a triple click entered one folder"; else echo "FAIL: $mode: triple click made $((after - levels)) steps (want 1)"; status=1; fi
    xdotool key Escape; sleep 1
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    rm -f "$out"
done
exit $status
