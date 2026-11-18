#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs ../x11-window-state/key-window.m (cross-compiled, GUEST_BIN is its path in the guest) in the
# mode given (orderfront, makekey, makefront, modal, nokey, click) against a headless sway. Needs
# sway, swaymsg, wtype, python3 and a started compositor: WAYLAND_DISPLAY (absolute socket path),
# XDG_RUNTIME_DIR and SWAYSOCK are in the environment. Mode click also needs VIRTUAL_POINTER: the
# path of a helper that creates a persistent wlr-virtual-pointer on the seat, prints READY, and for
# each "x y" line on stdin moves the pointer there (output coordinates), clicks the left button and
# prints CLICKED (sway's own "seat cursor" commands need a pointer device, which a headless sway
# lacks). Exit status 0 when the guest prints DONE.
set -euo pipefail
mode=${1:?orderfront, makekey, makefront, modal, nokey or click}
temp=$(mktemp -d)
kb=
trap 'kill "$kb" 2>/dev/null || true; rm -rf "$temp"' EXIT
DARLING_APPKIT_BACKEND=wayland timeout -s KILL 120 darling shell "${GUEST_BIN:?guest path of the test}" "$mode" 14 \
    </dev/null >"$temp/guest.log" 2>&1 &
for _ in $(seq 1 300); do
    grep -q -E '^(READY|DONE|FAILED)' "$temp/guest.log" && break
    sleep 0.2
done
grep -q -E '^(READY|DONE|FAILED)' "$temp/guest.log" || { echo "FAIL: guest never printed READY"; cat "$temp/guest.log"; exit 1; }
if [ "$mode" = orderfront ]; then
    # The compositor's focus goes to the visible window, the keys are typed there.
    swaymsg '[title="kw-b"] focus' >/dev/null
    wtype -k Shift_L -s 9000 -k Shift_L &
    kb=$!
    sleep 1
    wtype -s 100 abc
elif [ "$mode" = click ]; then
    swaymsg -t get_tree >"$temp/tree.json"
    read -r x y < <(python3 - "$temp/tree.json" <<'PY'
import json, sys
def walk(n):
    if n.get("name") == "kw-b":
        r = n["rect"]; print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2); sys.exit(0)
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        walk(c)
walk(json.load(open(sys.argv[1])))
sys.exit(1)
PY
)
    mkfifo "$temp/pointer"
    "${VIRTUAL_POINTER:?path of the virtual pointer helper}" <"$temp/pointer" >"$temp/pointer.log" 2>&1 &
    vp=$!
    exec 3>"$temp/pointer"
    for _ in $(seq 1 50); do
        grep -q READY "$temp/pointer.log" && break
        sleep 0.2
    done
    echo "$x $y" >&3
    for _ in $(seq 1 50); do
        grep -q CLICKED "$temp/pointer.log" && break
        sleep 0.2
    done
    exec 3>&-
    kill "$vp" 2>/dev/null || true
fi
for _ in $(seq 1 200); do
    grep -q -E '^(DONE|FAILED)' "$temp/guest.log" && break
    sleep 0.2
done
cat "$temp/guest.log"
grep -q '^DONE' "$temp/guest.log"
