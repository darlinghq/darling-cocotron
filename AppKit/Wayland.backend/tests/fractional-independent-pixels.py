# Copyright (C) 2026 Darling Developers
#
# Licensed under the MIT license, the same as the rest of this project.
"""Check the compositor captures of fractional-independent-run.sh (ImageMagick required).

For every phase the window's rectangle comes from sway's tree and the scale and place of each output from
sway's output list; each region of the window (AppKit content coordinates, bottom left origin) is looked up in
the capture of the output it lies on, and every pixel of it must have the colour the window or view draws.
"""
import json
import math
from pathlib import Path
import subprocess
import sys

TITLE = 'Independent fractional fixture'
# Inside the views and the window, away from the edges the compositor filters.
REGIONS = [
    # The window's background on both sides of x = 300, where the window ends up across the border of the outputs.
    ('window red, left', (140, 150, 290, 250), (255, 0, 0)),
    ('window red, right', (310, 150, 390, 250), (255, 0, 0)),
    ('left GL magenta', (26, 26, 115, 65), (255, 0, 255)),
    ('right GL cyan', (406, 26, 495, 65), (0, 255, 255)),
]
# The window's x position in the layout where the script put it, None where the compositor decides.
POSITIONS = {0: 50, 1: 1586, 2: 1236, 3: 50, 4: None, 5: None}


def nodes(node):
    yield node
    for child in node.get('nodes', []) + node.get('floating_nodes', []):
        yield from nodes(child)


def check_phase(directory, phase):
    stem = 'phase-%d' % phase
    tree = json.loads((directory / (stem + '-tree.json')).read_text())
    outputs = {o['name']: o for o in json.loads((directory / (stem + '-outputs.json')).read_text())}
    matches = [n for n in nodes(tree) if n.get('name') == TITLE]
    assert len(matches) == 1 and matches[0]['shell'] == 'xdg_shell', (phase, 'the window')
    rect = matches[0]['rect']
    assert rect['width'] == 601 and rect['height'] == 401, (phase, rect)
    if POSITIONS[phase] is not None:
        assert rect['x'] == POSITIONS[phase], (phase, rect)
    images = {}
    result = []
    for name, (x0, y0, x1, y1), expected in REGIONS:
        left, right = rect['x'] + x0, rect['x'] + x1
        top, bottom = rect['y'] + rect['height'] - y1, rect['y'] + rect['height'] - y0
        home = [o for o in outputs.values()
                if o['rect']['x'] <= left and right <= o['rect']['x'] + o['rect']['width'] and
                o['rect']['y'] <= top and bottom <= o['rect']['y'] + o['rect']['height']]
        assert len(home) == 1, (phase, name, 'lies on one output', rect)
        output = home[0]
        scale = output['scale']
        if output['name'] not in images:
            path = str(directory / ('%s-%s.png' % (stem, output['name'])))
            width, height = map(int, subprocess.check_output(['magick', 'identify', '-format', '%w %h', path]).split())
            pixels = subprocess.check_output(['magick', path, '-depth', '8', 'RGB:-'])
            assert len(pixels) == width * height * 3
            images[output['name']] = (width, height, pixels)
        width, height, pixels = images[output['name']]
        box = (math.ceil((left - output['rect']['x']) * scale), math.ceil((top - output['rect']['y']) * scale),
               math.floor((right - output['rect']['x']) * scale), math.floor((bottom - output['rect']['y']) * scale))
        assert 0 <= box[0] < box[2] <= width and 0 <= box[1] < box[3] <= height, (phase, name, box)
        wanted = bytes(expected) * (box[2] - box[0])
        for y in range(box[1], box[3]):
            row = pixels[(y * width + box[0]) * 3:(y * width + box[2]) * 3]
            assert row == wanted, (phase, name, output['name'], scale, box, y)
        result.append({'phase': phase, 'region': name, 'output': output['name'], 'scale': scale, 'box': box,
                       'rgb': expected})
    return result


if __name__ == '__main__':
    directory = Path(sys.argv[1])
    print(json.dumps([r for phase in range(6) for r in check_phase(directory, phase)], indent=2))
