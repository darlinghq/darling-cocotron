#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/cgl-fullscreen-overlay-input.m on a Wayland compositor: a virtual pointer (the helper
# tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER; it takes absolute positions on a 1920x1080 extent, which
# the compositor maps onto its layout) and a virtual keyboard (wtype, or on KWin, which has none, the key injector
# tests/kwin-keys.c in $KWIN_KEYS with KWIN=1). $WAYLAND_DISPLAY and $XDG_RUNTIME_DIR must name a headless
# compositor with one output. Usage:
#   cgl-fullscreen-overlay-input-wayland.sh <command that runs cgl-fullscreen-overlay-input>
# for example: cgl-fullscreen-overlay-input-wayland.sh darling shell env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY=$WAYLAND_DISPLAY /path/cgl-fullscreen-overlay-input
set -u
pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
mkfifo "$work/fifo"
"$pointer" < "$work/fifo" > "$vpout" 2>&1 &
vp=$!
exec 3> "$work/fifo"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$work"' EXIT

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
# A point of the display (its pixels, y down), as the helper wants it: in its 1920x1080 extent
abs() { V "abs $(( ($1) * 1920 / W )) $(( ($2) * 1080 / H ))"; }
# A key: <evdev code> <character>. Every wtype run is a new virtual keyboard, which the client binds during the
# pause before the key.
key() {
    if [ -n "${KWIN:-}" ]; then "${KWIN_KEYS:?path of the built kwin-keys}" 50 "$1:1" "$1:0"; else wtype -s 500 "$2"; fi
}

for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
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
V "button 272 1"; V "button 272 0"; V "button 272 1"; V "button 272 0"
sleep 2.5
V "button 272 1"; V "button 272 0"
sleep 0.3
key 30 a
sleep 0.3
V "wheel 0 -1"
waitfor PHASE4
sleep 0.5
V "rel 12 5"
for _ in $(seq 200); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
