#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-overlay-pointer-input.m on a headless sway with a virtual pointer (the helper
# tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER; it takes absolute positions on a 1920x1080 extent, which
# the compositor maps onto its layout). KWin has no virtual pointer: with KWIN=1 the input comes from the injector
# tests/kwin-keys.c (in $KWIN_KEYS, KWin's fake input protocol), which one process keeps for the whole run.
# $WAYLAND_DISPLAY and $XDG_RUNTIME_DIR must name the compositor, which has one output. Usage:
#   appkit-overlay-pointer-input-wayland.sh <command that runs appkit-overlay-pointer-input>
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
rel() { if [ -n "${KWIN:-}" ]; then kw "r$1,$2"; else V "rel $1 $2"; fi; }

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
abs $((X + 240)) $((Y + 130))
abs $((X + 240)) $((Y + 160))
waitfor PHASE4
waitfor PHASE5
sleep 0.5
rel 12 5
for _ in $(seq 200); do grep -q -E '^(PASS|FAIL)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
