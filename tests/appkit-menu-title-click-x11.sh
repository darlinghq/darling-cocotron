#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-menu-title-click.m with XTest (xdotool) on $DISPLAY. Usage:
#   appkit-menu-title-click-x11.sh <command that runs "appkit-menu-title-click <seconds>">
# Needs xdotool and a window manager on $DISPLAY. With the application's own menu bar window (the default)
# the titles are on the screen; with DarlingInWindowMenuBar set they are in the window "title-click-host".
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
X=0 Y=0
if grep -q '^WHERE strip' "$out"; then
    echo "titles: in-window strip"
    id=$(xdotool search --name '^title-click-host$' | head -1)
    [ -n "$id" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
    eval "$(xdotool getwindowgeometry --shell "$id")"
    outside="$((X + 200)) $((Y + 200))"
else
    echo "titles: menu bar window"
    outside="1700 950"
fi
title() { set -- $(grep "^TITLE $1 " "$out"); echo "$((X + $3)) $((Y + $4))"; }

click() { xdotool mousemove "$1" "$2"; sleep 0.3; xdotool mousedown 1; sleep 0.08; xdotool mouseup 1; }
menus() { grep '^MENUS ' "$out" | tail -1 | cut -d' ' -f2; }
wait_menus() {
    for _ in $(seq 40); do [ "$(menus)" = "$1" ] && return 0; sleep 0.1; done
    return 1
}
status=0
expect() { # description, condition result
    if [ "$2" = 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; status=1; fi
}

set -- $(title 1); file_x=$1 file_y=$2
set -- $(title 2); edit_x=$1 edit_y=$2

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
xdotool mousemove $edit_x $edit_y
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
xdotool mousemove $file_x $file_y; sleep 0.3
xdotool mousedown 1; sleep 0.3
for step in 1 2 3 4 5 6; do xdotool mousemove_relative 0 6; sleep 0.1; done
xdotool mouseup 1
for _ in $(seq 40); do grep -q '^CHOSE New' "$out" && break; sleep 0.1; done
grep -q '^CHOSE New' "$out"; expect "press on a title, drag to the first item, release chooses it" $?
wait_menus 0; expect "the menu is closed after the choice" $?

wait $pid
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
