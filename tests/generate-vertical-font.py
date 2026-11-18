#!/usr/bin/env python3
"""Generate the vertical-metrics fixture with FontTools 4.66.1 (MIT).

Usage: python generate-vertical-font.py OUTPUT_DIRECTORY
Writes DarlingVerticalTest.ttf: 1000 units per em, three glyphs (A, B, C) whose horizontal advances
(500, 300, 800) and vertical advances (1000, 600, 1200) are all different, so a test can tell which
metric a call returned. The font carries real vhea and vmtx tables.
"""
import pathlib
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

NAMES = [".notdef", "A", "B", "C"]
HORIZONTAL = {".notdef": 500, "A": 500, "B": 300, "C": 800}
VERTICAL = {".notdef": 1000, "A": 1000, "B": 600, "C": 1200}

builder = FontBuilder(1000, isTTF=True)
builder.setupGlyphOrder(NAMES)
builder.setupCharacterMap({65 + index: name for index, name in enumerate(NAMES[1:])})
glyphs = {}
for name in NAMES:
    pen = TTGlyphPen(None)
    pen.moveTo((50, 0))
    pen.lineTo((HORIZONTAL[name] - 50, 0))
    pen.lineTo((HORIZONTAL[name] - 50, 700))
    pen.lineTo((50, 700))
    pen.closePath()
    glyphs[name] = pen.glyph()
builder.setupGlyf(glyphs)
builder.setupHorizontalMetrics({name: (HORIZONTAL[name], 50) for name in NAMES})
builder.setupHorizontalHeader(ascent=800, descent=-200)
builder.setupVerticalMetrics({name: (VERTICAL[name], 0) for name in NAMES})
builder.setupVerticalHeader(ascent=500, descent=-500)
builder.setupNameTable({
    "familyName": "DarlingVerticalTest", "styleName": "Regular",
    "uniqueFontIdentifier": "DarlingVerticalTest-Regular",
    "fullName": "DarlingVerticalTest Regular", "psName": "DarlingVerticalTest-Regular",
    "version": "Version 1.0",
})
builder.setupOS2(sTypoAscender=800, sTypoDescender=-200,
                usWinAscent=800, usWinDescent=200, sCapHeight=700, sxHeight=500)
builder.setupPost()
builder.font.recalcTimestamp = False
builder.font["head"].created = builder.font["head"].modified = 2082844800
output = pathlib.Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
builder.save(output / "DarlingVerticalTest.ttf")
