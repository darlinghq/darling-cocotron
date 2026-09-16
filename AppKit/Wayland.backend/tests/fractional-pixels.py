"""Check untouched compositor captures from fractional-live.m (ImageMagick required)."""
import json
import math
from pathlib import Path
import subprocess


def check_capture(directory, scale):
    directory = Path(directory)
    stem = 'scale-' + str(scale)
    tree = json.loads((directory / (stem + '-tree.json')).read_text())

    def nodes(node):
        yield node
        for child in node.get('nodes', []) + node.get('floating_nodes', []):
            yield from nodes(child)

    matches = [n for n in nodes(tree) if n.get('name') == 'Fractional live fixture']
    assert len(matches) == 1 and matches[0]['shell'] == 'xdg_shell'
    rect = matches[0]['rect']
    assert (rect['width'], rect['height']) == (601, 422)
    path = str(directory / (stem + '.png'))
    width, height = map(int, subprocess.check_output(['magick', 'identify', '-format', '%w %h', path]).split())
    pixels = subprocess.check_output(['magick', path, '-depth', '8', 'RGB:-'])
    assert len(pixels) == width * height * 3
    # Coordinates are AppKit content coordinates, bottom left origin. Sample
    # comfortably inside each region to avoid compositor edge filtering.
    regions = [
        ('CPU red', (350, 200, 390, 240), (255, 0, 0)),
        ('GL magenta', (23, 23, 118, 68), (255, 0, 255)),
        ('layer blue', (203, 23, 300, 70), (0, 0, 255)),
        ('clipped GL cyan', (553, 123, 598, 168), (0, 255, 255)),
        ('left of clip', (543, 123, 547, 168), (255, 0, 0)),
        ('outside parent', (605, 123, 609, 168), (0, 0, 0)),
        ('below GL', (23, 13, 118, 17), (255, 0, 0)),
        ('above GL', (23, 74, 118, 78), (255, 0, 0)),
    ]
    result = []
    for name, (x0, y0, x1, y1), expected in regions:
        box = (math.ceil((rect['x'] + x0) * scale),
               math.ceil((rect['y'] + 422 - y1) * scale),
               math.floor((rect['x'] + x1) * scale),
               math.floor((rect['y'] + 422 - y0) * scale))
        assert 0 <= box[0] < box[2] <= width and 0 <= box[1] < box[3] <= height
        wanted = bytes(expected) * (box[2] - box[0])
        for y in range(box[1], box[3]):
            row = pixels[(y * width + box[0]) * 3:(y * width + box[2]) * 3]
            assert row == wanted, (name, scale, box, y)
        result.append({'region': name, 'box': box, 'pixels': (box[2]-box[0]) * (box[3]-box[1]), 'rgb': expected})
    return result


if __name__ == '__main__':
    import sys
    print(json.dumps({str(s): check_capture(sys.argv[1], s) for s in (1.25, 1.5, 1.75)}, indent=2))
