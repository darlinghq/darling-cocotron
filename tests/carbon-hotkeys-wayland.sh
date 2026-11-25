#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of carbon-hotkeys-focused on Wayland: types the keys of its header comment into the window
# "carbon-hotkeys-focused". Usage:
#   HOTKEY_COMPOSITOR=sway|kwin HOTKEY_KEYS=<injector> carbon-hotkeys-wayland.sh <command that runs carbon-hotkeys-focused>
# $WAYLAND_DISPLAY and $XDG_RUNTIME_DIR name the compositor. The keys come from the injector, which takes a
# pause in milliseconds and evdev key codes with 1 or 0 for press and release: virtual-keyboard-keys.c on sway
# (a headless sway whose windows float, named by $SWAYSOCK; needs swaymsg) and kwin-keys.c on KWin (a private
# kwin_wayland --virtual); both are built as their headers describe. Caps Lock is only typed when HOTKEY_CAPS
# is set, which the command has to pass to the program, too.
set -u
mode=${HOTKEY_COMPOSITOR:-sway}
: "${HOTKEY_KEYS:?the key injector}"
work=$(mktemp -d)
out=$work/out
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$work"' EXIT

for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
[ "$mode" = sway ] && swaymsg -q '[title="carbon-hotkeys-focused"] focus'
sleep 0.5

# evdev codes: A 30, B 48, Q 16, F5 63, Left Control 29, Left Shift 42, Caps Lock 58
K() { "$HOTKEY_KEYS" 100 "$@"; }
K 29:1 30:1 30:0 29:0; sleep 0.3
K 29:1 42:1 30:1 30:0 42:0 29:0; sleep 0.3
K 63:1 63:0; sleep 0.3
K 30:1 30:0; sleep 0.3
if [ -n "${HOTKEY_CAPS:-}" ]; then
    K 58:1 58:0 29:1 30:1 30:0 29:0 58:1 58:0; sleep 0.3
fi
K 29:1 30:1 w1300 30:0 29:0; sleep 0.3
K 48:1 48:0; sleep 0.3
K 29:1 30:1 30:0 29:0; sleep 0.3
K 29:1 42:1 30:1 30:0 42:0 29:0; sleep 0.3
K 16:1 16:0

for _ in $(seq 300); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
