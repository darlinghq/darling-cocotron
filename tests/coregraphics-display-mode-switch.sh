#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Display mode switching on X11 (RandR). Starts a private Xvfb, which has only the one mode
# its -screen option gives, adds two more with tests/x11-add-modes.c, which stays connected while the test runs (the server
# deletes a client's modes when it disconnects, so xrandr --newmode / --addmode cannot keep them; a
# client can only switch to a mode the output lists), runs the guest test coregraphics-display-mode-switch
# against it and checks, with xrandr, that the test left the display in its original mode, also
# when the process exits without releasing the display.
#
# Xvfb's RandR allows screen sizes up to the size of its -screen, so the added modes are smaller.
# Never point this at a real session: it changes the mode of the display it is given.
#
# Usage: coregraphics-display-mode-switch.sh <guest test command, e.g. "darling /path/to/coregraphics-display-mode-switch">
# The command is run with DISPLAY set to the private Xvfb and CG_TEST_MODE=1024x600.
set -u
work=$(mktemp -d)
xvfb_pid=
modes_pid=
cleanup() {
    [ -n "$modes_pid" ] && kill "$modes_pid" 2>/dev/null
    [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
for tool in Xvfb xrandr; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done

Xvfb -screen 0 1280x720x24 -displayfd 3 3> "$work/display" > "$work/xvfb.log" 2>&1 &
xvfb_pid=$!
for _ in $(seq 50); do [ -s "$work/display" ] && break; sleep 0.1; done
[ -s "$work/display" ] || { echo "Xvfb did not start" >&2; exit 2; }
export DISPLAY=:$(head -n 1 "$work/display")

command -v cc >/dev/null || { echo "need cc" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
cc -Wall -o "$work/add-modes" "$here/x11-add-modes.c" -lX11 -lXrandr || exit 2
"$work/add-modes" 1024x600 800x480 > "$work/modes.log" &
modes_pid=$!
for _ in $(seq 50); do grep -q READY "$work/modes.log" && break; sleep 0.1; done
grep -q READY "$work/modes.log" || { echo "could not add modes" >&2; exit 2; }

current() { xrandr | awk '/ connected/ {sub(/\+.*/, "", $3); print $3; exit}'; }
[ "$(current)" = 1280x720 ] || { echo "unexpected starting mode $(current)" >&2; exit 2; }

fail=0
CG_TEST_MODE=1024x600 "$@" || fail=1
[ "$(current)" = 1280x720 ] || { echo "FAIL: the display is $(current) after the test, not 1280x720"; fail=1; }

# Leaving the process without releasing restores the mode too.
CG_TEST_MODE=1024x600 "$@" exit || fail=1
[ "$(current)" = 1280x720 ] || { echo "FAIL: the display is $(current) after exit, not 1280x720"; fail=1; }

[ $fail = 0 ] && echo PASS || { echo FAIL; exit 1; }
