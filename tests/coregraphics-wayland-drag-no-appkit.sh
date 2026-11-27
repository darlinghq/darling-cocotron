#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of coregraphics-wayland-drag-no-appkit on the headless sway named by $SWAYSOCK, $WAYLAND_DISPLAY and
# $XDG_RUNTIME_DIR (darling-skills' wayland.sh): places the program's two windows (titles cg-wl-drag-source and
# cg-wl-drag-destination), and with a virtual pointer (a program that reads "abs <x> <y>" and "button <code> <0|1>" lines
# on its standard input) presses the left button in the source window, moves the pointer over the destination window and
# releases it there, then again passing over the destination and releasing away from any window, and once more for the
# local drag. Usage:
#   coregraphics-wayland-drag-no-appkit.sh <virtual pointer> <command that runs coregraphics-wayland-drag-no-appkit>
set -u
vptr=$1; shift
work=$(mktemp -d)
out=$work/out
mkfifo "$work/ptr"
"$vptr" < "$work/ptr" > "$work/ptr.out" 2>&1 &
vpid=$!
exec 3> "$work/ptr"
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid $vpid 2>/dev/null; exec 3>&-; rm -rf "$work"' EXIT

waitfor() { for _ in $(seq 600); do grep -q "^$1" "$out" && return 0; sleep 0.1; done; return 1; }
center() { swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == sys.argv[1] and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))' "$1"; }
move() { echo "abs $1 $2" >&3; sleep 0.12; }
waitfor READY || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
swaymsg -q '[title="cg-wl-drag-source"] move position 100 100'
swaymsg -q '[title="cg-wl-drag-destination"] move position 700 100'
sleep 1

read sx sy <<< "$(center cg-wl-drag-source)"
read tx ty <<< "$(center cg-wl-drag-destination)"
status=0
for n in 1 2 3; do
    waitfor "ARMED $n" || { echo "FAIL: drag $n was never armed"; status=1; break; }
    echo "abs $sx $sy" >&3; sleep 0.5
    echo "button 272 1" >&3; sleep 0.5
    for i in 1 2 3 4 5 6 7 8 9 10; do move $((sx + (tx - sx) * i / 10)) $((sy + (ty - sy) * i / 10)); done
    sleep 0.5
    if [ $n = 2 ]; then
        for i in 1 2 3 4 5 6; do move $((tx + 40 * i)) $((ty + 25 * i)); done
        move 1500 900
        sleep 0.4
    fi
    echo "button 272 0" >&3
    waitfor "DONE $n" || { echo "FAIL: drag $n never finished"; status=1; break; }
    sleep 0.5
done

for _ in $(seq 100); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
rc=$?
cat "$out"
[ $rc -eq 0 ] || status=1
exit $status
