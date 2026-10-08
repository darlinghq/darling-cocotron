"""Generate authored fixtures with Pillow 11.3.0 (HPND license)."""
import hashlib
import json
from pathlib import Path
import sys

import PIL
from PIL import ExifTags, Image

if PIL.__version__ != "11.3.0":
    raise SystemExit("use pinned Pillow 11.3.0")
output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (3, 2), (20, 80, 140))
image.save(output / "plain.jpg", quality=90)
exif = Image.Exif()
exif[ExifTags.Base.Orientation] = 6
image.save(output / "exif.jpg", quality=90, exif=exif)

data = bytearray((output / "plain.jpg").read_bytes())
position = 2
found_frame = False
while position < len(data):
    if data[position] != 0xff:
        raise SystemExit("expected JPEG marker")
    marker = data[position + 1]
    length = int.from_bytes(data[position + 2:position + 4], "big")
    end = position + 2 + length
    if marker == 0xc0:
        data[position + 5:position + 9] = (60000).to_bytes(2, "big") * 2
        found_frame = True
    if marker == 0xda:
        if not found_frame:
            raise SystemExit("missing baseline frame header")
        (output / "large-header.jpg").write_bytes(data[:end])
        break
    position = end
else:
    raise SystemExit("missing scan header")

(output / "malformed.jpg").write_bytes(bytes.fromhex("ffd8 ffc0 0002"))
(output / "soi-only.jpg").write_bytes(bytes.fromhex("ffd8"))
manifest = {
    "generator": "Pillow 11.3.0, HPND",
    "complete_images": ["plain.jpg", "exif.jpg"],
    "incomplete_raster_with_header": "large-header.jpg",
    "malformed_headers": ["malformed.jpg", "soi-only.jpg"],
    "sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
               for p in output.glob("*.jpg")},
}
(output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
