#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Checks which windows of tests/appkit-window-hidden-title-chrome.m the window manager on $DISPLAY
# frames (_NET_FRAME_EXTENTS), and that the window without a frame is where the application put it.
# Usage: appkit-window-hidden-title-chrome-x11.sh <command that runs "appkit-window-hidden-title-chrome 5">
# Needs a window manager that honours _MOTIF_WM_HINTS (xfwm4, for example), xdotool and xprop.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT

wait_for() {
    for _ in $(seq 300); do grep -q "^$1\$" "$out" && return 0; sleep 0.1; done
    echo "FAIL: the test never printed $1"; cat "$out"; exit 1
}

status=0
eval "$(xdotool getdisplaygeometry --shell)"
screen_height=$HEIGHT

check() { # phase name framed(yes|no)
    local id ext want got
    id=$(xdotool search --name "^$2\$" | head -1)
    [ -n "$id" ] || { echo "FAIL: $1 $2: no window"; status=1; return; }
    ext=$(xprop -id "$id" _NET_FRAME_EXTENTS | sed -n 's/.* = //p')
    case "$ext" in "0, 0, 0, 0") got=no;; "") got=unknown;; *) got=yes;; esac
    if [ "$got" = "$3" ]; then echo "PASS: $1 $2: framed $got ($ext)"
    else echo "FAIL: $1 $2: framed $got ($ext), expected $3"; status=1; fi
}

check_place() { # phase name requested-x requested-y height (Cocoa coordinates)
    local id
    id=$(xdotool search --name "^$2\$" | head -1)
    eval "$(xdotool getwindowgeometry --shell "$id")"
    local want_y=$((screen_height - $4 - $5))
    if [ "$X,$Y" = "$3,$want_y" ]; then echo "PASS: $1 $2: placed at $X,$Y"
    else echo "FAIL: $1 $2: placed at $X,$Y, expected $3,$want_y"; status=1; fi
}

wait_for shown
sleep 0.5
check shown hidden-all no
check_place shown hidden-all 60 500 200
check shown hidden-title yes
check shown transparent yes
check shown opaque-hidden yes
check shown late-hidden yes
# untitled resizable windows: framed only in a program built against an SDK older than 10.7
old=no; grep -q '^old-sdk 1$' "$out" && old=yes
check shown resizable $old
check shown mini-resizable $old
grep '^FAIL' "$out" && status=1
wait_for changed
sleep 0.5
check changed late-hidden no
check changed hidden-all no
grep "^win hidden-all " "$out" | head -1 | grep -q "^win hidden-all 60 500 300 200$" \
    && echo "PASS: AppKit reports hidden-all at 60,500" \
    || { echo "FAIL: AppKit reports $(grep "^win hidden-all " "$out" | head -1)"; status=1; }
wait $pid
exit $status
