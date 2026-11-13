/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CTFontDrawGlyphs and the context state it leaves behind.
 *
 * Contract: the glyphs are drawn at the given positions with the font; the
 * positions go through the context's text matrix like those of
 * CGContextShowGlyphsAtPositions.
 *
 * test_quirk_font_and_size_stay_set covers the QUIRK in CTFontDrawGlyphs:
 * after the call the context's font and font size are those of the CTFont
 * (observed on macOS 26.7.3), while the text matrix and text position are
 * unchanged.
 */
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

typedef struct { long minx, maxx, miny, maxy; } Ink;

static CGContextRef bitmap(void)
{
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef c = CGBitmapContextCreate(NULL, 240, 120, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(cs);
	CGContextSetRGBFillColor(c, 0, 0, 0, 1);
	return c;
}

static Ink ink(CGContextRef c)
{
	size_t w = CGBitmapContextGetWidth(c), h = CGBitmapContextGetHeight(c), bpr = CGBitmapContextGetBytesPerRow(c);
	const unsigned char *p = CGBitmapContextGetData(c);
	Ink r = { (long)w, -1, (long)h, -1 };
	for (size_t y = 0; y < h; y++)
		for (size_t x = 0; x < w; x++)
			if (p[y * bpr + x * 4 + 3] > 128) {
				if ((long)x < r.minx) r.minx = x;
				if ((long)x > r.maxx) r.maxx = x;
				if ((long)y < r.miny) r.miny = y;
				if ((long)y > r.maxy) r.maxy = y;
			}
	memset(CGBitmapContextGetData(c), 0, bpr * h);
	return r;
}

int main(void)
{
	CTFontRef big = CTFontCreateWithName(CFSTR("Helvetica"), 40, NULL);
	CGFontRef cgf = CTFontCopyGraphicsFont(big, NULL);
	UniChar ch = 'H';
	CGGlyph g;
	if (!CTFontGetGlyphsForCharacters(big, &ch, &g, 1)) {
		printf("FAIL: no glyph\n");
		return 1;
	}
	CGPoint at = CGPointMake(100, 20);

	/* Reference ink of the same glyph at 10 pt through CoreGraphics. */
	CGContextRef c = bitmap();
	CGContextSetFont(c, cgf);
	CGContextSetFontSize(c, 10);
	CGContextShowGlyphsAtPositions(c, &g, &at, 1);
	Ink small = ink(c);
	CGContextShowGlyphsAtPositions(c, &g, &at, 1);
	Ink small2 = ink(c);
	CHECK(small.maxx >= 0 && small2.maxy - small2.miny == small.maxy - small.miny, "reference glyph");

	/* test_quirk_font_and_size_stay_set */
	CGContextSetTextMatrix(c, CGAffineTransformIdentity);
	CGContextSetTextPosition(c, 3, 4);
	CTFontDrawGlyphs(big, &g, &at, 1, c);
	Ink viaCT = ink(c);
	CHECK(viaCT.maxx >= 0, "CTFontDrawGlyphs drew nothing");
	CHECK((viaCT.maxy - viaCT.miny) > 3 * (small.maxy - small.miny), "CT glyph height %ld not about 4x the 10 pt one %ld", viaCT.maxy - viaCT.miny, small.maxy - small.miny);
	CGContextShowGlyphsAtPositions(c, &g, &at, 1);
	Ink after = ink(c);
	CHECK(after.maxx >= 0 && after.maxy - after.miny == viaCT.maxy - viaCT.miny,
	      "font size did not stay set: plain CG draw height %ld, CT draw height %ld", after.maxy - after.miny, viaCT.maxy - viaCT.miny);
	CGPoint pos = CGContextGetTextPosition(c);
	CHECK(pos.x == 3 && pos.y == 4, "text position changed to (%g,%g)", pos.x, pos.y);

	/* Also with no CG font ever set on the context. */
	CGContextRef fresh = bitmap();
	CTFontDrawGlyphs(big, &g, &at, 1, fresh);
	ink(fresh);
	CGContextShowGlyphsAtPositions(fresh, &g, &at, 1);
	Ink freshAfter = ink(fresh);
	CHECK(freshAfter.maxx >= 0 && freshAfter.maxy - freshAfter.miny == viaCT.maxy - viaCT.miny, "font not set on a fresh context");
	CGContextRelease(fresh);

	/* Text matrix unchanged; applied to the glyph position (shear moves the
	 * origin sideways by c * y). */
	CGAffineTransform shear = CGAffineTransformMake(1, 0, 0.5, 1, 0, 0);
	CGContextSetTextMatrix(c, CGAffineTransformIdentity);
	CTFontDrawGlyphs(big, &g, &at, 1, c);
	Ink plain = ink(c);
	CGContextSetTextMatrix(c, shear);
	CTFontDrawGlyphs(big, &g, &at, 1, c);
	Ink sheared = ink(c);
	CGAffineTransform tm = CGContextGetTextMatrix(c);
	CHECK(CGAffineTransformEqualToTransform(tm, shear), "text matrix changed to (%g,%g,%g,%g,%g,%g)", tm.a, tm.b, tm.c, tm.d, tm.tx, tm.ty);
	CHECK(sheared.minx - plain.minx >= 8 && sheared.minx - plain.minx <= 12, "shear moved the glyph origin by %ld, expected about 10", sheared.minx - plain.minx);

	/* Degenerate arguments do not draw and do not crash. */
	CTFontDrawGlyphs(big, &g, &at, 0, c);
	CTFontDrawGlyphs(big, NULL, &at, 1, c);
	CTFontDrawGlyphs(big, &g, NULL, 1, c);
	CTFontDrawGlyphs(big, &g, &at, 1, NULL);

	CGContextRelease(c);
	CGFontRelease(cgf);
	CFRelease(big);
	printf(failures ? "FAILED %d\n" : "PASS\n", failures);
	return failures != 0;
}
