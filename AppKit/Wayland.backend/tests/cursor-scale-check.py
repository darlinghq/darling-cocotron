#!/usr/bin/env python3
"""cursor-scale-check.py LOG OUTPUT_SCALE

Reads the WAYLAND_DEBUG client log of cursor-scale.m (output scale OUTPUT_SCALE, then 1) and checks
what a compositor that sizes a cursor as buffer size / buffer scale would show, whatever else it
does with a viewport:
 - the custom image is 31x17 logical and the theme arrow the nominal XCURSOR_SIZE (24 unless set),
   tagged with ceil(OUTPUT_SCALE) in set_buffer_scale, with no viewport on the cursor surface
 - the surface damage is the logical size and the hotspot lies inside it (the image hotspot is 3,5)
 - hiding the cursor sends set_cursor with no surface
 - when the output scale then drops to 1 with the arrow shown (no new setCursor), the backend sets
   the cursor again by itself: a new theme image of the nominal size at buffer scale 1
"""
import math
import os
import re
import sys

log, scale = sys.argv[1], float(sys.argv[2])
whole = math.ceil(scale)
nominal = int(os.environ.get('XCURSOR_SIZE') or 24)

buffers, attached, scales, damage, viewports = {}, {}, {}, {}, set()
state = {}
events = []  # per set_cursor: None for a hidden cursor, else a dict of the committed surface state
for line in open(log, errors='replace'):
    m = re.search(r'create_buffer\(new id wl_buffer#(\d+), \d+, (\d+), (\d+),', line)
    if m: buffers[m[1]] = (int(m[2]), int(m[3]))
    m = re.search(r'wl_surface#(\d+)\.attach\(wl_buffer#(\d+),', line)
    if m: attached[m[1]] = buffers.get(m[2])
    m = re.search(r'wl_surface#(\d+)\.set_buffer_scale\((\d+)\)', line)
    if m: scales[m[1]] = int(m[2])
    m = re.search(r'wl_surface#(\d+)\.damage\(0, 0, (\d+), (\d+)\)', line)
    if m: damage[m[1]] = (int(m[2]), int(m[3]))
    m = re.search(r'get_viewport\(new id wp_viewport#\d+, wl_surface#(\d+)\)', line)
    if m: viewports.add(m[1])
    m = re.search(r'wl_surface#(\d+)\.commit\(\)', line)
    if m: state[m[1]] = (attached.get(m[1]), scales.get(m[1], 1), damage.get(m[1]))
    m = re.search(r'wl_pointer#\d+\.set_cursor\(\d+, (nil|wl_surface#(\d+)), (-?\d+), (-?\d+)\)', line)
    if m:
        if m[1] == 'nil':
            events.append(None)
        else:
            buf, bscale, dmg = state.get(m[2], (None, 1, None))
            events.append({'buffer': buf, 'scale': bscale, 'damage': dmg, 'hot': (int(m[3]), int(m[4])),
                           'viewport': m[2] in viewports})

shown = [e for e in events if e]
results = []
def check(label, ok): results.append((label, bool(ok)))

check('set_cursor ran for the image, the arrow, a hidden cursor and the arrow again, then a rescale (>= 5)', len(events) >= 5)
if len(shown) >= 3:
    def logical(e): return (e['buffer'][0] / e['scale'], e['buffer'][1] / e['scale'])
    # The arrow is set when the pointer enters, before the fixture sets the image.
    image = next((e for e in shown if logical(e) == (31, 17)), shown[0])
    arrow = next((e for e in shown if e is not image), None)
    final = shown[-1]
    check('no cursor surface has a viewport', not any(e['viewport'] for e in shown))
    check('image: %s buffer at scale %s is 31x17 logical, tagged %d' % (image['buffer'], image['scale'], whole),
          image['scale'] == whole and logical(image) == (31, 17))
    check('image hotspot is (3, 5)', image['hot'] == (3, 5))
    check('arrow: %s at scale %s is %d logical, tagged %d' % (arrow and arrow['buffer'], arrow and arrow['scale'], nominal, whole),
          arrow and arrow['scale'] == whole and logical(arrow)[0] == nominal)
    for name, e in (('image', image), ('arrow', arrow), ('rescaled arrow', final)):
        check('%s: damage %s is the logical size and the hotspot %s lies inside it' % (name, e and e['damage'], e and e['hot']),
              e and e['damage'] == tuple(int(v) for v in logical(e))
              and 0 <= e['hot'][0] < logical(e)[0] and 0 <= e['hot'][1] < logical(e)[1])
    check('hiding the cursor sent set_cursor with no surface', None in events)
    check('rescaled to 1: a new theme image %s at buffer scale %s, %d logical, set without a new setCursor'
          % (final['buffer'], final['scale'], nominal),
          final['scale'] == 1 and logical(final)[0] == nominal and final['buffer'] != arrow['buffer'])
    check('the last set_cursor came after the hide', events.index(None) < len(events) - 1)
for label, ok in results:
    print('%s %s' % ('PASS' if ok else 'FAIL', label))
print('RESULT failures=%d' % sum(not ok for _, ok in results))
sys.exit(1 if any(not ok for _, ok in results) else 0)
