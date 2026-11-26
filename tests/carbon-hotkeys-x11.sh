#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of carbon-hotkeys-focused on X11: types the keys of its header comment with XTest (xdotool) on
# $DISPLAY, which needs a window manager, after the window "carbon-hotkeys-focused" has the keyboard focus.
# Usage: carbon-hotkeys-x11.sh <command that runs carbon-hotkeys-focused>
set -u
work=$(mktemp -d)
out=$work/out
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1.5
win=$(xdotool search --name '^carbon-hotkeys-focused$' | head -1)
[ -n "$win" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
xdotool windowactivate --sync "$win" 2>/dev/null
xdotool windowfocus --sync "$win" 2>/dev/null
sleep 0.5

key() { xdotool "$@"; sleep 0.3; }
D="--delay 120"
key keydown --delay 120 ctrl keydown --delay 120 a keyup --delay 120 a keyup ctrl
key keydown ctrl keydown shift keydown a keyup a keyup shift keyup ctrl
key key $D F5
key key $D a
if [ -n "${HOTKEY_CAPS:-}" ]; then
    key key Caps_Lock keydown ctrl keydown a keyup a keyup ctrl key Caps_Lock
fi
xdotool keydown ctrl keydown a; sleep 1.3; xdotool keyup a keyup ctrl; sleep 0.3
key key $D b
key keydown ctrl keydown a keyup a keyup ctrl
key keydown ctrl keydown shift keydown a keyup a keyup shift keyup ctrl
key key $D q

for _ in $(seq 300); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
