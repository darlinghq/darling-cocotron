#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-scroll-cgevents-wayland: scrolls over the window "scroll-cgevents-wayland" with a virtual
# pointer (the helper tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER): a wheel, a finger on a touchpad, a
# source of continuous scrolling, a finger scroll cut short by the pointer leaving the window, and a wheel notch and a
# finger scroll with Shift held. $WAYLAND_DISPLAY,
# $XDG_RUNTIME_DIR and $SWAYSOCK must name a headless sway whose windows float. Usage:
#   appkit-scroll-cgevents-wayland.sh <command that runs appkit-scroll-cgevents-wayland>
# Needs swaymsg, wtype and python3.
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
for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
swaymsg -q '[title="scroll-cgevents-wayland"] move position 200 200, focus'
sleep 0.5
center=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "scroll-cgevents-wayland" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$center" ] || { echo "FAIL: the window is not on screen"; cat "$out"; exit 1; }
PX=${center% *} PY=${center#* }

n=0
V() {
    echo "$*" >&3
    n=$((n + 1))
    for _ in $(seq 300); do [ "$(wc -l < "$vpout")" -gt "$n" ] && return; sleep 0.02; done
}
V "abs $PX $PY"
sleep 0.5
# the wheel: one notch down, one to the right, two up
V "wheel 0 1"; V "wheel 1 1"; V "wheel 0 -2"
sleep 0.3
# a finger: 12 and 6 units down, then stop
V "axis 0 12 1"; V "axis 0 6 1"; V "stop 0 1"
sleep 0.3
# five frames of 0.4 units, then stop
for i in 1 2 3 4 5; do V "axis 0 0.4 1"; done
V "stop 0 1"
sleep 0.3
# a continuous source
V "axis 0 7 2"
sleep 0.3
# a finger scroll cut short: the pointer leaves the window
V "axis 0 5 1"
V "abs 1850 1050"
sleep 0.5
# with Shift held (wtype holds it for 1.6 s): a wheel notch down, a finger scroll
V "abs $PX $PY"
sleep 0.3
wtype -M shift -s 1600 -m shift &
sleep 0.8
V "wheel 0 1"
V "axis 0 12 1"; V "stop 0 1"
sleep 1.2
wtype -s 300 q

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
