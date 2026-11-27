# Copyright (C) 2026 Lubos Dolezel
# Writes Assets.xcassets with one JPEG image set, Jpeg: 32 x 24 points, the top half solid red and the bottom half
# solid blue (flat blocks survive the lossy compression). The file is written as a PNG; convert it with
#   sips -s format jpeg -s formatOptions 100 jpeg.png --out Jpeg.imageset/jpeg.jpg
# (the script runs it when sips exists) because actool keeps a JPEG file as a JPEG rendition.
import json, os, struct, subprocess, sys, zlib

root = os.path.join(sys.argv[1], 'Assets.xcassets')
d = os.path.join(root, 'Jpeg.imageset')
os.makedirs(d, exist_ok=True)
json.dump({'info': {'version': 1, 'author': 'xcode'}}, open(os.path.join(root, 'Contents.json'), 'w'))

w, h = 32, 24
raw = b''.join(b'\0' + (bytes((255, 0, 0)) if y < h // 2 else bytes((0, 0, 255))) * w for y in range(h))
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
png = os.path.join(sys.argv[1], 'jpeg.png')
with open(png, 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n')
    f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
    f.write(chunk(b'IDAT', zlib.compress(raw)))
    f.write(chunk(b'IEND', b''))
subprocess.check_call(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '100', png, '--out', os.path.join(d, 'jpeg.jpg')])
json.dump({'images': [{'idiom': 'universal', 'filename': 'jpeg.jpg', 'scale': '1x'}], 'info': {'version': 1, 'author': 'xcode'}},
          open(os.path.join(d, 'Contents.json'), 'w'), indent=2)
