// Copyright (C) 2026 Lubos Dolezel
//
// Private NSAppearance methods, as observed on macOS 26.7.3 x86_64 (default
// blue accent color):
// - tintColor is the accent color for every named appearance;
// - appearanceByApplyingTintColor: returns a new appearance of the same name
//   that reports the given tint color (also nil); two made from the same
//   appearance and color are equal;
// - _drawInRect:context:options: with the scroll bar track corner widget
//   (CoreUI's kCUIWidgetScrollBarTrackCorner) draws a 15 x 15 square centered
//   in the rect, without scaling it: light gray (250) and opaque in Aqua, a
//   faint gray (alpha 19/255) in Dark Aqua. A half-point offset rounds down,
//   except vertically when is.flipped (kCUIIsFlippedKey) is set, where it
//   rounds up. An unknown widget or no widget draws nothing.

#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSColor *tint(NSAppearance *a) { return ((id (*)(id, SEL)) objc_msgSend)(a, sel_registerName("tintColor")); }
static NSAppearance *tinted(NSAppearance *a, NSColor *c) { return ((id (*)(id, SEL, id)) objc_msgSend)(a, sel_registerName("appearanceByApplyingTintColor:"), c); }

typedef struct { int covered, minx, maxx, miny, maxy; unsigned char center[4]; } Drawn;

// Draws into a W x H premultiplied RGBA bitmap; y bounds are in CG (bottom-up) coordinates.
static Drawn draw(NSAppearance *a, NSRect rect, NSDictionary *options, int W, int H)
{
	unsigned char *px = calloc(W * H, 4);
	CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef ctx = CGBitmapContextCreate(px, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedLast);
	[a performAsCurrentDrawingAppearance:^{
		((void (*)(id, SEL, NSRect, CGContextRef, id)) objc_msgSend)(a, sel_registerName("_drawInRect:context:options:"), rect, ctx, options);
	}];
	Drawn d = { 0, W, -1, H, -1, { 0 } };
	for (int row = 0; row < H; row++) {
		for (int x = 0; x < W; x++) {
			if (!px[(row * W + x) * 4 + 3])
				continue;
			int y = H - 1 - row;
			d.covered++;
			if (x < d.minx) d.minx = x;
			if (x > d.maxx) d.maxx = x;
			if (y < d.miny) d.miny = y;
			if (y > d.maxy) d.maxy = y;
		}
	}
	int cx = (int) NSMidX(rect), crow = H - 1 - (int) NSMidY(rect);
	if (cx >= 0 && cx < W && crow >= 0 && crow < H)
		memcpy(d.center, &px[(crow * W + cx) * 4], 4);
	CGContextRelease(ctx);
	CGColorSpaceRelease(cs);
	free(px);
	return d;
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSAppearance *aqua = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
		NSAppearance *dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

		// tintColor
		NSColor *accent = [[NSColor controlAccentColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
		NSColor *aquaTint = [tint(aqua) colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
		NSColor *darkTint = [tint(dark) colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
		CHECK(aquaTint != nil && darkTint != nil);
		CHECK(fabs(aquaTint.redComponent - accent.redComponent) < 0.01 && fabs(aquaTint.greenComponent - accent.greenComponent) < 0.01 && fabs(aquaTint.blueComponent - accent.blueComponent) < 0.01);
		CHECK([aquaTint isEqual:darkTint]);

		// appearanceByApplyingTintColor:
		NSAppearance *red = tinted(aqua, NSColor.systemRedColor);
		CHECK(red != nil && red != aqua);
		CHECK([red.name isEqualToString:NSAppearanceNameAqua]);
		CHECK([tint(red) isEqual:NSColor.systemRedColor]);
		NSAppearance *red2 = tinted(aqua, NSColor.systemRedColor);
		CHECK(red2 != red && [red2 isEqual:red]);
		CHECK(![red isEqual:tinted(aqua, NSColor.systemBlueColor)]);
		NSAppearance *none = tinted(aqua, nil);
		CHECK(none != nil && none != aqua && tint(none) == nil);
		NSAppearance *darkBlue = tinted(dark, NSColor.systemBlueColor);
		CHECK([darkBlue.name isEqualToString:NSAppearanceNameDarkAqua]);
		NSArray *families = @[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ];
		CHECK([[darkBlue bestMatchFromAppearancesWithNames:families] isEqualToString:NSAppearanceNameDarkAqua]);

		// _drawInRect:context:options:
		NSDictionary *corner = @{ @"widget": @"kCUIWidgetScrollBarTrackCorner" };
		NSDictionary *flipped = @{ @"widget": @"kCUIWidgetScrollBarTrackCorner", @"is.flipped": @YES };

		Drawn d = draw(aqua, NSMakeRect(0, 0, 16, 16), corner, 16, 16);
		CHECK(d.covered == 225 && d.minx == 0 && d.maxx == 14 && d.miny == 0 && d.maxy == 14);
		CHECK(d.center[0] == 250 && d.center[1] == 250 && d.center[2] == 250 && d.center[3] == 255);

		d = draw(dark, NSMakeRect(0, 0, 16, 16), corner, 16, 16);
		CHECK(d.covered == 225);
		CHECK(d.center[3] >= 17 && d.center[3] <= 21 && d.center[0] >= 13 && d.center[0] <= 17);

		d = draw(aqua, NSMakeRect(0, 0, 32, 32), flipped, 40, 40);
		CHECK(d.covered == 225 && d.minx == 8 && d.maxx == 22 && d.miny == 9 && d.maxy == 23);
		d = draw(aqua, NSMakeRect(4, 6, 15, 15), flipped, 40, 40);
		CHECK(d.covered == 225 && d.minx == 4 && d.maxx == 18 && d.miny == 6 && d.maxy == 20);
		d = draw(aqua, NSMakeRect(0, 0, 30, 10), flipped, 40, 40);
		CHECK(d.covered == 195 && d.minx == 7 && d.maxx == 21 && d.miny == 0 && d.maxy == 12);

		CHECK(draw(aqua, NSMakeRect(0, 0, 16, 16), @{ @"widget": @"kCUIWidgetNoSuchThing" }, 16, 16).covered == 0);
		CHECK(draw(aqua, NSMakeRect(0, 0, 16, 16), @{}, 16, 16).covered == 0);
	}
	printf(failures ? "FAILED\n" : "PASSED\n");
	return failures != 0;
}
