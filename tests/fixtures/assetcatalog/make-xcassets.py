# Copyright (C) 2026 Lubos Dolezel
# Writes Assets.xcassets, the input for the asset catalog test fixture: small
# PNG and PDF images drawn here, compiled with actool on a Mac.
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

def pdf(path, size):
    content = b'1 0 0 rg 0 0 %d %d re f\n' % (size, size)
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R >>' % (size, size),
               b'<< /Length %d >>\nstream\n' % len(content) + content + b'endstream']
    out = b'%PDF-1.4\n'
    offsets = []
    for i, o in enumerate(objects):
        offsets.append(len(out))
        out += b'%d 0 obj\n' % (i + 1) + o + b'\nendobj\n'
    xref = len(out)
    out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1)
    out += b''.join(b'%010d 00000 n \n' % o for o in offsets)
    out += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
    open(path, 'wb').write(out)

def imageset(root, name, images, properties=None):
    d = os.path.join(root, name + '.imageset')
    os.makedirs(d, exist_ok=True)
    entries = []
    for filename, scale, writer in images:
        writer(os.path.join(d, filename))
        entry = {'idiom': 'universal', 'filename': filename}
        if scale:
            entry['scale'] = scale
        entries.append(entry)
    contents = {'images': entries, 'info': {'version': 1, 'author': 'xcode'}}
    if properties:
        contents['properties'] = properties
    json.dump(contents, open(os.path.join(d, 'Contents.json'), 'w'), indent=2)

root = os.path.join(sys.argv[1], 'Assets.xcassets')
os.makedirs(root, exist_ok=True)
json.dump({'info': {'version': 1, 'author': 'xcode'}}, open(os.path.join(root, 'Contents.json'), 'w'))
# red top half, blue bottom half, opaque
halves = lambda w, h: (lambda x, y: (255, 0, 0, 255) if y < h // 2 else (0, 0, 255, 255))
imageset(root, 'Halves', [('halves.png', '1x', lambda p: png(p, 20, 10, halves(20, 10), 'RGB')),
                          ('halves@2x.png', '2x', lambda p: png(p, 40, 20, halves(40, 20), 'RGB'))])
# green at half alpha
imageset(root, 'Translucent', [('translucent.png', '1x', lambda p: png(p, 12, 12, lambda x, y: (0, 255, 0, 128)))])
# gray 128 opaque on the left, clear on the right
imageset(root, 'Gray', [('gray.png', '1x', lambda p: png(p, 16, 16, lambda x, y: (128, 255) if x < 8 else (0, 0), 'GA'))])
# a large opaque image, red top half and blue bottom half
imageset(root, 'Large', [('large.png', '1x', lambda p: png(p, 300, 200, halves(300, 200), 'RGB'))])
# a red square as a PDF with its vector data kept
imageset(root, 'Vector', [('vector.pdf', None, lambda p: pdf(p, 16))], {'preserves-vector-representation': True})
# a template image
imageset(root, 'Template', [('template.png', '1x', lambda p: png(p, 16, 16, lambda x, y: (0, 0, 0, 255 if (x + y) % 2 else 0)))],
         {'template-rendering-intent': 'template'})
