#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-child-windows.m on the Wayland backend and checks its results, and that sway maps
# the child windows that are shown (child-moving was shown by its first parent) and not the ones that left
# their parent or belong to a hidden one (a compositor places toplevels
# itself, so the move made by the window manager in the -x11.sh harness has no Wayland counterpart).
# Usage: appkit-window-child-windows-wayland.sh <command that runs "appkit-window-child-windows 5">
# with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY in the command's environment. Needs swaymsg,
# python3 and SWAYSOCK.
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT
for _ in $(seq 300); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
status=0
grep -q '^READY 0$' "$out" || status=1
mapped=$(swaymsg -t get_tree | python3 -I -c '
import json, sys
names = []
def walk(n):
    if (n.get("name") or "").startswith("child-") and n.get("visible") is not None:
        names.append(n["name"])
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        walk(c)
walk(json.load(sys.stdin))
print(" ".join(sorted(names)))')
want="child-attached child-moving child-parent"
if [ "$mapped" = "$want" ]; then echo "PASS: sway shows $mapped"; else echo "FAIL: sway shows \"$mapped\"; expected \"$want\""; status=1; fi
kill $pid 2>/dev/null; wait $pid 2>/dev/null
grep '^PASS \|^FAIL ' "$out"
[ $status = 0 ] || { echo "--- test output:"; cat "$out"; }
exit $status
