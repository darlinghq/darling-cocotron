#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-child-windows.m on the Wayland backend and checks its results, and that the
# compositor shows the child windows that are shown (child-moving was shown by its first parent) and not the
# ones that left their parent or belong to a hidden one (a compositor places toplevels itself, so the move
# made by the window manager in the -x11.sh harness has no Wayland counterpart). The children are borderless
# windows attached to their parent, so they are xdg_popups of it, which a compositor does not list with the
# toplevels: the popups still alive at the end are read from the protocol trace (WAYLAND_DEBUG=client, which
# this script sets), by size.
# Usage: appkit-window-child-windows-wayland.sh <command that runs "appkit-window-child-windows 5">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg,
# python3 and SWAYSOCK.
set -u
out=$(mktemp)
export WAYLAND_DEBUG=client
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
status=0
grep -q '^READY 0$' "$out" || status=1
toplevels=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
names = []
def walk(n):
    if (n.get("name") or "").startswith("child-") and n.get("visible") is not None:
        names.append(n["name"])
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        walk(c)
walk(json.load(sys.stdin))
print(" ".join(sorted(names)))')
popups=$(python3 -I -c '
import re, sys
sizes = {(120, 80): "child-attached", (60, 40): "child-hidden", (50, 50): "child-late", (40, 40): "child-moving"}
pos = {}
alive = {}
for line in sys.stdin:
    if " -> " not in line:
        continue
    line = line.split(" -> ", 1)[1].strip()
    m = re.match(r"xdg_positioner#(\d+)\.set_size\((\d+), (\d+)\)", line)
    if m:
        pos[m.group(1)] = (int(m.group(2)), int(m.group(3))); continue
    m = re.match(r"xdg_surface#\d+\.get_popup\(new id xdg_popup#(\d+), xdg_surface#\d+, xdg_positioner#(\d+)\)", line)
    if m:
        alive[m.group(1)] = sizes.get(pos.get(m.group(2)), "other"); continue
    m = re.match(r"xdg_popup#(\d+)\.destroy\(\)", line)
    if m:
        alive.pop(m.group(1), None)
print(" ".join(sorted(alive.values())))' < "$out")
mapped=$(echo $toplevels $popups | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
want="child-attached child-moving child-parent"
if [ "$mapped" = "$want" ]; then echo "PASS: sway shows $mapped"; else echo "FAIL: sway shows \"$mapped\"; expected \"$want\""; status=1; fi
kill $pid 2>/dev/null; wait $pid 2>/dev/null
grep '^PASS \|^FAIL ' "$out"
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
