/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// CGBitmapContextCreateWithData: the release callback is called with releaseInfo and the pixel
// buffer when the context is released, whether the caller supplied the buffer or the context
// allocated it (data NULL). Contract: Quartz 2D CGBitmapContextCreateWithData documentation.
// The "quirk" cases (callback also runs when creation fails, with the caller's data; here a too short bytesPerRow) were observed
// on macOS 26.7.3 (black-box, tier 2) and are pinned by Onyx2D's QUIRK comment in
// O2BitmapContext.m. The test passes on macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

static int g_fail, g_calls;
static void *g_info, *g_data;

static void release_cb(void *info, void *data) {
	g_calls++;
	g_info = info;
	g_data = data;
}

static void check(const char *label, int ok) {
	if (!ok) {
		printf("FAIL %s\n", label);
		g_fail++;
	}
}

int main(void) {
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	static unsigned char buf[4 * 4 * 4];
	int tag = 7;

	// Caller-supplied data.
	CGContextRef c = CGBitmapContextCreateWithData(buf, 4, 4, 8, 16, rgb,
			kCGImageAlphaPremultipliedLast, release_cb, &tag);
	check("context with data is created", c != NULL);
	if (c == NULL)
		return 1;
	check("callback not called while the context lives", g_calls == 0);
	check("context uses the caller's buffer", CGBitmapContextGetData(c) == buf);
	CGImageRef image = CGBitmapContextCreateImage(c);
	CGContextRelease(c);
	check("callback called once at context release", g_calls == 1);
	check("callback gets releaseInfo", g_info == &tag);
	check("callback gets the caller's data", g_data == buf);
	CGImageRelease(image);
	check("image release does not call it again", g_calls == 1);

	// Context-allocated data: the callback gets the context's own buffer.
	g_calls = 0;
	g_data = NULL;
	c = CGBitmapContextCreateWithData(NULL, 4, 4, 8, 0, rgb,
			kCGImageAlphaPremultipliedLast, release_cb, &tag);
	check("context with NULL data is created", c != NULL);
	if (c == NULL)
		return 1;
	void *own = CGBitmapContextGetData(c);
	check("context allocated its buffer", own != NULL);
	CGContextRelease(c);
	check("callback called once for allocated data", g_calls == 1);
	check("callback gets the allocated buffer", g_data == own && own != NULL);

	// NULL callback is allowed.
	c = CGBitmapContextCreateWithData(buf, 4, 4, 8, 16, rgb,
			kCGImageAlphaPremultipliedLast, NULL, NULL);
	check("NULL callback is accepted", c != NULL);
	CGContextRelease(c);

	// Quirk: creation failures call the callback with the caller's data.
	g_calls = 0;
	c = CGBitmapContextCreateWithData(buf, 4, 4, 8, 4, rgb,
			kCGImageAlphaPremultipliedLast, release_cb, &tag);
	check("quirk: too short bytesPerRow fails", c == NULL);
	check("quirk: callback called once on short row", g_calls == 1);
	check("quirk: callback gets releaseInfo and data on short row", g_info == &tag && g_data == buf);

	CGColorSpaceRelease(rgb);
	if (g_fail == 0)
		printf("PASS\n");
	return g_fail != 0;
}
