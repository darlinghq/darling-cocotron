"""Verify settled cursor wire state and untouched compositor captures."""
from decimal import Decimal as D, ROUND_HALF_UP
from pathlib import Path
import json
import math
import re
import subprocess
import sys


def verify(directory, synthetic=False):
    root = Path(directory)
    viewports, destinations, buffers, attached, scales, damage = {}, {}, {}, {}, {}, {}
    cursor = None
    committed = {}
    results = []
    for line in (root / 'app.log').read_text().splitlines():
        m = re.search(r'get_viewport\(new id wp_viewport#(\d+), wl_surface#(\d+)\)', line)
        if m: viewports[m[1]] = m[2]
        m = re.search(r'wp_viewport#(\d+)\.set_destination\((\d+), (\d+)\)', line)
        if m: destinations[viewports[m[1]]] = tuple(map(int, m.groups()[1:]))
        m = re.search(r'create_buffer\(new id wl_buffer#(\d+), \d+, (\d+), (\d+),', line)
        if m: buffers[m[1]] = tuple(map(int, m.groups()[1:]))
        m = re.search(r'wl_surface#(\d+)\.attach\(wl_buffer#(\d+),', line)
        if m: attached[m[1]] = buffers[m[2]]
        m = re.search(r'wl_surface#(\d+)\.set_buffer_scale\((\d+)\)', line)
        if m: scales[m[1]] = int(m[2])
        m = re.search(r'wl_surface#(\d+)\.damage\(0, 0, (\d+), (\d+)\)', line)
        if m: damage[m[1]] = tuple(map(int, m.groups()[1:]))
        m = re.search(r'wl_surface#(\d+)\.commit\(\)', line)
        if m:
            surface = m[1]
            committed[surface] = (attached.get(surface), destinations.get(surface),
                                  scales.get(surface, 1), damage.get(surface))
        m = re.search(r'\.set_cursor\(\d+, (nil|wl_surface#\d+), (\d+), (\d+)\)', line)
        if m: cursor = None if m[1] == 'nil' else (m[1].split('#')[1], int(m[2]), int(m[3]))
        m = re.fullmatch(r'CAPTURE (\d+)', line)
        if not m: continue
        stage = int(m[1]); assert stage == len(results) and stage < 7
        scale = (D('1.25'), D('1.5'), D('1.75'), D('1.75'), D('1.25'), D('1.25'), D('1.5'))[stage]
        path = str(root / ('cursor-' + str(stage) + '.png'))
        width, height = map(int, subprocess.check_output(['magick','identify','-format','%w %h',path]).split())
        pixels = subprocess.check_output(['magick',path,'-depth','8','RGB:-'])
        assert len(pixels) == width * height * 3
        custom = stage in (0, 1, 2, 6)
        wanted = b'\0\xff\xff' if custom else b'\xff\x80\0'
        points = [(i//3 % width, i//3//width) for i in range(0,len(pixels),3)
                  if (pixels[i:i+3] == wanted if custom or (synthetic and stage != 5) else pixels[i:i+3] != b'\0\0\0')]
        if stage == 5:
            assert cursor is None and not points
            results.append({'stage': stage, 'blank': True}); continue
        assert cursor is not None
        surface, hx, hy = cursor
        actual, logical, wire_scale, committed_damage = committed[surface]
        assert wire_scale == 1 and committed_damage == logical
        assert 0 <= hx < logical[0] and 0 <= hy < logical[1]
        if custom:
            expected = tuple(int((D(n)*scale).quantize(D(1),rounding=ROUND_HALF_UP)) for n in (31,17))
            assert actual == expected and logical == (31,17) and (hx,hy) == (3,5)
            assert len(points) == actual[0] * actual[1], (stage,actual,len(points))
        else:
            expected = tuple(max(1,int((D(n)/scale).quantize(D(1),rounding=ROUND_HALF_UP))) for n in actual)
            assert logical == expected
            if synthetic:
                assert logical == (24,16) and (hx,hy) == (4,8)
                assert actual == (int(24*scale),int(16*scale))
                assert len(points) == actual[0]*actual[1]
        assert points
        extent = (max(x for x,y in points)-min(x for x,y in points)+1,
                  max(y for x,y in points)-min(y for x,y in points)+1)
        if custom: assert extent == actual
        else: assert extent[0] <= math.ceil(logical[0]*scale) and extent[1] <= math.ceil(logical[1]*scale)
        origin = (min(x for x,y in points),min(y for x,y in points))
        if synthetic:
            # The runner sends a fresh absolute native pointer motion after
            # each output change, fixing the pointer at logical (250,220).
            expected_origin = ((250-hx)*scale,(220-hy)*scale)
            assert all(abs(D(a)-b) <= 1 for a,b in zip(origin,expected_origin)), (stage,origin,expected_origin)
            assert sum(pixels[i:i+3] != b'\0\0\0' for i in range(0,len(pixels),3)) == len(points)
        results.append({'stage': stage, 'buffer': actual, 'logical': logical,
                        'hotspot': (hx,hy), 'visible_pixels': len(points), 'visible_extent': extent, 'visible_origin': origin})
    assert len(results) == 7
    return results


if __name__ == '__main__':
    print(json.dumps(verify(sys.argv[1], '--synthetic' in sys.argv[2:]),indent=2))
