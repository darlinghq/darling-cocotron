#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-standard-buttons.m on a headless sway compositor, then clicks the close,
# miniaturize and zoom buttons of three windows with a virtual pointer where the program says they are
# (relative to the window, whose position comes from the compositor), and checks that each click did what
# the button is for. Usage:
#   appkit-window-standard-buttons-wayland.sh <command that runs "appkit-window-standard-buttons <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg,
# python3, SWAYSOCK and WAYLAND_DISPLAY for the compositor, and VIRTUAL_POINTER, the path of a built
# tests/wayland-virtual-pointer.c. Windows must be floating (for_window [shell=".*"] floating enable).
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
sleep 1

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
for spec in "btn-close 20 100" "btn-mini 420 100" "btn-zoom 820 100" "btn-closable 20 500" \
            "btn-hidden 420 500" "btn-titled 820 500"; do
    set -- $spec
    swaymsg -q "[title=\"$1\"] move position $2 $3"
done
sleep 0.5

status=0
grep -q '^READY 0$' "$out" || status=1
for spec in "btn-close close CLOSED" "btn-mini miniaturize MINIATURIZING" "btn-zoom zoom ZOOMED"; do
    set -- $spec
    name=$1 kind=$2 want=$3
    pos=$(rect "$name")
    [ -n "$pos" ] || { echo "FAIL: $name: no window"; status=1; continue; }
    set -- $pos; X=$1 Y=$2
    set -- $(grep "^BUTTON $name $kind " "$out")
    clicked=$(grep -c '^CLICKED' "$vpout")
    echo "$((X + $4 + $6 / 2)) $((Y + $5 + $7 / 2))" >&3
    for _ in $(seq 50); do [ "$(grep -c '^CLICKED' "$vpout")" -gt "$clicked" ] && break; sleep 0.1; done
    for _ in $(seq 30); do grep -q "^$want $name\$" "$out" && break; sleep 0.1; done
    if grep -q "^$want $name\$" "$out"; then echo "PASS: $name: the $kind button: $want"
    else echo "FAIL: $name: clicking the $kind button did nothing"; status=1; fi
done
kill $pid 2>/dev/null
wait $pid 2>/dev/null
grep '^PASS\|^FAIL' "$out"
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
