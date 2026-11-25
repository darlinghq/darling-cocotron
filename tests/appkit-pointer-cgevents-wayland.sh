#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Driver of appkit-pointer-cgevents-wayland: moves a virtual pointer and presses its buttons (the helper
# tests/wayland-virtual-pointer.c, in $VIRTUAL_POINTER) over the window "ptr-cgevents-wayland", and holds modifier
# keys with a virtual keyboard (wtype). $WAYLAND_DISPLAY, $XDG_RUNTIME_DIR and $SWAYSOCK must name a headless sway
# whose windows float. Usage:
#   appkit-pointer-cgevents-wayland.sh <command that runs appkit-pointer-cgevents-wayland>
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
for _ in $(seq 50); do grep -q '^READY' "$vpout" && break; sleep 0.1; done
grep -q '^READY' "$vpout" || { echo "FAIL: no virtual pointer"; cat "$vpout"; exit 1; }
for _ in $(seq 600); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 2
if [ -n "${KWIN:-}" ]; then
    center="640 360"
else
swaymsg -q '[title="ptr-cgevents-wayland"] move position 200 200, focus'
sleep 0.5

# A point in the window, in layout coordinates
center=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "ptr-cgevents-wayland" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2)
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
fi
[ -n "$center" ] || { echo "FAIL: the window is not on screen"; cat "$out"; exit 1; }
PX=${center% *} PY=${center#* }
LEFT=272 RIGHT=273 MIDDLE=274 SIDE=275

# Send a command and wait for the helper's answer (the helper does a roundtrip after each one)
n=0
V() {
    echo "$*" >&3
    n=$((n + 1))
    for _ in $(seq 300); do [ "$(wc -l < "$vpout")" -gt "$n" ] && return; sleep 0.02; done
}
click() { V "button $1 1"; V "button $1 0"; }

# The pointer starts outside the window; the first phase is three moves inside it
V "abs 1850 1050"
sleep 0.3
V "abs $((PX - 40)) $((PY - 40))"
V "rel 10 10"
V "rel 10 10"
sleep 0.2
# a click at P (the first NSEvent makes the window accept mouse moved events), moves, and back to P
V "abs $PX $PY"
click $LEFT
sleep 0.3
V "rel 10 10"; V "rel 15 5"; V "rel -25 -15"
sleep 0.3
# four fractional moves
V "rel 0.5 0.25"; V "rel 0.5 0.25"; V "rel 0.5 0.25"; V "rel 0.5 0.25"
sleep 0.3
V "abs $PX $PY"
sleep 1.3
# a triple click
click $LEFT; click $LEFT; click $LEFT
sleep 1.3
# a click after the interval, one 2 points away (count continues), one 38 points further (starts over)
click $LEFT
V "rel 2 2"
click $LEFT
V "rel 38 0"
click $LEFT
V "abs $PX $PY"
sleep 1.3
# left, right and middle at once
click $LEFT; click $RIGHT; click $MIDDLE
sleep 1.3
# drags with each button
for b in $LEFT $RIGHT $MIDDLE; do
    V "abs $PX $PY"
    V "button $b 1"
    V "rel 10 5"
    V "rel 20 10"
    V "button $b 0"
    sleep 1.3
done
V "abs $PX $PY"
# clicks with modifiers: wtype holds the key for 1.6 s; the keyboard is bound by the client during the first second
mods="shift ctrl logo"
[ -n "${KWIN:-}" ] && mods="shift ctrl"   # KWin takes a click with Meta for its window move
for mod in $mods; do
    if [ -n "${KWIN:-}" ]; then
        case $mod in shift) key=42;; ctrl) key=29;; logo) key=125;; esac
        V "key $key 1"
        sleep 1.0
        click $LEFT
        V "key $key 0"
    else
        wtype -M $mod -s 1600 -m $mod &
        wt=$!
        sleep 1.0
        click $LEFT
        wait $wt
    fi
    sleep 1.3
done
# the side button
V "abs $PX $PY"
click $SIDE
sleep 0.5
# the end: the key q
if [ -n "${KWIN:-}" ]; then V "key 16 1"; V "key 16 0"; else wtype -s 300 q; fi

for _ in $(seq 600); do grep -q -E '^(ALL PASSED|FAILED)' "$out" && break; sleep 0.1; done
wait $pid
status=$?
cat "$out"
exit $status
