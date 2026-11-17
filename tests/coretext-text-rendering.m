// Copyright (C) 2026 Lubos Dolezel
//
// Text rendering settings of a bitmap context, checked on pixels:
//  - font smoothing (default on) makes text darker than with it off, and the
//    AppleFontSmoothing default of 0 turns it off;
//  - with antialiasing off every pixel is fully covered or not covered;
//  - text at x + 0.25 renders differently from text at x when subpixel
//    positioning is allowed (the default), and identically when it is not;
//  - a fractional size renders differently from the truncated size;
//  - rotated text is rotated.
// Coverage totals measured on macOS 10.14.4 with the same DejaVu Sans file are
// compared with a tolerance; the renderings are not expected to be pixel-identical.
// usage: coretext-text-rendering tests/fixtures/fonts/DejaVuSans.ttf
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;
static void expect(int ok, const char *what) {
	if (ok) printf("PASS: %s\n", what);
	else { printf("FAIL: %s\n", what); failures++; }
}

enum { W = 220, H = 40 };
typedef struct { int smooth, aa, allowSub, sub; double x, size, rot; int single; } Settings;
typedef struct { unsigned char px[W * H]; long sum; int partial; int minX, maxX, minY, maxY; } Image;

static CTFontRef baseFont;

static void render(Settings s, Image *img) {
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, W * 4, cs,
			kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGContextFillRect(ctx, CGRectMake(0, 0, W, H));
	CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
	if (s.smooth >= 0) CGContextSetShouldSmoothFonts(ctx, s.smooth);
	if (s.aa >= 0) CGContextSetShouldAntialias(ctx, s.aa);
	if (s.allowSub >= 0) CGContextSetAllowsFontSubpixelPositioning(ctx, s.allowSub);
	if (s.sub >= 0) CGContextSetShouldSubpixelPositionFonts(ctx, s.sub);
	CTFontRef f = CTFontCreateCopyWithAttributes(baseFont, s.size, NULL, NULL);
	CFStringRef keys[1] = { kCTFontAttributeName };
	CFTypeRef values[1] = { f };
	CFDictionaryRef attrs = CFDictionaryCreate(NULL, (const void **) keys, (const void **) values, 1,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFAttributedStringRef as = CFAttributedStringCreate(NULL, s.single ? CFSTR("H") : CFSTR("Hamburgefonstiv. Illil"), attrs);
	CTLineRef line = CTLineCreateWithAttributedString(as);
	CGContextTranslateCTM(ctx, s.x, 12);
	CGContextRotateCTM(ctx, s.rot * M_PI / 180);
	CGContextSetTextPosition(ctx, 0, 0);
	CTLineDraw(line, ctx);
	const unsigned char *p = CGBitmapContextGetData(ctx);
	memset(img, 0, sizeof *img);
	img->minX = W; img->minY = H; img->maxX = img->maxY = -1;
	for (int y = 0; y < H; y++)
		for (int x = 0; x < W; x++) {
			int cov = 255 - p[y * W * 4 + x * 4 + 1];
			img->px[y * W + x] = cov;
			img->sum += cov;
			if (cov > 0 && cov < 255) img->partial++;
			if (cov > 0) {
				if (x < img->minX) img->minX = x;
				if (x > img->maxX) img->maxX = x;
				if (y < img->minY) img->minY = y;
				if (y > img->maxY) img->maxY = y;
			}
		}
	CFRelease(line); CFRelease(as); CFRelease(attrs); CFRelease(f);
	CGContextRelease(ctx); CGColorSpaceRelease(cs);
}

static int same(const Image *a, const Image *b) { return memcmp(a->px, b->px, sizeof a->px) == 0; }

static void within(const char *what, long got, long want, double tolerance) {
	char name[128];
	snprintf(name, sizeof name, "%s: %ld within %.0f%% of macOS %ld", what, got, tolerance * 100, want);
	expect(fabs((double) got - want) <= tolerance * want, name);
}

int main(int argc, char **argv) {
	@autoreleasepool {
		if (argc < 2) { printf("usage: coretext-text-rendering DejaVuSans.ttf\n"); return 2; }
		NSData *data = [NSData dataWithContentsOfFile: [NSString stringWithUTF8String: argv[1]]];
		CGDataProviderRef dp = CGDataProviderCreateWithCFData((CFDataRef) data);
		CGFontRef cg = CGFontCreateWithDataProvider(dp);
		if (!cg) { printf("FAIL: font loads\n"); return 1; }
		baseFont = CTFontCreateWithGraphicsFont(cg, 13, NULL, NULL);

		static Image on, off, aliased, x0, x25, nosub0, nosub25, trunc13, frac134, up, rot90, zero, rot30, big, bigOff;
		render((Settings){ 1, 1, -1, -1, 10.0, 13, 0 }, &on);
		render((Settings){ 0, 1, -1, -1, 10.0, 13, 0 }, &off);
		expect(on.sum > off.sum * 1.05, "smoothing on is darker than smoothing off");
		expect(off.sum > 0 && off.partial > 0, "smoothed-off text is antialiased");

		render((Settings){ 1, 0, -1, -1, 10.0, 13, 0 }, &aliased);
		int onlyBinary = aliased.sum > 0;
		for (int i = 0; i < W * H; i++)
			if (aliased.px[i] != 0 && aliased.px[i] != 255) onlyBinary = 0;
		expect(onlyBinary, "aliased text has only 0 or 255 coverage");

		render((Settings){ 1, 1, 1, 1, 10.0, 13, 0 }, &x0);
		render((Settings){ 1, 1, 1, 1, 10.25, 13, 0 }, &x25);
		expect(!same(&x0, &x25), "text at x+0.25 differs from x+0 with subpixel positioning");
		// Without subpixel positioning each glyph origin snaps to a whole pixel, so a
		// single glyph does not move for a quarter pixel (a string would, as the
		// fractional advances accumulate).
		render((Settings){ 1, 1, 0, 1, 10.0, 13, 0, 1 }, &nosub0);
		render((Settings){ 1, 1, 0, 1, 10.25, 13, 0, 1 }, &nosub25);
		expect(same(&nosub0, &nosub25), "a glyph at x+0.25 equals one at x+0 without subpixel positioning");
		render((Settings){ 1, 1, 1, 0, 10.0, 13, 0, 1 }, &nosub0);
		render((Settings){ 1, 1, 1, 0, 10.25, 13, 0, 1 }, &nosub25);
		expect(same(&nosub0, &nosub25), "a glyph at x+0.25 equals one at x+0 with positioning not requested");
		render((Settings){ 1, 1, 1, 1, 10.0, 13, 0, 1 }, &nosub0);
		render((Settings){ 1, 1, 1, 1, 10.25, 13, 0, 1 }, &nosub25);
		expect(!same(&nosub0, &nosub25), "a glyph at x+0.25 differs from one at x+0 with subpixel positioning");

		render((Settings){ 1, 1, -1, -1, 10.0, 13, 0 }, &trunc13);
		render((Settings){ 1, 1, -1, -1, 10.0, 13.4, 0 }, &frac134);
		expect(!same(&trunc13, &frac134) && frac134.maxX > trunc13.maxX, "a fractional size renders differently from the truncated size");

		render((Settings){ 1, 1, -1, -1, 10.0, 13, 0 }, &up);
		render((Settings){ 1, 1, -1, -1, 10.0, 13, 90 }, &rot90);
		expect((rot90.maxY - rot90.minY) > (rot90.maxX - rot90.minX) && (up.maxX - up.minX) > (up.maxY - up.minY),
		      "text rotated by 90 degrees runs vertically");
		// The glyph itself is rotated, not only its position: an upright H is taller than wide.
		static Image hUp, hRot;
		render((Settings){ 1, 1, -1, -1, 10.0, 24, 0, 1 }, &hUp);
		render((Settings){ 1, 1, -1, -1, 30.0, 24, 90, 1 }, &hRot);
		expect((hUp.maxY - hUp.minY) > (hUp.maxX - hUp.minX) && (hRot.maxX - hRot.minX) > (hRot.maxY - hRot.minY),
		       "a glyph rotated by 90 degrees is rotated");

		// The AppleFontSmoothing default of 0 turns smoothing off, as on macOS.
		CFNumberRef none = (CFNumberRef) CFBridgingRetain(@0);
		CFPreferencesSetValue(CFSTR("AppleFontSmoothing"), none, kCFPreferencesAnyApplication,
		                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		render((Settings){ 1, 1, -1, -1, 10.0, 13, 0 }, &zero);
		CFPreferencesSetValue(CFSTR("AppleFontSmoothing"), NULL, kCFPreferencesAnyApplication,
		                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		CFRelease(none);
		expect(same(&zero, &off), "AppleFontSmoothing 0 renders like smoothing off");

		// Coverage totals from macOS 10.14.4 (same font data).
		render((Settings){ 1, 1, -1, -1, 10.0, 24, 0 }, &big);
		render((Settings){ 0, 1, -1, -1, 10.0, 24, 0 }, &bigOff);
		within("24 pt smoothing on", big.sum, 314509, 0.05);
		within("24 pt smoothing off", bigOff.sum, 270316, 0.05);
		within("13.4 pt smoothing on", frac134.sum, 117366, 0.05);
		render((Settings){ 1, 1, -1, -1, 10.0, 13, 30 }, &rot30);
		within("13 pt rotated 30 degrees", rot30.sum, 40910, 0.05);
		printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
	}
	return failures != 0;
}
