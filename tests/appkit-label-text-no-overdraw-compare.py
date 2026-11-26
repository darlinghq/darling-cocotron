#!/usr/bin/env python3
# Compares, for each scenario, the capture after the change (NAME-B) with the one of a window built in the final state
# (NAME-ref), both cropped at the magenta anchor; prints PASS or FAIL per scenario. Needs Pillow.
import sys, os
from PIL import Image
W, H = 420, 260
def crop(p):
    im = Image.open(p).convert("RGB"); px = im.load()
    for y in range(im.height - 8):
        for x in range(im.width - 8):
            if px[x, y] == (255, 0, 255) and px[x + 7, y + 7] == (255, 0, 255):
                return im.crop((x, y, x + W, y + H))
    return None
d = sys.argv[1]; bad = 0
for n in sorted({f.rsplit("-", 1)[0] for f in os.listdir(d) if f.endswith(".png")}):
    try:
        a, b, r = (crop(f"{d}/{n}-{k}.png") for k in ("A", "B", "ref"))
    except FileNotFoundError:
        print("FAIL", n, "missing capture"); bad += 1; continue
    if None in (a, b, r):
        print("FAIL", n, "window not found"); bad += 1; continue
    diff = sum(1 for p, q in zip(b.getdata(), r.getdata()) if p != q)
    changed = sum(1 for p, q in zip(a.getdata(), r.getdata()) if p != q)
    ok = diff == 0 and changed > 0
    print("PASS" if ok else "FAIL", n, "pixels differing from a fresh window:", diff, "(change visible:", changed, "px)")
    if not ok: bad += 1
print("ALL PASSED" if not bad else "FAILED")
sys.exit(1 if bad else 0)
