#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-menu-dismiss-click.m on a headless sway compositor with a virtual pointer and wtype. Usage:
#   appkit-menu-dismiss-click-wayland.sh <command that runs "appkit-menu-dismiss-click <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg, wtype,
# python3, SWAYSOCK and WAYLAND_DISPLAY for the compositor, and VIRTUAL_POINTER, the path of a built
# tests/wayland-virtual-pointer.c. Set DarlingInWindowMenuBar for the guest: the titles are then in a strip
# drawn in the window, which takes the keyboard focus. A menu closed with Escape (or with a second click on its
# title) leaves the window key, the next key press reaches its first responder and the next click in the
# window reaches its view.
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
for _ in $(seq 1200); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2

geometry=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "dismiss-click-host" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"], r["y"], r["width"], r["height"])
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$geometry" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
set -- $geometry; X=$1 Y=$2 W=$3 H=$4
grep -q '^WHERE strip' "$out" || { echo "FAIL: the titles are not in a strip in the window"; cat "$out"; exit 1; }
title() { set -- $(grep "^TITLE $1 " "$out"); echo "$((X + $3)) $((Y + $4))"; }
view="$((X + W / 2)) $((Y + H / 2))"
click() {
    local clicked
    clicked=$(grep -c '^CLICKED' "$vpout")
    echo "$1 $2" >&3
    for _ in $(seq 50); do [ "$(grep -c '^CLICKED' "$vpout")" -gt "$clicked" ] && break; sleep 0.1; done
}
menus() { grep '^MENUS ' "$out" | tail -1 | cut -d' ' -f2; }
downs() { grep -c '^DOWN ' "$out"; }
wait_menus() {
    for _ in $(seq 40); do [ "$(menus)" = "$1" ] && return 0; sleep 0.1; done
    return 1
}
wait_downs() {
    for _ in $(seq 30); do [ "$(downs)" -ge "$1" ] && return 0; sleep 0.1; done
    return 1
}
status=0
expect() { # description, exit status of the condition
    if [ "$2" = 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; status=1; fi
}

set -- $(title 1); file_x=$1 file_y=$2

click $view
wait_downs 1; expect "a click in the key window reaches the view" $?
sleep 0.6
wtype -s 300 p -s 300
for _ in $(seq 30); do grep -q '^TYPED p' "$out" && break; sleep 0.1; done
grep -q '^TYPED p' "$out"; expect "a key press reaches the first responder" $?

click $file_x $file_y
wait_menus 1; expect "a click on File opens its menu" $?
sleep 0.6
# A pause on each side keeps the virtual keyboard (and its keymap) alive around the key.
wtype -s 300 -k Escape -s 300
wait_menus 0; expect "Escape closes the menu" $?
sleep 0.6
wtype -s 300 q -s 300
for _ in $(seq 30); do grep -q '^TYPED q' "$out" && break; sleep 0.1; done
grep -q '^TYPED q' "$out"; expect "the first key press after Escape reaches the first responder" $?
sleep 0.6
click $view
wait_downs 2; expect "the first click after Escape reaches the view" $?
grep -q '^DOWN 2 1$' "$out"; expect "the window is still key for that click" $?
sleep 0.6

click $file_x $file_y
wait_menus 1; expect "File opens again" $?
sleep 0.6
click $file_x $file_y
wait_menus 0; expect "a second click on File closes the menu" $?
sleep 0.6
click $view
wait_downs 3; expect "the first click after closing with the title reaches the view" $?

! grep -q '^KEY 0' "$out"; expect "the window never resigned key" $?

[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
