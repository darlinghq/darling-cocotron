"""Independently check exact crop endpoints in fractional-crop's client trace."""
from decimal import Decimal as D, ROUND_HALF_UP
from pathlib import Path
import json
import re
import sys


def rounded(value):
    return value.quantize(D(1), rounding=ROUND_HALF_UP)


def endpoint(logical, pixels, extent):
    return rounded(D(logical) * pixels / D(extent) * 256) / 256


def verify(path):
    viewports, sources, destinations, attachments, buffers, scales = {}, {}, {}, {}, {}, {}
    results = []
    for line in Path(path).read_text().splitlines():
        match = re.search(r'get_viewport\(new id wp_viewport#(\d+), wl_surface#(\d+)\)', line)
        if match: viewports[match[1]] = match[2]
        match = re.search(r'wp_viewport#(\d+)\.set_source\(([^)]+)\)', line)
        if match: sources[match[1]] = tuple(map(D, match[2].split(', ')))
        match = re.search(r'wp_viewport#(\d+)\.set_destination\(([^)]+)\)', line)
        if match: destinations[match[1]] = tuple(map(int, match[2].split(', ')))
        match = re.search(r'create_buffer\(new id wl_buffer#(\d+), \d+, (\d+), (\d+),', line)
        if match: buffers[match[1]] = tuple(map(int, match.groups()[1:]))
        match = re.search(r'wl_surface#(\d+)\.attach\(wl_buffer#(\d+),', line)
        if match: attachments[match[1]] = buffers[match[2]]
        match = re.search(r'wl_surface#(\d+)\.set_buffer_scale\((\d+)\)', line)
        if match: scales[match[1]] = int(match[2])
        match = re.fullmatch(r'CAPTURE (\d+)', line)
        if not match: continue
        stage = int(match[1]); assert stage == len(results) and stage < 3
        scale = (D('1.25'), D('1.5'), D('1.75'))[stage]
        width, height = rounded(101 * scale), rounded(51 * scale)
        left, right = endpoint(30, width, 101), endpoint(51, width, 101)
        top, bottom = endpoint(20, height, 51), endpoint(31, height, 51)
        expected = [
            ((101, 51), (0, 0, width, height)),
            ((51, 51), (0, 0, right, height)),
            ((71, 51), (left, 0, width-left, height)),
            ((101, 31), (0, 0, width, bottom)),
            ((101, 31), (0, top, width, height-top)),
        ]
        matched = []
        for dest, source in expected:
            ids = [v for v, d in destinations.items() if d == dest and sources.get(v) == source]
            assert len(ids) == 1, (stage, dest, source, ids)
            surface = viewports[ids[0]]
            assert attachments[surface] == (width, height), (stage, surface, attachments[surface])
            assert scales[surface] == 1
            matched.append({'destination': dest, 'source': list(map(str, source)), 'surface': surface})
        parents = [v for v, d in destinations.items() if d == (601, 401)]
        assert len(parents) == 1
        surface = viewports[parents[0]]
        assert attachments[surface] == (rounded(601 * scale), rounded(401 * scale))
        assert scales[surface] == 1
        results.append({'scale': str(scale), 'children': matched, 'parent_pixels': attachments[surface]})
    assert len(results) == 3
    return results


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1]), indent=2))
