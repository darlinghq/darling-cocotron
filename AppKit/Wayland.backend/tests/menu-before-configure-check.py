#!/usr/bin/env python3
# Copyright (C) 2026 Lubos Dolezel
"""menu-before-configure-check.py LOG

Reads the WAYLAND_DEBUG client log of menu-before-configure.m and checks on the wire:
 - there is an xdg_popup (the menu)
 - no surface that got an xdg_popup was ever given an xdg_toplevel
 - the window is the only toplevel
 - the popup's parent is the window's xdg_surface, and the popup was created after the compositor
   had configured that parent and the client acknowledged it (a popup of a surface that has not
   been configured yet cannot be created)
"""
import re
import sys

xdg_to_surface, toplevels, popups = {}, [], []
configured_acked = set()
seq = 0
for line in open(sys.argv[1], errors='replace'):
    seq += 1
    m = re.search(r'get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)', line)
    if m: xdg_to_surface[m[1]] = m[2]
    m = re.search(r'xdg_surface#(\d+)\.get_toplevel\(', line)
    if m: toplevels.append(m[1])
    m = re.search(r'xdg_surface#(\d+)\.ack_configure\(', line)
    if m: configured_acked.add(m[1])
    m = re.search(r'xdg_surface#(\d+)\.get_popup\(new id xdg_popup#(\d+), xdg_surface#(\d+),', line)
    if m:
        popups.append({'xdg': m[1], 'parent': m[3], 'parent_acked': m[3] in configured_acked})

popup_surfaces = {p['xdg'] for p in popups}
results = [
    ('the menu is an xdg_popup', len(popups) >= 1),
    ('no popup surface was ever a toplevel', not (popup_surfaces & set(toplevels))),
    ('the window is the only toplevel (%d)' % len(toplevels), len(toplevels) == 1),
    ('every popup is a child of the window', all(p['parent'] in toplevels for p in popups)),
    ('every popup was created after its parent was configured and acknowledged', all(p['parent_acked'] for p in popups)),
]
for label, ok in results:
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
print('RESULT failures=%d' % sum(not ok for _, ok in results))
sys.exit(0 if all(ok for _, ok in results) else 1)
