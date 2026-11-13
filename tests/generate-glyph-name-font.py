#!/usr/bin/env python3
"""Generate authored glyph-name fixtures with FontTools 4.66.1 (MIT).

Usage: python generate-glyph-name-font.py OUTPUT_DIRECTORY
The 150-character name tests FreeType's tolerant input boundary; it exceeds
OpenType's 63-character naming constraint and is not a conforming font.
"""
import pathlib
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def build(path, names, keep_names=True):
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(names)
    builder.setupCharacterMap({65 + index: name for index, name in enumerate(names[1:])})
    glyphs = {}
    for name in names:
        pen = TTGlyphPen(None)
        pen.moveTo((50, 0))
        pen.lineTo((450, 0))
        pen.lineTo((450, 700))
        pen.lineTo((50, 700))
        pen.closePath()
        glyphs[name] = pen.glyph()
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (500, 50) for name in names})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({
        "familyName": "DarlingGlyphNameTest", "styleName": "Regular",
        "uniqueFontIdentifier": "DarlingGlyphNameTest-Regular",
        "fullName": "DarlingGlyphNameTest Regular", "psName": "DarlingGlyphNameTest-Regular",
        "version": "Version 1.0",
    })
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200,
                    usWinAscent=800, usWinDescent=200, sCapHeight=700, sxHeight=500)
    builder.setupPost(keepGlyphNames=keep_names)
    builder.font.recalcTimestamp = False
    builder.font["head"].created = builder.font["head"].modified = 2082844800
    builder.save(path)


output = pathlib.Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
build(output / "conforming.ttf", [".notdef", "A", "n" * 63])
build(output / "tolerated-long.ttf", [".notdef", "A", "g" * 150])
build(output / "nameless.ttf", [".notdef", "A"], keep_names=False)
