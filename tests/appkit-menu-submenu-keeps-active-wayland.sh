#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Drives tests/appkit-menu-submenu-keeps-active.m on a headless compositor with a virtual pointer: opens the
# menu with a click on the window, clicks the item with the submenu, then outside the menus, and checks
# that the application stayed active while the submenu was open and after the menus closed. Usage:
#   appkit-menu-submenu-keeps-active-wayland.sh <command that runs "appkit-menu-submenu-keeps-active <seconds>">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg (or
# KWin's window list through KWIN_TREE, a command that prints the window's "x y"), python3, and VIRTUAL_POINTER,
# the path of a built tests/wayland-virtual-pointer.c.
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

if [ -n "${KWIN_TREE:-}" ]; then
    pos=$($KWIN_TREE)
else
    pos=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
def walk(n):
    if n.get("name") == "menu-host" and n.get("shell") == "xdg_shell":
        r = n["rect"]
        print(r["x"], r["y"])
        return True
    return any(walk(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
walk(json.load(sys.stdin))')
fi
[ -n "$pos" ] || { echo "FAIL: no window"; cat "$out"; exit 1; }
set -- $pos; X=$1 Y=$2   # a point in the window

click() {
    local clicked
    clicked=$(grep -c '^CLICKED' "$vpout")
    echo "$1 $2" >&3
    for _ in $(seq 50); do [ "$(grep -c '^CLICKED' "$vpout")" -gt "$clicked" ] && break; sleep 0.1; done
}

status=0
GX=$((X + 100)) GY=$((Y + 100))
click $GX $GY
for _ in $(seq 100); do grep -q "^CLICK " "$out" && break; sleep 0.1; done
set -- $(grep "^CLICK " "$out")
# the window's top left, from where the first click was in the window
X=$((GX - $2)) Y=$((GY - $3))
for _ in $(seq 100); do grep -q "^OPEN\$" "$out" && break; sleep 0.1; done
grep -q "^OPEN\$" "$out" || { echo "FAIL: no menu"; cat "$out"; exit 1; }
sleep 0.5
set -- $(grep "^ITEM 1 " "$out")
click $((X + $3 + 10)) $((Y + $4 + $6 / 2))
for _ in $(seq 100); do grep -q "^SUBOPEN" "$out" && break; sleep 0.1; done
grep -q "^SUBOPEN" "$out" || { echo "FAIL: no submenu"; cat "$out"; exit 1; }
sleep 0.5
click $((X + 450)) $((Y + 350))
for _ in $(seq 100); do grep -q "^DONE\$" "$out" && break; sleep 0.1; done
wait $pid

if grep -q '^SUBOPEN active=1 resigns=0$' "$out"; then echo "PASS: the application stayed active while the submenu opened"
else echo "FAIL: '$(grep '^SUBOPEN' "$out")', expected SUBOPEN active=1 resigns=0"; status=1; fi
if grep -q '^FINAL active=1 resigns=0$' "$out"; then echo "PASS: still active and no resignation at the end"
else echo "FAIL: '$(grep '^FINAL' "$out")', expected FINAL active=1 resigns=0"; status=1; fi
grep -q '^FAIL' "$out" && { grep '^FAIL' "$out"; status=1; }
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
