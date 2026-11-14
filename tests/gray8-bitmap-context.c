/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// 8-bit gray bitmap contexts (kCGImageAlphaNone, 8 bpc, 8 bpp; and gray with a last alpha, 16 bpp): the
// contexts exist, drawing converts to gray, and the pixels read back. The context is one of the supported
// pixel formats of the Quartz 2D Programming Guide ("Supported Pixel Formats"). Expected values were printed on
// macOS 26.7.3 (mac-probes/v470-bitmap-context-formats.c, black-box, tier 2). Also passes on macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fail;

static void expect(const char* label, int got, int want, int tol) {
	if (abs(got - want) > tol) {
		printf("FAIL %s: got %d, expected %d\n", label, got, want);
		g_fail++;
	}
}

static void expectTrue(const char* label, int ok) {
	if (!ok) {
		printf("FAIL %s\n", label);
		g_fail++;
	}
}

int main(void) {
	CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	unsigned char b[16];

	// kCGImageAlphaNone gray, rows exactly as wide as the image.
	memset(b, 0xEE, sizeof b);
	CGContextRef c = CGBitmapContextCreate(b, 4, 2, 8, 4, gray, kCGImageAlphaNone);
	expectTrue("gray8 context is created", c != NULL);
	if (c == NULL)
		return 1;
	expect("bits per pixel", (int)CGBitmapContextGetBitsPerPixel(c), 8, 0);
	expect("bits per component", (int)CGBitmapContextGetBitsPerComponent(c), 8, 0);
	expect("bytes per row", (int)CGBitmapContextGetBytesPerRow(c), 4, 0);
	expect("alpha info", (int)CGBitmapContextGetAlphaInfo(c), kCGImageAlphaNone, 0);
	expectTrue("gray color space", CGColorSpaceGetModel(CGBitmapContextGetColorSpace(c)) == kCGColorSpaceModelMonochrome);

	// One pixel column per color; row 0 of the buffer is the top row of the context.
	CGContextSetGrayFillColor(c, 0.5, 1);
	CGContextFillRect(c, CGRectMake(0, 0, 1, 2));
	CGContextSetGrayFillColor(c, 1, 1);
	CGContextFillRect(c, CGRectMake(1, 0, 1, 2));
	CGContextSetRGBFillColor(c, 0.2, 0.6, 0.9, 1);
	CGContextFillRect(c, CGRectMake(2, 0, 1, 2));
	CGContextSetRGBFillColor(c, 1, 0, 0, 1);
	CGContextFillRect(c, CGRectMake(3, 0, 1, 2));
	expect("gray 0.5", b[0], 128, 1);
	expect("white", b[1], 255, 0);
	// An RGB color becomes the gray of the same luminance, not a weighting of the encoded values.
	// QUIRK pinned by this check: see grayFromEncodedRGB in Onyx2D/O2Surface.m (54 would be the plain weighting).
	expect("rgb 0.2 0.6 0.9", b[2], 145, 2);
	expect("sRGB-ish red", b[3], 130, 2);
	expect("second row, gray 0.5", b[4], 128, 1);
	expect("second row, red", b[7], 130, 2);

	// 50% black over white, then the pixels as an image drawn into an RGBA context.
	CGContextSetGrayFillColor(c, 1, 1);
	CGContextFillRect(c, CGRectMake(0, 0, 4, 2));
	CGContextSetGrayFillColor(c, 0, 0.5);
	CGContextFillRect(c, CGRectMake(0, 0, 4, 2));
	expect("black 50% over white", b[0], 128, 1);
	CGContextSetGrayFillColor(c, 0.25, 1);
	CGContextFillRect(c, CGRectMake(0, 0, 4, 2));
	CGImageRef image = CGBitmapContextCreateImage(c);
	expectTrue("image of the gray context", image != NULL);
	if (image != NULL) {
		unsigned char o[16];
		memset(o, 0, sizeof o);
		CGContextRef rgba = CGBitmapContextCreate(o, 2, 2, 8, 8, rgb, kCGImageAlphaPremultipliedLast);
		CGContextDrawImage(rgba, CGRectMake(0, 0, 2, 2), image);
		expect("gray 0.25 drawn as RGB: red", o[0], 64, 1);
		expect("gray 0.25 drawn as RGB: green", o[1], 64, 1);
		expect("gray 0.25 drawn as RGB: blue", o[2], 64, 1);
		expect("gray 0.25 drawn as RGB: alpha", o[3], 255, 0);
		CGContextRelease(rgba);
		CGImageRelease(image);
	}
	CGContextRelease(c);

	// The context allocates its own buffer.
	c = CGBitmapContextCreate(NULL, 4, 3, 8, 0, gray, kCGImageAlphaNone);
	expectTrue("gray8 context with its own buffer", c != NULL);
	if (c != NULL) {
		expectTrue("own buffer rows hold a row", CGBitmapContextGetBytesPerRow(c) >= 4);
		expectTrue("own buffer exists", CGBitmapContextGetData(c) != NULL);
		CGContextRelease(c);
	}

	// Gray with a last alpha: two bytes per pixel, the gray premultiplied.
	memset(b, 0, sizeof b);
	c = CGBitmapContextCreate(b, 2, 1, 8, 4, gray, kCGImageAlphaPremultipliedLast);
	expectTrue("gray+alpha context is created", c != NULL);
	if (c != NULL) {
		expect("gray+alpha bits per pixel", (int)CGBitmapContextGetBitsPerPixel(c), 16, 0);
		CGContextSetGrayFillColor(c, 0.5, 0.5);
		CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
		CGContextSetGrayFillColor(c, 0.5, 1);
		CGContextFillRect(c, CGRectMake(1, 0, 1, 1));
		expect("premultiplied gray", b[0], 64, 1);
		expect("half alpha", b[1], 128, 1);
		expect("opaque gray", b[2], 128, 1);
		expect("opaque alpha", b[3], 255, 0);
		CGContextSetGrayFillColor(c, 1, 0.5);
		CGContextFillRect(c, CGRectMake(1, 0, 1, 1));
		expect("white 50% over opaque gray", b[2], 191, 1);
		CGContextRelease(c);
	}

	// Combinations that are not supported give NULL, as on macOS.
	expectTrue("row shorter than the width", CGBitmapContextCreate(b, 4, 1, 8, 3, gray, kCGImageAlphaNone) == NULL);
	expectTrue("gray with the alpha first", CGBitmapContextCreate(b, 4, 1, 8, 8, gray, kCGImageAlphaPremultipliedFirst) == NULL);
	expectTrue("gray 4 bits per component", CGBitmapContextCreate(b, 4, 1, 4, 4, gray, kCGImageAlphaNone) == NULL);

	CGColorSpaceRelease(gray);
	CGColorSpaceRelease(rgb);
	printf(g_fail == 0 ? "PASS\n" : "FAIL (%d)\n", g_fail);
	return g_fail != 0;
}
