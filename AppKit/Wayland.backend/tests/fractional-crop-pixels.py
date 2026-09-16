"""Check untouched compositor captures from fractional-crop.m (ImageMagick required)."""
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
    assert (rect['width'], rect['height']) == (601, 401)
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
        ('right crop lower-left', (553, 123, 597, 140), (255, 255, 0)),
        ('right crop upper-left', (553, 150, 597, 168), (0, 255, 0)),
        ('left crop lower-left', (3, 223, 17, 240), (255, 255, 0)),
        ('left crop lower-right', (25, 223, 68, 240), (0, 255, 255)),
        ('left crop upper-left', (3, 250, 17, 268), (0, 255, 0)),
        ('left crop upper-right', (25, 250, 68, 268), (0, 0, 255)),
        ('bottom crop lower-left', (353, 1, 397, 3), (255, 255, 0)),
        ('bottom crop lower-right', (405, 1, 448, 3), (0, 255, 255)),
        ('bottom crop upper-left', (353, 10, 397, 28), (0, 255, 0)),
        ('bottom crop upper-right', (405, 10, 448, 28), (0, 0, 255)),
        ('top crop lower-left', (353, 373, 397, 392), (255, 255, 0)),
        ('top crop lower-right', (405, 373, 448, 392), (0, 255, 255)),
        ('top crop upper-left', (353, 398, 397, 400), (0, 255, 0)),
        ('top crop upper-right', (405, 398, 448, 400), (0, 0, 255)),
        ('outside parent left', (-8, 223, -4, 268), (0, 0, 0)),
        ('outside parent above', (353, 405, 448, 409), (0, 0, 0)),
        ('outside parent below', (353, -7, 448, -3), (0, 0, 0)),
        ('left of clip', (543, 123, 547, 168), (255, 0, 0)),
        ('outside parent', (605, 123, 609, 168), (0, 0, 0)),
        ('below GL', (23, 13, 118, 17), (255, 0, 0)),
        ('above GL', (23, 74, 118, 78), (255, 0, 0)),
    ]
    result = []
    for name, (x0, y0, x1, y1), expected in regions:
        box = (math.ceil((rect['x'] + x0) * scale),
               math.ceil((rect['y'] + 401 - y1) * scale),
               math.floor((rect['x'] + x1) * scale),
               math.floor((rect['y'] + 401 - y0) * scale))
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
