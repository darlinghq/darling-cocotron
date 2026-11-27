#!/bin/bash
# Copyright (C) 2026 Darling Developers
#
# Licensed under the MIT license, the same as the rest of this project.
#
# Drives tests/clipboardtest.m on a private headless sway: types the fixture's keys with wtype and checks the
# result both ways through the compositor's clipboard (wl-copy / wl-paste are the host's clients):
#  1. "c" copies the text of CLIPBOARD_INPUT: wl-paste reads it back;
#  2. the host copies other text, "p" pastes it into CLIPBOARD_RESULT;
#  3. "u" asks for a type nobody offered and gets nil, "e" clears the clipboard, "q" quits.
# Every key is typed with "wtype -s 200". wtype makes a virtual keyboard for each run and removes it when it
# exits, and a client only gets a wl_keyboard (and the keymap) once the seat announces the new keyboard, so a key
# typed without the pause is gone before the client can see it. That is how a compositor treats a client that
# has no keyboard yet; it is not a fault of the window.
# Needs sway, swaymsg, wtype, wl-copy and wl-paste. Nothing of the running desktop session is used or touched.
#   clipboardtest.sh <runner> <guest binary>
# <runner> is the command that runs a guest command (for example "darling shell"); the guest binary is the host
# path of a program built from clipboardtest.m, run as <runner> env VAR=... /Volumes/SystemRoot<path>.
set -u
runner=${1:-}
binary=${2:-}
[ -n "$runner" ] && [ -n "$binary" ] || { echo "usage: $0 <runner> <guest binary>" >&2; exit 2; }
guest_root=${GUEST_ROOT:-/Volumes/SystemRoot}
# A Wayland socket path is limited to 107 bytes: keep the directory short.
work=$(mktemp -d)
sway_pid=
guest_pid=
cleanup() {
    [ -n "$guest_pid" ] && kill "$guest_pid" 2>/dev/null
    [ -n "$sway_pid" ] && kill "$sway_pid" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
for tool in sway swaymsg wtype wl-copy wl-paste; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done

mkdir -m 700 "$work/run"
printf 'default_border none\nfor_window [shell=".*"] floating enable\n' > "$work/sway.conf"
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK I3SOCK
export XDG_RUNTIME_DIR="$work/run" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
sway -c "$work/sway.conf" > "$work/sway.log" 2>&1 &
sway_pid=$!
socket=
for _ in $(seq 100); do
    socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | head -n 1)
    [ -n "$socket" ] && [ -n "$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null)" ] && break
    sleep 0.1
done
[ -n "$socket" ] || { cat "$work/sway.log"; echo "sway did not start" >&2; exit 2; }
export WAYLAND_DISPLAY="$socket" SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock)

printf 'darling-clipboard-text' > "$work/in.txt"
$runner env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$WAYLAND_DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    CLIPBOARD_INPUT="$guest_root$work/in.txt" CLIPBOARD_RESULT="$guest_root$work/result.txt" \
    "$guest_root$binary" > "$work/guest.out" 2>&1 < /dev/null &
guest_pid=$!
for _ in $(seq 240); do
    grep -q '^clipboard ready' "$work/guest.out" && break
    kill -0 "$guest_pid" 2>/dev/null || break
    sleep 0.25
done
grep -q '^clipboard ready' "$work/guest.out" || { cat "$work/guest.out"; echo "FAIL: the fixture did not start" >&2; exit 1; }
sleep 1 # let the window finish its first frame

status=0
check() { if [ "$2" = 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; status=1; fi; }
waitfor() { for _ in $(seq 40); do grep -q "$1" "$work/guest.out" && return 0; sleep 0.25; done; return 1; }
press() { wtype -s 200 "$1"; }

press c
waitfor '^copy 1'; check "the key reaches the window and the copy succeeds" $?
got=$(timeout 5 wl-paste -n 2>/dev/null)
[ "$got" = darling-clipboard-text ]; check "the host reads what the window copied" $?

printf 'host-clipboard-text' | wl-copy
sleep 0.5
press p
waitfor '^paste 1'; check "the window pastes what the host copied" $?
[ "$(cat "$work/result.txt" 2>/dev/null)" = host-clipboard-text ]; check "the pasted data is the host text" $?

press u
waitfor '^unsupported nil=1'; check "a type nobody offered gives nil" $?

press e
waitfor '^cleared'; check "the window clears the clipboard" $?

press q
waitfor '^exiting'; check "the window handles the last key" $?
[ "$status" = 0 ] && echo PASS || echo FAIL
exit "$status"
