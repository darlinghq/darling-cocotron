#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of cursor-callback: moves a virtual pointer (the helper tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER) into
# the window "Cursor callback fixture" and prints the verdict of the program (its RESULT line decides the exit status).
# $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and $SWAYSOCK must name a headless sway whose windows float; with KWIN set the input comes
# from KWin's fake input protocol (the injector in $KWIN_KEYS) and the pointer visits the display until the program has it.
# Usage:
#   cursor-callback.sh <command that runs cursor-callback>
set -u
work=$(mktemp -d)
out=$work/out vpout=$work/pointer
if [ -n "${KWIN:-}" ]; then
    # KWin has no virtual pointer: the input comes from the injector tests/kwin-keys.c (in $KWIN_KEYS, KWin's fake input protocol)
    mkfifo "$work/fifo"
    "${KWIN_KEYS:?path of the built kwin-keys}" 20 < "$work/fifo" > "$vpout" 2>&1 &
else
    pointer=${VIRTUAL_POINTER:?path of the built wayland-virtual-pointer helper}
    mkfifo "$work/fifo"
    "$pointer" < "$work/fifo" > "$vpout" 2>&1 &
fi
vp=$!
exec 3> "$work/fifo"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'exec 3>&-; kill $pid $vp 2>/dev/null; rm -rf "$work"' EXIT
if [ -z "${KWIN:-}" ]; then
    for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
    grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
fi
for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; head -20 "$out"; exit 1; }
sleep 2
# The pointer may already be where the window appeared (a previous run left it there): the program has it then.
if ! grep -q '^SELECTED' "$out"; then
    if [ -n "${KWIN:-}" ]; then
        # KWin places the window itself: the pointer visits points of the display until the program has the pointer.
        for y in 360 200 520 120 650; do
            for x in 640 300 980 150 1130; do
                grep -q '^SELECTED' "$out" && break 2
                echo "a$x,$y" >&3; sleep 0.5
            done
        done
    else
        swaymsg -q '[title="Cursor callback fixture"] move position 200 200, focus'
        sleep 0.5
        center=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "Cursor callback fixture" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
        if [ -n "$center" ]; then
            echo "abs ${center% *} ${center#* }" >&3
        else
            # The program may have had the pointer meanwhile and, in its hide mode, taken the window away.
            sleep 1
            grep -q '^SELECTED' "$out" || { echo "FAIL: the window is not on screen"; head -20 "$out"; exit 1; }
        fi
    fi
fi
for _ in $(seq 400); do grep -q '^RESULT' "$out" && break; sleep 0.1; done
grep -E '^(SELECTED|CALLBACK|LIFETIME|RESULT)' "$out"
grep -q '^RESULT.*failures=0' "$out"
