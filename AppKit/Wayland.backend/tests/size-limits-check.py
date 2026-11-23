#!/usr/bin/env python3
"""size-limits-check.py LOG

Reads the WAYLAND_DEBUG client log of size-limits.m and checks, for the toplevel that sent the most
xdg_toplevel.set_min_size requests (the fixture window), what NSWindow's size limits became on the wire. The
sizes are window geometry sizes: the frame sizes the fixture sets, plus what a client-side frame adds around
the window (at most EXTRA_W x EXTRA_H), so the checks allow that much.
 - the minimum (200, 150) and the maximum (800, 600) set before the window is shown arrive
 - contentMinSize (250, 180), set after minSize, is the minimum then: at least that (the two are one limit,
   the last set wins)
 - no set_max_size is below the set_min_size sent with it (a protocol error, unless it is zero), and the
   maximum 100x100 that the fixture sets below the minimum arrives raised to the minimum
 - removing every limit (min 0, content min 0, max FLT_MAX) ends with set_min_size(0, 0) and set_max_size(0, 0)
"""
import re
import sys

EXTRA_W, EXTRA_H = 40, 80
events = {}     # toplevel id -> list of ('min'|'max', w, h)
for line in open(sys.argv[1], errors='replace'):
    m = re.search(r'xdg_toplevel#(\d+)\.set_(min|max)_size\((-?\d+), (-?\d+)\)', line)
    if m:
        events.setdefault(m[1], []).append((m[2], int(m[3]), int(m[4])))
if not events:
    print('FAIL no xdg_toplevel.set_min_size or set_max_size in the log')
    print('RESULT failures=1')
    sys.exit(1)
toplevel = max(events, key=lambda t: sum(1 for k, _, _ in events[t] if k == 'min'))
seq = events[toplevel]


def within(value, wanted, extra):
    return wanted <= value <= wanted + extra


mins = [(w, h) for k, w, h in seq if k == 'min']
maxs = [(w, h) for k, w, h in seq if k == 'max']
results = []
results.append(('the minimum 200x150 was set (%s)' % (mins[:3],),
                any(within(w, 200, EXTRA_W) and within(h, 150, EXTRA_H) for w, h in mins)))
results.append(('the maximum 800x600 was set (%s)' % (maxs[:3],),
                any(within(w, 800, EXTRA_W) and within(h, 600, EXTRA_H) for w, h in maxs)))
results.append(('contentMinSize 250x180, set last, became the minimum',
                any(w >= 250 and h >= 180 for w, h in mins)))
bad = []
raised = False
pending_min = (0, 0)
for k, w, h in seq:
    if k == 'min':
        pending_min = (w, h)
        continue
    if (w and w < pending_min[0]) or (h and h < pending_min[1]):
        bad.append((pending_min, (w, h)))
    if w and h and (w, h) == pending_min:
        raised = True
results.append(('no maximum below the minimum sent with it %s' % (bad,), not bad))
results.append(('a maximum below the minimum was raised to it', raised))
results.append(('after the limits were removed the last min and max are 0x0 (%s, %s)' % (mins[-1:], maxs[-1:]),
                bool(mins) and bool(maxs) and mins[-1] == (0, 0) and maxs[-1] == (0, 0)))
for label, ok in results:
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
print('RESULT failures=%d' % sum(not ok for _, ok in results))
sys.exit(0 if all(ok for _, ok in results) else 1)
