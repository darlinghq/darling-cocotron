#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# The Wayland counterpart of appkit-state-queries-x11.sh: a virtual pointer (tests/wayland-virtual-pointer.c, in
# $VIRTUAL_POINTER) and wtype's virtual keyboard. $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and $SWAYSOCK must name a
# headless sway (darling-skills' wayland.sh) whose windows float. Usage:
#   appkit-state-queries-wayland.sh <command that runs appkit-state-queries>
# Needs swaymsg, wtype and python3.
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
    for _ in $(seq 400); do grep -q "^$1" "$2" && return 0; sleep 0.1; done
    echo "FAIL: no $1"; cat "$out"; exit 1
}
waitfor READY "$vpout"
waitfor READY "$out"
sleep 2
swaymsg -q '[title="state-queries"] move position 200 200, focus'
sleep 0.5
middle=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "state-queries" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$middle" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
set -- $middle
echo "move $(($1 - 20)) $2" >&3
sleep 0.2
echo "move $1 $2" >&3
waitfor PHASE2 "$out"
sleep 0.3
# The keyboard is new to the seat: the client binds it during the pause, then gets the key; Shift stays down for
# the pause of the second wtype.
wtype -M shift -s 4000 -m shift &
wt=$!
sleep 1
echo "button 272 1" >&3
waitfor PHASE3 "$out"
sleep 0.3
echo "button 272 0" >&3
wait $wt
waitfor PHASE4 "$out"
sleep 0.3
echo "move 5 5" >&3
for _ in $(seq 200); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
