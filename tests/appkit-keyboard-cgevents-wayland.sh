#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-keyboard-cgevents on Wayland: types with a virtual keyboard (wtype) into the window
# "kbd-cgevents". $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and $SWAYSOCK must name a headless sway whose windows
# float. Usage:
#   appkit-keyboard-cgevents-wayland.sh <command that runs appkit-keyboard-cgevents>
# Needs swaymsg and wtype.
set -u
work=$(mktemp -d)
out=$work/out
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
swaymsg -q '[title="kbd-cgevents"] focus'
sleep 0.5

# Every wtype run is a new virtual keyboard: the seat gains the keyboard capability, the client binds the
# keyboard during the pause, then gets the keys (a key sent before that comes as a key held at the enter)
wtype -s 300 a
sleep 0.3
wtype -s 300 -M shift a -m shift
sleep 0.3
wtype -s 300 -M ctrl a -m ctrl
sleep 0.3
wtype -s 300 -P s -s 1200 -p s
sleep 0.3
wtype -s 300 d
sleep 0.3
# the keysym of Shift+Tab on a PC keyboard: xkbcommon gives no text for it
wtype -s 300 -M shift -k ISO_Left_Tab -m shift
sleep 0.3
wtype -s 300 q

for _ in $(seq 300); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
