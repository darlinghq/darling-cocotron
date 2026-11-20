#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-about-panel-scroller.m on a headless sway compositor with a virtual pointer: drags the
# knob of the About panel's scroller down, then clicks the track below the knob, and checks that the
# scroller's value grew each time. Usage:
#   appkit-about-panel-scroller-wayland.sh <command that runs "appkit-about-panel-scroller <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment; the command must run
# an app bundle whose Resources hold a long Credits.rtf. Needs swaymsg, python3, SWAYSOCK and WAYLAND_DISPLAY
# for the compositor, and VIRTUAL_POINTER, the path of a built tests/wayland-virtual-pointer.c.
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
for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2

pos=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "about-panel" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"], r["y"])
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$pos" ] || { echo "FAIL: no panel window"; cat "$out"; exit 1; }
set -- $pos; X=$1 Y=$2
set -- $(grep '^scroller ' "$out"); sx=$2 sy=$3 sw=$4 sh=$5 ky=$6 kh=$7
value() { grep '^VALUE ' "$out" | tail -1 | cut -d' ' -f2; }
status=0
grep '^enabled ' "$out"

x=$((X + sx + sw / 2))
v0=$(value)
y=$((Y + ky + kh / 2))
dragged=$(grep -c '^DRAGGED' "$vpout")
echo "drag $x $y 0 40" >&3
for _ in $(seq 100); do [ "$(grep -c '^DRAGGED' "$vpout")" -gt "$dragged" ] && break; sleep 0.1; done
sleep 1
v1=$(value)
if awk "BEGIN{exit !(${v1:-0} > ${v0:-0})}"; then echo "PASS: knob drag: $v0 -> $v1"
else echo "FAIL: knob drag: $v0 -> $v1"; status=1; fi

y=$((Y + sy + sh - 8))
clicked=$(grep -c '^CLICKED' "$vpout")
echo "$x $y" >&3
for _ in $(seq 50); do [ "$(grep -c '^CLICKED' "$vpout")" -gt "$clicked" ] && break; sleep 0.1; done
sleep 1
v2=$(value)
if awk "BEGIN{exit !(${v2:-0} > ${v1:-0})}"; then echo "PASS: track click: $v1 -> $v2"
else echo "FAIL: track click: $v1 -> $v2"; status=1; fi
wait $pid
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
