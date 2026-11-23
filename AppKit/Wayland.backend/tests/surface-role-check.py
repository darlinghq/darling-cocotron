#!/usr/bin/env python3
"""surface-role-check.py LOG

Reads a WAYLAND_DEBUG client log (surface-role.m, or any other client) and checks on the wire that no
wl_surface was given two different xdg-shell roles. The core protocol (wl_surface, "Once a wl_surface is
given a role, it is set permanently for the whole lifetime of the wl_surface object") makes the role
permanent, and xdg_toplevel and xdg_popup are different roles, so a window that is shown once as a toplevel
and once as a popup needs a new wl_surface for the second role.
 - no wl_surface gets both xdg_surface.get_toplevel and xdg_surface.get_popup in its lifetime (the
   lifetime ends with wl_surface.destroy; an id can be used again after that)
 - there is at least one popup and one toplevel in the log, so that the check had something to look at
"""
import re
import sys

xdg_to_surface = {}
roles = {}          # wl_surface id -> (role, line number of the request that gave it)
violations = []
counts = {'toplevel': 0, 'popup': 0}


def give_role(xdg, role, line_no):
    surface = xdg_to_surface.get(xdg)
    counts[role] += 1
    if surface is None:
        return
    first = roles.get(surface)
    if first is None:
        roles[surface] = (role, line_no)
    elif first[0] != role:
        violations.append((surface, first, (role, line_no)))


for line_no, line in enumerate(open(sys.argv[1], errors='replace'), 1):
    m = re.search(r'wl_compositor#\d+\.create_surface\(new id wl_surface#(\d+)\)', line)
    if m:
        roles.pop(m[1], None)
    m = re.search(r'get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)', line)
    if m:
        xdg_to_surface[m[1]] = m[2]
    m = re.search(r'xdg_surface#(\d+)\.get_toplevel\(', line)
    if m:
        give_role(m[1], 'toplevel', line_no)
    m = re.search(r'xdg_surface#(\d+)\.get_popup\(', line)
    if m:
        give_role(m[1], 'popup', line_no)
    m = re.search(r'wl_surface#(\d+)\.destroy\(', line)
    if m:
        roles.pop(m[1], None)

results = [('the log has a toplevel and a popup', counts['toplevel'] > 0 and counts['popup'] > 0)]
results.append(('no wl_surface was given two different roles' + ''.join(
    ' (wl_surface#%s: %s at line %d, then %s at line %d)' % (s, f[0], f[1], n[0], n[1])
    for s, f, n in violations), not violations))
for label, ok in results:
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
print('RESULT failures=%d' % sum(not ok for _, ok in results))
sys.exit(0 if all(ok for _, ok in results) else 1)
