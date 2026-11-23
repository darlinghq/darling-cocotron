#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-open-panel-presentation.m with the Wayland backend and checks, in the protocol trace, how the panel
# is presented to the compositor, for a panel run as a sheet and one run modally:
#  - the panel is an xdg_toplevel related to the document window (xdg_toplevel.set_parent), so the compositor keeps it in
#    front of that window and centres it on it; it is never left unrelated;
#  - the panel has a frame: when the compositor offers decoration negotiation (zxdg_decoration_manager_v1), the panel asks
#    for server-side decorations (a sheet is not drawn over its window as on macOS, since xdg-shell cannot place it there,
#    so it must not be a bare undecorated rectangle at a place the compositor chose).
# The compositor is whatever WAYLAND_DISPLAY names. Usage: appkit-open-panel-presentation-wayland.sh <command that runs
# "appkit-open-panel-presentation <sheet|modal> <seconds> free">; the script appends the three arguments itself.
# Needs python3.
set -u
status=0
for kind in sheet modal; do
    out=$(mktemp)
    WAYLAND_DEBUG=client "$@" $kind 5 free > "$out" 2>&1 < /dev/null &
    pid=$!
    for _ in $(seq 400); do grep -q '^DISMISSED' "$out" && break; sleep 0.1; done
    wait $pid; rc=$?
    grep -q '^PASS' "$out" || { echo "FAIL: $kind: the fixture failed (exit $rc)"; grep -E '^FAIL' "$out"; status=1; }
    result=$(python3 -I -c '
import re, sys
surf_top = {}; top_title = {}; top_parent = {}; deco_for = {}; deco_mode = {}; have_mgr = False
for line in sys.stdin:
    if "zxdg_decoration_manager_v1\", " in line and "-> wl_registry" in line: have_mgr = True
    if " -> " not in line: continue
    l = line.split(" -> ", 1)[1].strip()
    m = re.match(r"xdg_surface#(\d+)\.get_toplevel\(new id xdg_toplevel#(\d+)\)", l)
    if m: surf_top[m.group(1)] = m.group(2)
    m = re.match(r"xdg_toplevel#(\d+)\.set_title\(\"(.*)\"\)", l)
    if m: top_title[m.group(1)] = m.group(2)
    m = re.match(r"xdg_toplevel#(\d+)\.set_parent\((?:xdg_toplevel#(\d+)|nil)\)", l)
    if m: top_parent[m.group(1)] = m.group(2)
    m = re.match(r"zxdg_decoration_manager_v1#\d+\.get_toplevel_decoration\(new id zxdg_toplevel_decoration_v1#(\d+), xdg_toplevel#(\d+)\)", l)
    if m: deco_for[m.group(2)] = m.group(1)
    m = re.match(r"zxdg_toplevel_decoration_v1#(\d+)\.set_mode\((\d+)\)", l)
    if m: deco_mode[m.group(1)] = m.group(2)
by_title = {v: k for k, v in top_title.items()}
panel = by_title.get("Open"); doc = by_title.get("opp-doc")
ok = True
if panel is None or doc is None:
    print("no toplevels for the panel and the document window"); sys.exit(0)
if top_parent.get(panel) != doc:
    print("the panel is not related to the document window (set_parent)"); ok = False
if have_mgr and deco_mode.get(deco_for.get(panel)) != "2":
    print("the panel does not ask for server-side decorations"); ok = False
print("OK" if ok else "")
' < "$out")
    if [ "$result" = OK ]; then echo "PASS: $kind panel: related to the document window and framed"; else echo "FAIL: $kind panel: $result"; status=1; fi
    rm -f "$out"
done
exit $status
