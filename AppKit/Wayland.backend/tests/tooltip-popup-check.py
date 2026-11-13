#!/usr/bin/env python3
"""tooltip-popup-check.py LOG

Reads the WAYLAND_DEBUG client log of tooltip-popup.m and checks on the wire, independently of the
backend's own bookkeeping:
 - every tool tip surface (the surfaces that got xdg_popup) was never an xdg_toplevel, got no
   xdg_popup.grab (the first one is ordered front inside a click, so a grab would hold a valid
   serial), and has an input region that is a wl_region that never got add()
 - the first two popups sit next to the pointer: the compositor's xdg_popup.configure position is
   the pointer position in the parent surface plus (12, 4), the offsets of NSToolTipWindow, and
   the parent is the surface that had pointer focus (the second popup belongs to the window the
   pointer moved to, not to the window clicked before)
 - there are at least 6 popups (two placements, three show/hide cycles and the last show) and each
   was destroyed; the one shown when its parent window closed was destroyed before the parent's
   xdg_surface
"""
import re
import sys

TOL = 2.0  # logical px: the backend floors the pointer position and the tool tip frame is integral
xdg_to_surface, regions, added = {}, set(), set()
toplevels, input_regions, popups, order = set(), [], [], []
focus = pos = None
seq = 0
for line in open(sys.argv[1], errors='replace'):
    seq += 1
    m = re.search(r'wl_compositor#\d+\.create_region\(new id wl_region#(\d+)\)', line)
    if m: regions.add(m[1])
    m = re.search(r'wl_region#(\d+)\.add\(', line)
    if m: added.add(m[1])
    m = re.search(r'get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)', line)
    if m: xdg_to_surface[m[1]] = m[2]
    m = re.search(r'xdg_surface#(\d+)\.get_toplevel\(', line)
    if m: toplevels.add(xdg_to_surface.get(m[1]))
    m = re.search(r'wl_pointer#\d+\.enter\(\d+, wl_surface#(\d+), ([-\d.]+), ([-\d.]+)\)', line)
    if m: focus, pos = m[1], (float(m[2]), float(m[3]))
    m = re.search(r'wl_pointer#\d+\.motion\(\d+, ([-\d.]+), ([-\d.]+)\)', line)
    if m: pos = (float(m[1]), float(m[2]))
    m = re.search(r'xdg_surface#(\d+)\.get_popup\(new id xdg_popup#(\d+), xdg_surface#(\d+),', line)
    if m:
        popups.append({'id': m[2], 'xdg': m[1], 'surface': xdg_to_surface.get(m[1]), 'parent_xdg': m[3],
                       'parent': xdg_to_surface.get(m[3]), 'focus': focus, 'pointer': pos,
                       'grab': False, 'configure': None, 'destroyed': None})
    m = re.search(r'xdg_popup#(\d+)\.grab\(', line)
    for p in popups:
        if m and p['id'] == m[1]: p['grab'] = True
    m = re.search(r'xdg_popup#(\d+)\.configure\((-?\d+), (-?\d+), (\d+), (\d+)\)', line)
    for p in popups:
        if m and p['id'] == m[1] and p['configure'] is None: p['configure'] = (int(m[2]), int(m[3]))
    m = re.search(r'xdg_popup#(\d+)\.destroy\(', line)
    for p in popups:
        if m and p['id'] == m[1]: p['destroyed'] = seq
    m = re.search(r'wl_surface#(\d+)\.set_input_region\(wl_region#(\d+)\)', line)
    if m: input_regions.append((m[1], m[2]))
    m = re.search(r'xdg_surface#(\d+)\.destroy\(', line)
    if m: order.append((m[1], seq))

results = [('at least 6 tool tip popups were created', len(popups) >= 6)]
results.append(('no tool tip surface was ever a toplevel', all(p['surface'] not in toplevels for p in popups)))
results.append(('no xdg_popup.grab for any tool tip', not any(p['grab'] for p in popups)))
results.append(('every tool tip input region is an empty wl_region',
                all(any(s == p['surface'] and r in regions and r not in added for s, r in input_regions) for p in popups)))
results.append(('every tool tip popup was destroyed', all(p['destroyed'] for p in popups)))
for i, p in enumerate(popups[:2]):
    ok = (p['configure'] is not None and p['pointer'] is not None and p['parent'] == p['focus']
          and abs(p['configure'][0] - (p['pointer'][0] + 12)) <= TOL
          and abs(p['configure'][1] - (p['pointer'][1] + 4)) <= TOL)
    results.append(('popup %d is next to the pointer in its parent: configure %s, pointer %s, parent %s focus %s'
                    % (i + 1, p['configure'], p['pointer'], p['parent'], p['focus']), ok))
if len(popups) >= 2:
    results.append(('the second popup has another parent than the first (the pointer window, not the clicked one)',
                    popups[0]['parent_xdg'] != popups[1]['parent_xdg']))
if popups:
    last = popups[-1]
    gone = [s for x, s in order if x == last['parent_xdg']]
    results.append(('the popup shown when its parent closed was destroyed before the parent xdg_surface',
                    bool(gone) and last['destroyed'] is not None and last['destroyed'] < gone[0]))
for label, ok in results:
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
print('RESULT failures=%d' % sum(not ok for _, ok in results))
sys.exit(0 if all(ok for _, ok in results) else 1)
