#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drags the windows of tests/appkit-window-drag.m on a headless sway compositor with a virtual pointer and
# checks which of them the compositor moved. A Wayland client is not told where its windows are, so only the
# compositor's view is checked. Usage:
#   appkit-window-drag-wayland.sh <command that runs "appkit-window-drag <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg,
# python3, SWAYSOCK and WAYLAND_DISPLAY for the compositor, and VIRTUAL_POINTER, the path of a built
# tests/wayland-virtual-pointer.c (a headless sway has no pointer device). Windows must be floating
# (for_window [shell=".*"] floating enable), as sway moves only floating windows.
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

rect() { # print "x y" of the window with this title, in layout coordinates
    swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == sys.argv[1] and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"], r["y"])
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))' "$1"
}

# A client cannot place its windows: spread them out so that none covers another.
for spec in "perform-drag 20 100" "not-movable 420 100" "titlebar 820 100" "below-titlebar 1220 100" \
            "frame-subclass 20 500" "background 420 500"; do
    set -- $spec
    swaymsg -q "[title=\"$1\"] move position $2 $3"
done
sleep 0.5

DX=80 DY=60
status=0
for spec in "perform-drag 150 100 yes" "not-movable 150 100 no" "titlebar 150 10 yes" \
            "below-titlebar 150 60 no" "frame-subclass 150 40 yes" "background 150 100 yes"; do
    set -- $spec
    name=$1 px=$2 py=$3 moves=$4
    pos=$(rect "$name")
    [ -n "$pos" ] || { echo "FAIL: $name: no window"; status=1; continue; }
    set -- $pos; x0=$1 y0=$2
    dragged=$(grep -c '^DRAGGED' "$vpout")
    echo "drag $((x0 + px)) $((y0 + py)) $DX $DY" >&3
    for _ in $(seq 100); do [ "$(grep -c '^DRAGGED' "$vpout")" -gt "$dragged" ] && break; sleep 0.1; done
    sleep 1
    pos=$(rect "$name")
    [ -n "$pos" ] || { echo "FAIL: $name: the window went away"; status=1; continue; }
    set -- $pos
    mx=$(($1 - x0)) my=$(($2 - y0))
    if [ $moves = yes ]; then wx=$DX wy=$DY; else wx=0 wy=0; fi
    # The compositor converts the pointer position through floating point, which can cost a pixel.
    if [ $((mx - wx)) -ge -1 ] && [ $((mx - wx)) -le 1 ] && [ $((my - wy)) -ge -1 ] && [ $((my - wy)) -le 1 ]; then
        echo "PASS: $name: moved $mx,$my"
    else
        echo "FAIL: $name: moved $mx,$my; expected $wx,$wy"; status=1
    fi
done
wait $pid
[ $status = 0 ] || { echo "--- test output:"; grep -v "^frame " "$out"; }
exit $status
