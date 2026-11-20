#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-about-panel-scroller.m with XTest (xdotool) on $DISPLAY, which must have a window
# manager: drags the knob of the About panel's scroller down, then clicks the track below the knob, and
# checks that the scroller's value grew each time. Usage:
#   appkit-about-panel-scroller-x11.sh <command that runs "appkit-about-panel-scroller <seconds>">
# The command must run an app bundle whose Resources hold a long Credits.rtf. Needs xdotool.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
id=$(xdotool search --name '^about-panel$' | head -1)
[ -n "$id" ] || { echo "FAIL: no panel window"; exit 1; }
set -- $(grep '^scroller ' "$out"); sx=$2 sy=$3 sw=$4 sh=$5 ky=$6 kh=$7
eval "$(xdotool getwindowgeometry --shell "$id")"
value() { grep '^VALUE ' "$out" | tail -1 | cut -d' ' -f2; }
status=0
grep '^enabled ' "$out"

x=$((X + sx + sw / 2))
v0=$(value)
y=$((Y + ky + kh / 2))
xdotool mousemove $x $y; sleep 0.3
xdotool mousedown 1; sleep 0.3
for i in 1 2 3 4 5 6 7 8; do xdotool mousemove $x $((y + 40 * i / 8)); sleep 0.05; done
sleep 0.3
xdotool mouseup 1; sleep 1
v1=$(value)
if awk "BEGIN{exit !(${v1:-0} > ${v0:-0})}"; then echo "PASS: knob drag: $v0 -> $v1"
else echo "FAIL: knob drag: $v0 -> $v1"; status=1; fi

# The knob has moved: click the track near the bottom of the scroller, below it.
y=$((Y + sy + sh - 8))
xdotool mousemove $x $y; sleep 0.3
xdotool click 1; sleep 1
v2=$(value)
if awk "BEGIN{exit !(${v2:-0} > ${v1:-0})}"; then echo "PASS: track click: $v1 -> $v2"
else echo "FAIL: track click: $v1 -> $v2"; status=1; fi
wait $pid
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
