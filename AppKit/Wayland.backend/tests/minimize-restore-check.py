#!/usr/bin/env python3
"""minimize-restore-check.py LOG --advertised 0|1

Reads the WAYLAND_DEBUG client log of minimize-restore.m and checks on the wire what the backend asks the
compositor for. xdg-shell has no request that undoes xdg_toplevel.set_minimized, so a client can only ask
for the window to be activated again (xdg-activation-v1). --advertised is what the fixture printed as
MINIMIZE-ADVERTISED: whether the compositor advertised minimizing in xdg_toplevel.wm_capabilities (the log
shows only the array's size, not its entries).
 - the first toplevel to get xdg_toplevel.set_minimized got it
 - with 1: after it, an activation token was requested whose set_surface names ANOTHER wl_surface (the one
   requesting the activation, not the one to activate), committed, and xdg_activation_v1.activate then
   named the minimized toplevel's wl_surface
 - with 0: no activation token was requested after it (the window was never in the minimized state, so
   there was nothing to restore)
"""
import re
import sys

advertised = None
for i, arg in enumerate(sys.argv):
    if arg == '--advertised' and i + 1 < len(sys.argv):
        advertised = sys.argv[i + 1] == '1'
if advertised is None:
    sys.exit('usage: minimize-restore-check.py LOG --advertised 0|1')

xdg_to_surface, toplevel_xdg = {}, {}
minimized_surface = None
token_surface = {}          # token object id -> wl_surface of its set_surface
committed = []              # (token object id, requesting wl_surface or None) after the minimize
activated = []              # wl_surface named by activate, after a commit
for line in open(sys.argv[1], errors='replace'):
    m = re.search(r'get_xdg_surface\(new id xdg_surface#(\d+), wl_surface#(\d+)\)', line)
    if m:
        xdg_to_surface[m[1]] = m[2]
    m = re.search(r'xdg_surface#(\d+)\.get_toplevel\(new id xdg_toplevel#(\d+)\)', line)
    if m:
        toplevel_xdg[m[2]] = m[1]
    m = re.search(r'xdg_toplevel#(\d+)\.set_minimized\(', line)
    if m and minimized_surface is None:
        minimized_surface = xdg_to_surface.get(toplevel_xdg.get(m[1]))
    if minimized_surface is None:
        continue
    m = re.search(r'xdg_activation_token_v1#(\d+)\.set_surface\(wl_surface#(\d+)\)', line)
    if m:
        token_surface[m[1]] = m[2]
    m = re.search(r'xdg_activation_token_v1#(\d+)\.commit\(', line)
    if m:
        committed.append((m[1], token_surface.get(m[1])))
    m = re.search(r'xdg_activation_v1#\d+\.activate\("[^"]*", wl_surface#(\d+)\)', line)
    if m and committed:
        activated.append(m[1])

results = [('the toplevel got xdg_toplevel.set_minimized', minimized_surface is not None)]
if advertised:
    results.append(('an activation token was requested after that, naming another surface as the requester',
                    any(s is not None and s != minimized_surface for _, s in committed)))
    results.append(('xdg_activation_v1.activate named the minimized wl_surface',
                    minimized_surface in activated))
else:
    results.append(('no activation was requested (minimizing was not advertised)', not committed and not activated))
for label, ok in results:
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
print('RESULT failures=%d' % sum(not ok for _, ok in results))
sys.exit(0 if all(ok for _, ok in results) else 1)
