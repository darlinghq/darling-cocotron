#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-menu-title-click.m on a headless sway compositor with a virtual pointer (the menu titles are
# in a strip drawn in the window there). Usage:
#   appkit-menu-title-click-wayland.sh <command that runs "appkit-menu-title-click <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg, python3,
# SWAYSOCK and WAYLAND_DISPLAY for the compositor, and VIRTUAL_POINTER, the path of a built
# tests/wayland-virtual-pointer.c.
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

pos=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "title-click-host" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"], r["y"])
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$pos" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
set -- $pos; X=$1 Y=$2
grep -q '^WHERE strip' "$out" || { echo "FAIL: the titles are not in a strip in the window"; cat "$out"; exit 1; }

title() { set -- $(grep "^TITLE $1 " "$out"); echo "$((X + $3)) $((Y + $4))"; }
click() {
    local clicked
    clicked=$(grep -c '^CLICKED' "$vpout")
    echo "$1 $2" >&3
    for _ in $(seq 50); do [ "$(grep -c '^CLICKED' "$vpout")" -gt "$clicked" ] && break; sleep 0.1; done
}
menus() { grep '^MENUS ' "$out" | tail -1 | cut -d' ' -f2; }
wait_menus() {
    for _ in $(seq 40); do [ "$(menus)" = "$1" ] && return 0; sleep 0.1; done
    return 1
}
status=0
expect() { # description, exit status of the condition
    if [ "$2" = 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; status=1; fi
}

set -- $(title 1); file_x=$1 file_y=$2
set -- $(title 2); edit_x=$1 edit_y=$2
outside="$((X + 200)) $((Y + 250))"

click $file_x $file_y
wait_menus 1; expect "a click on File opens its menu" $?
sleep 0.6
click $file_x $file_y
wait_menus 0; expect "a second click on File closes the menu" $?
sleep 0.6

click $file_x $file_y
wait_menus 1; expect "File opens again" $?
sleep 0.6
# With a menu open, the pointer reaching another title switches to that menu.
echo "move $edit_x $edit_y" >&3
for _ in $(seq 50); do grep -q '^MOVED' "$vpout" && break; sleep 0.1; done
for _ in $(seq 40); do grep -q '^OPEN Edit' "$out" && break; sleep 0.1; done
grep -q '^OPEN Edit' "$out"; expect "moving onto the Edit title switches to its menu" $?
sleep 0.5
[ "$(menus)" = 1 ]; expect "only the Edit menu is open after the switch" $?
click $edit_x $edit_y
wait_menus 0; expect "a click on the title of the switched-to menu closes it" $?
sleep 0.6

click $file_x $file_y
wait_menus 1; expect "File opens a third time" $?
sleep 0.6
click $outside
wait_menus 0; expect "a click outside closes the menu" $?
sleep 0.6

# Press on the title, drag onto the first item, release there.
echo "drag $file_x $file_y 0 36" >&3
for _ in $(seq 100); do grep -q '^DRAGGED' "$vpout" && break; sleep 0.1; done
for _ in $(seq 40); do grep -q '^CHOSE New' "$out" && break; sleep 0.1; done
grep -q '^CHOSE New' "$out"; expect "press on a title, drag to the first item, release chooses it" $?
wait_menus 0; expect "the menu is closed after the choice" $?

[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
