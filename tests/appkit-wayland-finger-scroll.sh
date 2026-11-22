#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-wayland-finger-scroll.m on a headless sway compositor, scrolls over its window with a virtual
# pointer like a finger on a touchpad and checks the scroll events the window got: all precise, a began phase,
# then changed, then an ended phase (with no motion) for the axis_stop, the deltas in the direction of the
# wheel sign. Usage:
#   appkit-wayland-finger-scroll.sh <command that runs "appkit-wayland-finger-scroll <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg, python3,
# SWAYSOCK for the compositor, and VIRTUAL_POINTER, the path of a built tests/wayland-virtual-pointer.c (a
# headless sway has no pointer device).
set -u
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
mkfifo "$work/fifo"
"$pointer" < "$work/fifo" > "$vpout" 2>&1 &
vp=$!
exec 3> "$work/fifo"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2

center=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "finger-scroll" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$center" ] || { echo "FAIL: the window is not on screen"; exit 1; }
echo "finger $center 12" >&3
for _ in $(seq 100); do grep -q '^SCROLLED' "$vpout" && break; sleep 0.1; done
sleep 1

status=0
events=$(grep '^EVENT' "$out")
count=$(grep -c '^EVENT' <<< "$events")
if [ "$count" -ge 3 ]; then echo "PASS: $count scroll events"; else echo "FAIL: $count scroll events, wanted 3"; status=1; fi
grep -qv 'precise=1' <<< "$events" && { echo "FAIL: an event is not precise"; status=1; } || echo "PASS: all events are precise"
phases=$(sed -n 's/.* phase=\([0-9]*\) .*/\1/p' <<< "$events" | tr '\n' ' ')
# NSEventPhaseBegan 1, Changed 4, Ended 8
if [ "$phases" = "1 4 8 " ]; then echo "PASS: phases began, changed, ended"; else echo "FAIL: phases $phases, wanted 1 4 8"; status=1; fi
dys=$(sed -n 's/.* dy=\(-\?[0-9.]*\)$/\1/p' <<< "$events" | tr '\n' ' ')
# a finger moving by +12 (down) scrolls with the wheel sign: negative, and the ended event has no motion
if [ "$dys" = "-12.0 -12.0 0.0 " ]; then echo "PASS: deltas $dys"; else echo "FAIL: deltas $dys, wanted -12.0 -12.0 0.0"; status=1; fi
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
echo "RESULT failures=$status"
exit $status
