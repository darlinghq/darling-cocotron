#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Display reconfiguration reported for a change another client of the window system makes. Runs the
# guest test coregraphics-displays-without-appkit in its "external" mode, which prints READY1, waits
# for a change of the main display's mode and prints READY2, waits for it to be restored.
# On X11 the mode is changed with xrandr on a private Xvfb (the added mode is kept by tests/x11-add-modes.c,
# see coregraphics-display-mode-switch.sh); on Wayland swaymsg changes the mode of a headless sway output.
#
# Usage: BACKEND=x11 coregraphics-displays-external-change.sh <guest test command>
#        BACKEND=wayland WAYLAND_DISPLAY=... SWAYSOCK=... coregraphics-displays-external-change.sh <guest test command>
# On X11 the script starts its own Xvfb; on Wayland it uses the running sway named by SWAYSOCK and
# changes the mode of its first output (restored afterwards).
# The command is run with DISPLAY or the Wayland variables set, CG_TEST_MODE=1024x600, and "external" appended.
set -u
backend=${BACKEND:-x11}
work=$(mktemp -d)
xvfb_pid=
modes_pid=
test_pid=
cleanup() {
    [ -n "$test_pid" ] && kill "$test_pid" 2>/dev/null
    [ -n "$modes_pid" ] && kill "$modes_pid" 2>/dev/null
    [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
here=$(cd "$(dirname "$0")" && pwd)

if [ "$backend" = x11 ]; then
    for tool in Xvfb xrandr cc; do
        command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
    done
    Xvfb -screen 0 1280x720x24 -displayfd 3 3> "$work/display" > "$work/xvfb.log" 2>&1 &
    xvfb_pid=$!
    for _ in $(seq 50); do [ -s "$work/display" ] && break; sleep 0.1; done
    [ -s "$work/display" ] || { echo "Xvfb did not start" >&2; exit 2; }
    export DISPLAY=:$(head -n 1 "$work/display")
    cc -Wall -o "$work/add-modes" "$here/x11-add-modes.c" -lX11 -lXrandr || exit 2
    "$work/add-modes" 1024x600 > "$work/modes.log" &
    modes_pid=$!
    for _ in $(seq 50); do grep -q READY "$work/modes.log" && break; sleep 0.1; done
    grep -q READY "$work/modes.log" || { echo "could not add modes" >&2; exit 2; }
    output=$(xrandr | awk '/ connected/ { print $1; exit }')
    original=$(xrandr | awk '/ connected/ { f = 1; next } f && /\*/ { print $1; exit }')
    change() { xrandr --output "$output" --mode "$1"; }
    new=1024x600_60
else
    command -v swaymsg >/dev/null || { echo "need swaymsg" >&2; exit 2; }
    output=$(swaymsg -t get_outputs -r | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["name"])')
    original=$(swaymsg -t get_outputs -r | python3 -c 'import json,sys; m=json.load(sys.stdin)[0]["current_mode"]; print("%dx%d" % (m["width"], m["height"]))')
    change() { swaymsg output "$output" resolution "$1" > /dev/null; }
    new=1024x600
fi
[ -n "$output" ] && [ -n "$original" ] || { echo "no active output" >&2; exit 2; }

CG_TEST_MODE=1024x600 "$@" external > "$work/log" 2>&1 &
test_pid=$!
wait_for() {
    for _ in $(seq 1 300); do
        grep -q "$1" "$work/log" && return 0
        sleep 0.2
    done
    echo "timed out waiting for $1" >&2
    return 1
}
fail=0
wait_for READY1 && change "$new" || fail=1
wait_for READY2 && change "$original" || fail=1
wait "$test_pid"; status=$?
test_pid=
cat "$work/log"
[ $status = 0 ] || fail=1
change "$original" 2>/dev/null
[ $fail = 0 ] && grep -q '^PASS' "$work/log" && echo "PASS ($backend external change)" || { echo FAIL; exit 1; }
