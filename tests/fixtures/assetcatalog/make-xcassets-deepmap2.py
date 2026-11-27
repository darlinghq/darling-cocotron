# Copyright (C) 2026 Lubos Dolezel
# Writes Assets.xcassets: small images in distinct colours (packed into shared sheets by actool),
# and a vector image set from an SVG.
import json, os, struct, sys, zlib

def png(path, width, height, pixel, mode='RGBA'):
    channels = {'RGBA': 4, 'RGB': 3, 'GA': 2}[mode]
    color = {'RGBA': 6, 'RGB': 2, 'GA': 4}[mode]
    raw = b''.join(b'\0' + b''.join(bytes(pixel(x, y)[:channels]) for x in range(width)) for y in range(height))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, color, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw)))
        f.write(chunk(b'IEND', b''))

def imageset(root, name, files, properties=None):
    d = os.path.join(root, name + '.imageset')
    os.makedirs(d, exist_ok=True)
    entries = []
    for filename, scale, writer in files:
        writer(os.path.join(d, filename))
        e = {'idiom': 'universal', 'filename': filename}
        if scale: e['scale'] = scale
        entries.append(e)
    c = {'images': entries, 'info': {'version': 1, 'author': 'xcode'}}
    if properties: c['properties'] = properties
    json.dump(c, open(os.path.join(d, 'Contents.json'), 'w'), indent=2)

root = os.path.join(sys.argv[1], 'Assets.xcassets')
os.makedirs(root, exist_ok=True)
json.dump({'info': {'version': 1, 'author': 'xcode'}}, open(os.path.join(root, 'Contents.json'), 'w'))
# Twelve small opaque images Pack0..Pack11 of (12 + i) x (10 + i % 3) points, and the grey image PackGA of 64 x 64
# with alpha. Every pixel differs from its neighbours, so that the compressor has to store them (an image of one
# colour, or a regular one, is stored in a shorter form). The colour of pixel (x, y) of image k is the three bytes
# of the hash below (the same function is in tests/appkit-asset-catalog-deepmap2.m); PackGA is black, its alpha
# the second byte.
def hash_rgb(k, x, y):
    h = ((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xffffffff
    return (h & 255, (h >> 8) & 255, (h >> 16) & 255)
for i in range(12):
    w, h = 12 + i, 10 + (i % 3)
    imageset(root, 'Pack%d' % i, [('p%d.png' % i, '1x',
        lambda p, i=i, w=w, h=h: png(p, w, h, lambda x, y: hash_rgb(i, x, y), 'RGB'))])
imageset(root, 'PackGA', [('ga.png', '1x', lambda p: png(p, 64, 64, lambda x, y: (0, hash_rgb(100, x, y)[1]), 'GA'))])
# Vector
d = os.path.join(root, 'Vec.imageset'); os.makedirs(d, exist_ok=True)
open(os.path.join(d, 'vec.svg'), 'w').write(
  '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">'
  '<rect x="2" y="2" width="16" height="16" fill="#ff0000"/>'
  '<path d="M6 6 L14 6 L14 14 L6 14 Z" fill="#0000ff"/></svg>')
json.dump({'images': [{'idiom': 'universal', 'filename': 'vec.svg'}], 'info': {'version': 1, 'author': 'xcode'},
           'properties': {'preserves-vector-representation': True}}, open(os.path.join(d, 'Contents.json'), 'w'), indent=2)
