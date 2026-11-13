/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Glyph drawing through the FreeType backend: the per-font raster cache must
 * give the same pixels as a fresh render whatever was drawn before, and caller
 * supplied advances place the glyphs.
 */
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

typedef struct { long minx, maxx, miny, maxy; unsigned long hash; } Ink;

static CGContextRef bitmap(void)
{
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef c = CGBitmapContextCreate(NULL, 320, 160, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(cs);
	CGContextSetRGBFillColor(c, 0, 0, 0, 1);
	return c;
}

static Ink inkAndClear(CGContextRef c)
{
	size_t w = CGBitmapContextGetWidth(c), h = CGBitmapContextGetHeight(c), bpr = CGBitmapContextGetBytesPerRow(c);
	const unsigned char *p = CGBitmapContextGetData(c);
	Ink r = { (long)w, -1, (long)h, -1, 5381 };
	for (size_t y = 0; y < h; y++)
		for (size_t x = 0; x < w; x++) {
			unsigned a = p[y * bpr + x * 4 + 3];
			r.hash = r.hash * 33 + a;
			if (a > 128) {
				if ((long)x < r.minx) r.minx = x;
				if ((long)x > r.maxx) r.maxx = x;
				if ((long)y < r.miny) r.miny = y;
				if ((long)y > r.maxy) r.maxy = y;
			}
		}
	memset(CGBitmapContextGetData(c), 0, bpr * h);
	return r;
}

static CGFontRef font;
static CGGlyph gH, gI;

static Ink draw(CGContextRef c, CGFloat size, CGFloat x, CGFloat y)
{
	CGContextSetFont(c, font);
	CGContextSetFontSize(c, size);
	CGContextSetTextMatrix(c, CGAffineTransformIdentity);
	CGContextShowGlyphsAtPoint(c, x, y, &gH, 1);
	return inkAndClear(c);
}

int main(void)
{
	CTFontRef ct = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
	font = CTFontCopyGraphicsFont(ct, NULL);
	UniChar chars[2] = { 'H', 'I' };
	CGGlyph glyphs[2];
	if (!CTFontGetGlyphsForCharacters(ct, chars, glyphs, 2)) {
		printf("FAIL: no glyphs\n");
		return 1;
	}
	gH = glyphs[0];
	gI = glyphs[1];
	CGContextRef c = bitmap();

	/* The same size after other sizes gives the same pixels. */
	Ink a = draw(c, 20, 50, 40);
	Ink b = draw(c, 40, 50, 40);
	Ink a2 = draw(c, 20, 50, 40);
	CHECK(a.maxx >= 0, "nothing drawn");
	CHECK(a.hash == a2.hash, "20 pt render differs after a 40 pt render");
	CHECK((b.maxy - b.miny) >= 2 * (a.maxy - a.miny) - 2, "40 pt glyph height %ld not about twice the 20 pt one %ld", b.maxy - b.miny, a.maxy - a.miny);

	/* A scale in the text matrix and the same size set directly give the
	 * same glyph shape: the cache key follows the effective pixel size. */
	CGContextSetFont(c, font);
	CGContextSetFontSize(c, 10);
	CGContextSetTextMatrix(c, CGAffineTransformMakeScale(2, 2));
	CGContextShowGlyphsAtPoint(c, 25, 20, &gH, 1);
	Ink scaled = inkAndClear(c);
	CHECK(labs((scaled.maxy - scaled.miny) - (a.maxy - a.miny)) <= 1 && labs((scaled.maxx - scaled.minx) - (a.maxx - a.minx)) <= 1,
	      "text matrix scale 2 at 10 pt: ink %ldx%ld, 20 pt: %ldx%ld", scaled.maxx - scaled.minx, scaled.maxy - scaled.miny, a.maxx - a.minx, a.maxy - a.miny);
	Ink a3 = draw(c, 20, 50, 40);
	CHECK(a3.hash == a.hash, "20 pt render differs after a scaled-matrix render");

	/* The antialiasing flag does not leak into later draws. */
	CGContextSetShouldAntialias(c, false);
	draw(c, 20, 50, 40);
	CGContextSetShouldAntialias(c, true);
	Ink a4 = draw(c, 20, 50, 40);
	CHECK(a4.hash == a.hash, "render differs after toggling antialiasing");

	/* Many distinct sizes exceed the cache bounds; results stay correct. */
	for (int i = 0; i < 900; i++)
		draw(c, 8 + i / 64.0, 10, 40);
	Ink a5 = draw(c, 20, 50, 40);
	CHECK(a5.hash == a.hash, "20 pt render differs after the cache was overrun");

	/* Large glyph: drawn (clipped to the bitmap), no crash, no leftover state. */
	draw(c, 1500, 0, 0);
	Ink a6 = draw(c, 20, 50, 40);
	CHECK(a6.hash == a.hash, "20 pt render differs after a very large glyph");

	/* Caller supplied advances place the glyphs: the second glyph starts
	 * 60 units after the first, not where the font metrics put it. */
	CGGlyph two[2] = { gI, gI };
	CGSize adv[2] = { CGSizeMake(60, 0), CGSizeMake(0, 0) };
	CGContextSetFont(c, font);
	CGContextSetFontSize(c, 20);
	CGContextSetTextMatrix(c, CGAffineTransformIdentity);
	CGContextSetTextPosition(c, 20, 40);
	CGContextShowGlyphsWithAdvances(c, two, adv, 2);
	Ink pair = inkAndClear(c);
	Ink single = draw(c, 20, 20, 40);
	long width = single.maxx - single.minx;
	CHECK(pair.maxx - pair.minx >= 60 && pair.maxx - pair.minx <= 60 + width + 1,
	      "pair ink width %ld, expected about 60 + %ld", pair.maxx - pair.minx, width);

	/* The text position moves by the supplied advances. */
	CGContextSetTextPosition(c, 20, 40);
	CGContextShowGlyphsWithAdvances(c, two, adv, 2);
	CGPoint pos = CGContextGetTextPosition(c);
	CHECK(pos.x == 80 && pos.y == 40, "text position after advances (%g,%g), expected (80,40)", pos.x, pos.y);
	inkAndClear(c);

	/* Zero count and NULL glyphs are accepted without drawing. */
	CGContextShowGlyphsWithAdvances(c, two, adv, 0);
	CGContextShowGlyphsWithAdvances(c, NULL, adv, 2);
	Ink none = inkAndClear(c);
	CHECK(none.maxx < 0, "degenerate calls drew something");

	CGContextRelease(c);
	CGFontRelease(font);
	CFRelease(ct);
	printf(failures ? "FAILED %d\n" : "PASS\n", failures);
	return failures != 0;
}
