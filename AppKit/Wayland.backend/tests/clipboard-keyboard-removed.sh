#!/bin/bash
# Copyright (C) 2026 Darling Developers
#
# Licensed under the MIT license, the same as the rest of this project.
#
# A copy reaches the compositor's clipboard at once even when the seat loses its keyboard right after
# the key that made it. Runs tests/clipboard-fresh (a guest program: each "c" copies "fresh-<n>")
# against a private headless sway and types each "c" with wtype, whose virtual keyboard is removed
# from the seat when it exits, a few milliseconds after the key. After every key the clipboard, read
# with wl-paste, must hold the new string within CLIPBOARD_BUDGET_MS (200 by default); 20 rounds.
# wtype is given 200 ms (-s) after it creates its keyboard, so that the client has bound it before the key; without it
# the key can be gone before the client has a keyboard, and the guest never sees it.
# Needs sway, swaymsg, wtype and wl-paste (wl-clipboard). wtype writes its keymap to /tmp, so /tmp must
# have room. Nothing of the running desktop is used. A manual fixture, not run by CI.
#
# Build the guest program inside a Darling guest, like the other fixtures here:
#   clang -o clipboard-fresh clipboard-fresh.m -framework AppKit -framework Foundation
#
# Usage: clipboard-keyboard-removed.sh <command that runs the guest binary, such as "darling /path/clipboard-fresh">
# The command is run with XDG_RUNTIME_DIR, WAYLAND_DISPLAY and DARLING_APPKIT_BACKEND=wayland set.
set -u
rounds=20
budget_ms=${CLIPBOARD_BUDGET_MS:-200}
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
for tool in sway swaymsg wtype wl-paste; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done

mkdir -m 700 "$work/run"
printf 'default_border none\n' > "$work/sway.conf"
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
export WAYLAND_DISPLAY=$(basename "$socket") SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock)

DARLING_APPKIT_BACKEND=wayland "$@" > "$work/guest.out" 2>&1 < /dev/null &
guest_pid=$!
for _ in $(seq 1200); do
    swaymsg -t get_tree 2>/dev/null | grep -q '"pid":' && break
    kill -0 "$guest_pid" 2>/dev/null || break
    sleep 0.25
done
swaymsg -t get_tree 2>/dev/null | grep -q '"pid":' || { cat "$work/guest.out"; echo "the guest window did not appear" >&2; exit 2; }
sleep 5 # let the window finish its first frame
# The only window fills the output: a click anywhere gives it the keyboard focus.
swaymsg seat seat0 cursor set 200 200 >/dev/null
swaymsg seat seat0 cursor press button1 >/dev/null
swaymsg seat seat0 cursor release button1 >/dev/null
swaymsg '[title="Wayland clipboard freshness"] focus' >/dev/null
sleep 1

ms() { echo $(( $(date +%s%N) / 1000000 )); }
failures=0
for n in $(seq "$rounds"); do
    want="fresh-$n"
    wtype -s 200 c
    start=$(ms)
    got=
    while :; do
        got=$(timeout 2 wl-paste -n 2>/dev/null)
        [ "$got" = "$want" ] && break
        [ $(( $(ms) - start )) -gt "$budget_ms" ] && break
        sleep 0.02
    done
    elapsed=$(( $(ms) - start ))
    if [ "$got" = "$want" ]; then echo "PASS: round $n: $want after ${elapsed} ms"
    else
        grep -Eq "copied $want([^0-9]|$)" "$work/guest.out" && copied="the guest copied it" || copied="the guest did not report the copy"
        echo "FAIL: round $n: clipboard holds '$got', expected '$want' within $budget_ms ms ($copied)"
        failures=$((failures + 1))
    fi
done
wtype -s 200 q
[ "$failures" = 0 ] && echo "PASS: $rounds copies reached the clipboard in time" || echo "FAIL: $failures of $rounds copies were late"
[ "$failures" = 0 ]
