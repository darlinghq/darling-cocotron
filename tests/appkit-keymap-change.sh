#!/bin/bash
# Copyright (C) 2026 Lubos Dolezel
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Driver of the guest test appkit-keymap-change: the keymap of the window system changes
# us -> de -> us, and after each change the physical key that is Y on a US keyboard is typed.
#   X11:     setxkbmap changes the keymap of the server in DISPLAY, xdotool types the key (as the
#            keysym that the keymap has on it: y with us, z with de).
#   Wayland: wayland-keymap-switch (built here from wayland-keymap-switch.c) gives the keymap of the
#            seat's virtual keyboard a new layout and types KEY_Y. Needs the compositor named by
#            WAYLAND_DISPLAY / XDG_RUNTIME_DIR (a headless sway).
#
# Usage: appkit-keymap-change.sh <x11|wayland> <command that runs a guest program, e.g. run1.sh x11 90> <guest test>
set -u
backend=$1; shift
work=$(mktemp -d)
here=$(cd "$(dirname "$0")" && pwd)
test_pid= helper_pid=
cleanup() {
    [ -n "$test_pid" ] && kill "$test_pid" 2>/dev/null
    [ -n "$helper_pid" ] && kill "$helper_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

if [ "$backend" = x11 ]; then
    for tool in setxkbmap xdotool; do command -v $tool >/dev/null || { echo "need $tool" >&2; exit 2; }; done
    original=$(setxkbmap -query | awk '/^layout:/ { print $2 }')
    layout() { setxkbmap "$1"; }
    typekey() { case $1 in us) xdotool key --delay 100 y;; *) xdotool key --delay 100 z;; esac; }
    restore() { setxkbmap "${original:-us}"; }
else
    for tool in wayland-scanner cc; do command -v $tool >/dev/null || { echo "need $tool" >&2; exit 2; }; done
    wayland-scanner client-header "$here/wayland-virtual-keyboard.xml" "$work/virtual-keyboard-client.h" &&
        wayland-scanner private-code "$here/wayland-virtual-keyboard.xml" "$work/virtual-keyboard-protocol.c" &&
        cc -Wall -I"$work" -o "$work/switch" "$here/wayland-keymap-switch.c" "$work/virtual-keyboard-protocol.c" \
            -lwayland-client -lxkbcommon || { echo "cannot build the fixture" >&2; exit 2; }
    mkfifo "$work/commands"
    "$work/switch" < "$work/commands" > "$work/helper.log" 2>&1 &
    helper_pid=$!
    exec 3> "$work/commands"
    for _ in $(seq 50); do grep -q KEYBOARD_READY "$work/helper.log" && break; sleep 0.1; done
    grep -q KEYBOARD_READY "$work/helper.log" || { echo "no virtual keyboard"; cat "$work/helper.log"; exit 2; }
    # Commands are answered with DONE lines; waiting for them keeps the order.
    command_done=0
    send() {
        echo "$1" >&3
        command_done=$((command_done + 1))
        for _ in $(seq 100); do [ "$(grep -c '^DONE' "$work/helper.log")" -ge $command_done ] && return; sleep 0.1; done
    }
    layout() { send "layout $1"; }
    typekey() { send "key 21"; }
    restore() { :; }
fi

"$@" y z y > "$work/log" 2>&1 &
test_pid=$!
wait_for() {
    for _ in $(seq 1 300); do grep -q "^$1\$" "$work/log" && return 0; sleep 0.2; done
    echo "timed out waiting for $1" >&2
    return 1
}
fail=0
wait_for READY1 && { sleep 0.5; layout us; typekey us; } || fail=1
wait_for READY2 && { sleep 0.5; layout de; typekey de; } || fail=1
wait_for READY3 && { sleep 0.5; layout us; typekey us; } || fail=1
wait "$test_pid"; status=$?
test_pid=
cat "$work/log"
restore
[ $status = 0 ] || fail=1
[ $fail = 0 ] && grep -q '^PASS' "$work/log" && echo "PASS ($backend keymap change)" || { echo FAIL; exit 1; }
