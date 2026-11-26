#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of cursor-scale: moves a virtual pointer (the helper tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER) into
# the window of cursor-scale, changes the output scale of a headless sway to 1 when the program asks (WAIT-RESCALE) and
# checks the cursor requests of the program's WAYLAND_DEBUG=client output with cursor-scale-check.py.
# $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and $SWAYSOCK must name a headless sway whose windows float, started with the output
# scale given first. Usage:
#   cursor-scale.sh <output scale> <command that runs cursor-scale with WAYLAND_DEBUG=client set in the guest>
# Needs swaymsg and python3.
set -u
scale=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
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
for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; head -20 "$out"; exit 1; }
sleep 2
swaymsg -q '[title="Cursor scale fixture"] move position 200 200, focus'
sleep 0.5
center=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "Cursor scale fixture" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$center" ] || { echo "FAIL: the window is not on screen"; exit 1; }
# The helper moves the pointer in output pixels, a sway layout is in logical units.
awk -v x="${center% *}" -v y="${center#* }" -v s="$scale" 'BEGIN { printf "abs %d %d\n", x * s, y * s }' >&3
for _ in $(seq 600); do grep -q '^WAIT-RESCALE' "$out" && break; sleep 0.1; done
grep -q '^WAIT-RESCALE' "$out" || { echo "FAIL: the program never asked for the rescale"; tail -20 "$out"; exit 1; }
sleep 1
swaymsg -q 'output * scale 1'
for _ in $(seq 700); do grep -q '^\(DONE\|STAGE rescale-timeout\)' "$out" && break; sleep 0.1; done
grep -q '^DONE' "$out" || { echo "FAIL: the program did not finish"; grep '^STAGE' "$out"; exit 1; }
grep '^STAGE' "$out"
python3 -I "$here/cursor-scale-check.py" "$out" "$scale"
