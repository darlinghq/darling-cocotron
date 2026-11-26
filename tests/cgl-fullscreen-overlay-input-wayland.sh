#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/cgl-fullscreen-overlay-input.m on a Wayland compositor: a virtual pointer (the helper
# tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER; it takes absolute positions on a 1920x1080 extent, which
# the compositor maps onto its layout) and a virtual keyboard (wtype). KWin has neither: with KWIN=1 the input
# comes from the injector tests/kwin-keys.c (in $KWIN_KEYS, KWin's fake input protocol). $WAYLAND_DISPLAY and
# $XDG_RUNTIME_DIR must name a headless compositor with one output. Usage:
#   cgl-fullscreen-overlay-input-wayland.sh <command that runs cgl-fullscreen-overlay-input>
# for example: cgl-fullscreen-overlay-input-wayland.sh darling shell env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY=$WAYLAND_DISPLAY /path/cgl-fullscreen-overlay-input
set -u
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
vp= kwpid=
if [ -z "${KWIN:-}" ]; then
    pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
    mkfifo "$work/fifo"
    "$pointer" < "$work/fifo" > "$vpout" 2>&1 &
    vp=$!
    exec 3> "$work/fifo"
fi
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&- 4>&-; kill $pid $vp $kwpid 2>/dev/null; rm -rf "$work"' EXIT

waitfor() {
    for _ in $(seq 400); do grep -q "^$1" "$out" && return 0; sleep 0.1; done
    echo "FAIL: no $1"; cat "$out"; exit 1
}
n=0
V() {
    echo "$*" >&3
    n=$((n + 1))
    for _ in $(seq 300); do [ "$(wc -l < "$vpout")" -gt "$n" ] && return; sleep 0.02; done
}
# On KWin one injector process lives for the whole run: the pointer and keyboard KWin makes for its input go
# away with it, and so would the pointer's focus.
if [ -n "${KWIN:-}" ]; then
    mkfifo "$work/kwfifo"
    "${KWIN_KEYS:?path of the built kwin-keys}" 20 < "$work/kwfifo" > "$work/kwout" 2>&1 &
    kwpid=$!
    exec 4> "$work/kwfifo"
fi
kw() {
    local want=$(( $(grep -c DONE "$work/kwout") + $# ))
    for e in "$@"; do echo "$e" >&4; done
    for _ in $(seq 300); do [ "$(grep -c DONE "$work/kwout")" -ge "$want" ] && return; sleep 0.02; done
}
# A point of the display (its pixels, y down); the helper wants it in its 1920x1080 extent
abs() {
    if [ -n "${KWIN:-}" ]; then kw "a$1,$2"; else V "abs $(( ($1) * 1920 / W )) $(( ($2) * 1080 / H ))"; fi
}
click() {
    if [ -n "${KWIN:-}" ]; then kw b272:1 b272:0; else V "button 272 1"; V "button 272 0"; fi
}
wheel_up() { if [ -n "${KWIN:-}" ]; then kw v-15; else V "wheel 0 -1"; fi; }
rel() { if [ -n "${KWIN:-}" ]; then kw "r$1,$2"; else V "rel $1 $2"; fi; }
# A key: <evdev code> <character>. Every wtype run is a new virtual keyboard, which the client binds during the
# pause before the key.
key() {
    if [ -n "${KWIN:-}" ]; then kw "$1:1" "$1:0"; else wtype -s 500 "$2"; fi
}

if [ -z "${KWIN:-}" ]; then
    for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
    grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
fi
waitfor 'READY\|SKIP'
if grep -q '^SKIP' "$out"; then cat "$out"; exit 0; fi
read -r _ X Y W H < <(grep '^READY' "$out")
sleep 1.5
abs $((X + 100)) $((Y + 100))
sleep 0.3
abs $((X + 200)) $((Y + 150))
waitfor PHASE2
sleep 0.3
abs $((X + 230)) $((Y + 130))
waitfor PHASE3
sleep 0.3
# a double click, then (after the double-click interval) a single one
click; click
sleep 2.5
click
sleep 0.3
key 30 a
sleep 0.3
wheel_up
waitfor PHASE4
sleep 0.5
rel 12 5
for _ in $(seq 200); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
