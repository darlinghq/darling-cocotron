"""Match each native surface's allocation to its own advertised preference."""
import json
import re
import sys
from pathlib import Path


def verify(path):
    addons, preferences, viewports, destinations, buffers, attachments = {}, {}, {}, {}, {}, {}
    results = []
    for line in Path(path).read_text().splitlines():
        m = re.search(r'get_fractional_scale\(new id wp_fractional_scale_v1#(\d+), wl_surface#(\d+)\)', line)
        if m: addons[m[1]] = m[2]
        m = re.search(r'wp_fractional_scale_v1#(\d+)\.preferred_scale\((\d+)\)', line)
        if m: preferences[addons[m[1]]] = int(m[2])
        m = re.search(r'get_viewport\(new id wp_viewport#(\d+), wl_surface#(\d+)\)', line)
        if m: viewports[m[1]] = m[2]
        m = re.search(r'wp_viewport#(\d+)\.set_destination\((\d+), (\d+)\)', line)
        if m: destinations[m[1]] = tuple(map(int, m.groups()[1:]))
        m = re.search(r'create_buffer\(new id wl_buffer#(\d+), \d+, (\d+), (\d+),', line)
        if m: buffers[m[1]] = tuple(map(int, m.groups()[1:]))
        m = re.search(r'wl_surface#(\d+)\.attach\(wl_buffer#(\d+),', line)
        if m: attachments[m[1]] = buffers[m[2]]
        m = re.fullmatch(r'CAPTURE (\d+)', line)
        if not m: continue
        phase = int(m[1]); assert phase == len(results) and phase < 3
        records = []
        for viewport, logical in destinations.items():
            if logical not in [(101, 51), (601, 401)]: continue
            surface = viewports[viewport]; scale = preferences[surface]
            expected = tuple((n * scale + 60) // 120 for n in logical)
            assert attachments[surface] == expected, (phase, surface, scale, expected, attachments[surface])
            records.append({'surface': surface, 'logical': logical, 'preferred_scale': scale, 'pixels': expected})
        assert len(records) == 3
        children = [r for r in records if r['logical'] == (101, 51)]
        assert sorted(r['preferred_scale'] for r in children) == ([150, 210], [150, 180], [150, 210])[phase]
        results.append({'phase': phase, 'surfaces': records})
    assert len(results) == 3
    return results


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1]), indent=2))
