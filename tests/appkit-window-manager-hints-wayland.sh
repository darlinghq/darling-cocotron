#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-manager-hints.m with the Wayland backend (DARLING_APPKIT_BACKEND=wayland and
# WAYLAND_DISPLAY in the command's environment) and checks the roles it gave its windows in the protocol
# trace (WAYLAND_DEBUG=client, which this script sets):
#  - the main window, the window that draws its own chrome and the borderless window that cannot become main are
#    toplevels without a parent (all application windows of a regular application);
#  - the panel is a toplevel related to an application window
#    (xdg_toplevel.set_parent), so that the compositor keeps them in front of it and out of the task bar;
#  - the pop-up windows and the tool tip are xdg_popups of the main window, at the offset from the main
#    window's frame (as AppKit reports it) that AppKit gave them, and the compositor put them there
#    (xdg_popup.configure), not toplevels that it would centre and list.
# If KWIN_QUERY is set to a command that prints one "KWINWIN <caption> k=v ..." line per window (see the impl
# note), the compositor's own view is checked too: no task-bar entry for any window but the application
# windows (a window related to a parent counts as not listed), and only the key window active.
# Usage: appkit-window-manager-hints-wayland.sh <command that runs "appkit-window-manager-hints <seconds>">
# Needs python3.
set -u
out=$(mktemp)
export WAYLAND_DEBUG=client
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT
for _ in $(seq 400); do grep -q '^READY' "$out" && break; sleep 0.1; done
grep -q '^READY' "$out" || { echo "FAIL: the test never became ready"; cat "$out"; exit 1; }
sleep 1
status=0
screen_h=$(sed -n 's/^SCREEN [0-9]* //p' "$out")

mainframe=$(sed -n 's/^WIN wmh-main //p' "$out")
result=$(SCREEN_H=$screen_h MAIN_FRAME="$mainframe" python3 -I -c '
import os, re, sys
H = int(os.environ["SCREEN_H"])
# name: requested Cocoa frame, expected role, expected parent
# The main window is where AppKit says it is (the compositor chooses its size), the others where they were asked to be.
mf = [float(v) for v in os.environ["MAIN_FRAME"].split()[:4]]
APP = ("wmh-main", "wmh-chrome", "wmh-loose")
want = {
    "wmh-main":        ((mf[0], mf[1], mf[2], mf[3]), "toplevel", None),
    "wmh-chrome":      ((1400, 400, 210, 140), "toplevel", None),
    "wmh-loose":       ((1400, 700, 170, 110), "toplevel", None),
    "wmh-panel":       ((1000, 300, 180, 130), "toplevel", APP),
    "wmh-popup":       ((820, 560, 160, 120), "popup", "wmh-main"),
    "wmh-popup-level": ((1100, 640, 200, 150), "popup", "wmh-main"),
    "wmh-child":       ((700, 300, 150, 100), "popup", "wmh-main"),
    "wmh-tooltip":     ((300, 200, 120, 40), "popup", "wmh-main"),
}
popup_cfg = {}
cur_popup = {}
by_size = {(v[0][2], v[0][3]): k for k, v in want.items() if v[1] == "popup"}
surf_to_top = {}      # xdg_surface id -> xdg_toplevel id
top_name = {}         # xdg_toplevel id -> title
top_parent = {}       # xdg_toplevel id -> parent toplevel id
surf_name = {}        # xdg_surface id -> name of the window it belongs to (toplevels by title, popups by size)
pos = {}              # positioner id -> dict
popups = {}           # name -> (parent surface, anchor, offset)
toplevels = {}        # name -> parent toplevel id
for line in sys.stdin:
    m = re.search(r"\} xdg_popup#(\d+)\.configure\((-?\d+), (-?\d+), \d+, \d+\)", line)
    if m and m.group(1) in cur_popup:
        popup_cfg[cur_popup[m.group(1)]] = (int(m.group(2)), int(m.group(3)))
        continue
    if " -> " not in line:
        continue
    line = line.split(" -> ", 1)[1].strip()
    m = re.match(r"xdg_surface#(\d+)\.get_toplevel\(new id xdg_toplevel#(\d+)\)", line)
    if m:
        surf_to_top[m.group(1)] = m.group(2); top_parent.pop(m.group(2), None); continue
    m = re.match(r"xdg_toplevel#(\d+)\.set_title\(\"(.*)\"\)", line)
    if m:
        top_name[m.group(1)] = m.group(2)
        for s, t in surf_to_top.items():
            if t == m.group(1):
                surf_name[s] = m.group(2)
        toplevels[m.group(2)] = None
        continue
    m = re.match(r"xdg_toplevel#(\d+)\.set_parent\((?:xdg_toplevel#(\d+)|nil)\)", line)
    if m:
        top_parent[m.group(1)] = m.group(2)
        if m.group(1) in top_name:
            toplevels[top_name[m.group(1)]] = m.group(2)
        continue
    m = re.match(r"xdg_wm_base#\d+\.create_positioner\(new id xdg_positioner#(\d+)\)", line)
    if m:
        pos[m.group(1)] = {}; continue
    m = re.match(r"xdg_positioner#(\d+)\.(set_size|set_anchor_rect|set_offset)\(([-\d, ]+)\)", line)
    if m and m.group(1) in pos:
        pos[m.group(1)][m.group(2)] = [int(v) for v in m.group(3).split(",")]; continue
    m = re.match(r"xdg_popup#(\d+)\.reposition\(xdg_positioner#(\d+), \d+\)", line)
    if m and m.group(1) in cur_popup and cur_popup[m.group(1)] in popups:
        p = pos.get(m.group(2), {})
        name = cur_popup[m.group(1)]
        popups[name] = (popups[name][0], p.get("set_anchor_rect", [0, 0, 0, 0]), p.get("set_offset", [0, 0]))
        continue
    m = re.match(r"xdg_surface#(\d+)\.get_popup\(new id xdg_popup#(\d+), xdg_surface#(\d+), xdg_positioner#(\d+)\)", line)
    if m:
        p = pos.get(m.group(4), {})
        size = tuple(p.get("set_size", (0, 0)))
        name = by_size.get(size, "unknown-%dx%d" % size)
        surf_name[m.group(1)] = name
        cur_popup[m.group(2)] = name
        popups[name] = (m.group(3), p.get("set_anchor_rect", [0, 0, 0, 0]), p.get("set_offset", [0, 0]))
        toplevels.pop(name, None)
        continue
for name, (frame, role, parent) in want.items():
    x, y, w, h = frame
    if role == "toplevel":
        if name not in toplevels:
            print("FAIL %s: not a toplevel (expected a toplevel%s)" % (name, " of " + str(parent) if parent else "")); continue
        p = toplevels[name]
        got = top_name.get(p, "unknown") if p else None
        ok = got in parent if isinstance(parent, tuple) else got == parent
        if ok:
            print("PASS %s: xdg_toplevel, parent %s" % (name, got))
        else:
            print("FAIL %s: xdg_toplevel, parent %s; expected %s" % (name, got, parent))
    else:
        if name not in popups:
            print("FAIL %s: not an xdg_popup (expected a popup of %s)" % (name, parent)); continue
        psurf, anchor, off = popups[name]
        got_parent = surf_name.get(psurf, "unknown")
        mx, my, mw, mh = want["wmh-main"][0]
        wantx = int(x - mx)
        wanty = int((my + mh) - (y + h))
        gotx, goty = anchor[0] + off[0], anchor[1] + off[1]
        placed = popup_cfg.get(name)
        if got_parent == parent and (gotx, goty) == (wantx, wanty) and placed == (wantx, wanty):
            print("PASS %s: xdg_popup of %s at %d,%d, placed there by the compositor" % (name, got_parent, gotx, goty))
        else:
            print("FAIL %s: xdg_popup of %s at %d,%d, placed at %s; expected %s at %d,%d" % (name, got_parent, gotx, goty, placed, parent, wantx, wanty))
' < "$out")
echo "$result"
grep -q '^FAIL' <<< "$result" && status=1

if [ -n "${KWIN_QUERY:-}" ]; then
    kw=$($KWIN_QUERY)
    for n in wmh-main wmh-chrome wmh-loose; do
        l=$(grep "^KWINWIN $n " <<< "$kw")
        if grep -q 'skipTaskbar=false' <<< "$l"; then echo "PASS: KWin lists $n in the task bar"; else echo "FAIL: KWin does not list $n: $l"; status=1; fi
    done
    # A popup is not a window KWin lists at all; a window with a parent is a transient of it.
    for n in wmh-popup wmh-popup-level wmh-child wmh-panel wmh-tooltip; do
        l=$(grep "^KWINWIN $n " <<< "$kw")
        if [ -z "$l" ] || grep -q 'skipTaskbar=true' <<< "$l" || grep -q 'transient=true' <<< "$l"; then echo "PASS: KWin keeps $n out of the task bar"; else echo "FAIL: KWin lists $n in the task bar: $l"; status=1; fi
    done
    key=$(sed -n 's/^KEY //p' "$out")
    active=$(grep 'active=true' <<< "$kw" | sed 's/^KWINWIN \([^ ]*\) .*/\1/' | tr '\n' ' ')
    if [ "$active" = "$key " ]; then echo "PASS: only the key window ($key) is active"; else echo "FAIL: active windows: '$active', the key window is $key"; status=1; fi
fi
kill $pid 2>/dev/null; wait $pid 2>/dev/null
[ $status = 0 ] || { echo "--- test output (without protocol lines):"; grep -v '^\[' "$out"; }
exit $status
