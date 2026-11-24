#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-menu-dismiss-click.m with XTest (xdotool) on $DISPLAY. Usage:
#   appkit-menu-dismiss-click-x11.sh <command that runs "appkit-menu-dismiss-click <seconds>">
# Needs xdotool. A main-menu-bar menu opened with a click and closed with Escape (or with a second
# click on its title) leaves the window key, the next key press reaches its first responder and the
# next click in the window reaches its view.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

for _ in $(seq 1200); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
view=$(grep '^VIEW ' "$out" | cut -d' ' -f2-)
TX=0 TY=0
if grep -q '^WHERE strip' "$out"; then
    id=$(xdotool search --name '^dismiss-click-host$' | head -1)
    [ -n "$id" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
    eval "$(xdotool getwindowgeometry --shell "$id")"
    TX=$X TY=$Y
fi
title() { set -- $(grep "^TITLE $1 " "$out"); echo "$((TX + $3)) $((TY + $4))"; }

click() { xdotool mousemove "$1" "$2"; sleep 0.3; xdotool mousedown 1; sleep 0.08; xdotool mouseup 1; }
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
expect() { # description, condition result
    if [ "$2" = 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; status=1; fi
}

set -- $(title 1); file_x=$1 file_y=$2

click $view
wait_downs 1; expect "a click in the key window reaches the view" $?
sleep 0.6
xdotool key p
for _ in $(seq 30); do grep -q '^TYPED p' "$out" && break; sleep 0.1; done
grep -q '^TYPED p' "$out"; expect "a key press reaches the first responder" $?

click $file_x $file_y
wait_menus 1; expect "a click on File opens its menu" $?
sleep 0.6
xdotool key Escape
wait_menus 0; expect "Escape closes the menu" $?
sleep 0.6
xdotool key q
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

kill $pid 2>/dev/null
wait $pid 2>/dev/null
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
