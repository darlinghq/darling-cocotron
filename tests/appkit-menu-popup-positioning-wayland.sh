#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-menu-popup-positioning.m on a headless sway compositor with a virtual pointer: opens
# each case's menu with a click on the window, then clicks the item the test names where the program says
# it is relative to the window (or outside the menu). Each menu must be an xdg_popup of the window. Usage:
#   appkit-menu-popup-positioning-wayland.sh <command that runs "appkit-menu-popup-positioning <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg,
# python3, SWAYSOCK and WAYLAND_DISPLAY for the compositor, and VIRTUAL_POINTER, the path of a built
# tests/wayland-virtual-pointer.c.
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
    if n.get("name") == "menu-host" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"], r["y"])
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
[ -n "$pos" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
set -- $pos; X=$1 Y=$2

click() {
    local clicked
    clicked=$(grep -c '^CLICKED' "$vpout")
    echo "$1 $2" >&3
    for _ in $(seq 50); do [ "$(grep -c '^CLICKED' "$vpout")" -gt "$clicked" ] && break; sleep 0.1; done
}

status=0
for spec in "1 1 YES" "2 2 YES" "3 outside NO"; do
    set -- $spec
    n=$1 choose=$2 want=$3
    click $((X + 20)) $((Y + 20))
    for _ in $(seq 100); do grep -q "^OPEN $n\$" "$out" && break; sleep 0.1; done
    grep -q "^OPEN $n\$" "$out" || { echo "FAIL: case $n: no menu"; status=1; break; }
    if grep -q "^POPUP $n 1\$" "$out"; then echo "PASS: case $n: the menu is an xdg_popup"
    else echo "FAIL: case $n: the menu is not an xdg_popup"; status=1; fi
    sleep 0.5
    if [ "$choose" = outside ]; then
        click $((X + 450)) $((Y + 350))
    else
        set -- $(grep "^ITEM $n $choose " "$out")
        click $((X + $4 + 10)) $((Y + $5 + $7 / 2))
    fi
    for _ in $(seq 100); do grep -q "^RESULT $n " "$out" && break; sleep 0.1; done
    got=$(grep "^RESULT $n " "$out")
    if [ "$got" = "RESULT $n $want" ]; then echo "PASS: case $n: $got"
    else echo "FAIL: case $n: '$got', expected RESULT $n $want"; status=1; fi
done
wait $pid
actions=$(grep '^ACTION' "$out" | tr '\n' ' ')
if [ "$actions" = "ACTION Two ACTION Three " ]; then echo "PASS: actions $actions"
else echo "FAIL: actions '$actions', expected ACTION Two ACTION Three"; status=1; fi
grep -q '^PASS clamp' "$out" && grep '^PASS clamp' "$out" || { echo "FAIL: the clamp case did not pass"; status=1; }
grep -q '^FAIL' "$out" && { grep '^FAIL' "$out"; status=1; }
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
