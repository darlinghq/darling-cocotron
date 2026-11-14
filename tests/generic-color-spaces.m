/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// CGColorCreateGenericRGB/Gray and the calibrated NSColor constructors are in the Generic RGB / Generic Gray
// spaces, so a color filled into an sRGB 8-bit bitmap context converts (generic red gives 255,38,0), while the
// constant colors and the device and sRGB constructors keep their numbers. Expected values were printed by
// mac-probes/v469-generic-colours.m on macOS 26.7.3 (black-box, tier 2); the tolerance of 3 covers the
// quantisation of Apple's ICC profiles. Also passes on macOS.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_fail;

static void pixelOf(CGColorRef color, int px[3]) {
	CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	unsigned char b[4] = {0, 0, 0, 0};
	CGContextRef ctx = CGBitmapContextCreate(b, 1, 1, 8, 4, srgb, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
	CGContextSetFillColorWithColor(ctx, color);
	CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
	CGContextRelease(ctx);
	CGColorSpaceRelease(srgb);
	for (int i = 0; i < 3; i++)
		px[i] = b[i];
}

static void expectPixel(const char* label, CGColorRef color, int r, int g, int b, int tol) {
	int px[3];
	pixelOf(color, px);
	if (abs(px[0] - r) > tol || abs(px[1] - g) > tol || abs(px[2] - b) > tol) {
		printf("FAIL %s: got %d %d %d, expected %d %d %d\n", label, px[0], px[1], px[2], r, g, b);
		g_fail++;
	}
}

static void expectSpace(const char* label, CGColorRef color, CFStringRef name) {
	CFStringRef actual = CGColorSpaceGetName(CGColorGetColorSpace(color));
	if (actual == NULL || !CFEqual(actual, name)) {
		printf("FAIL %s: colour space name differs\n", label);
		g_fail++;
	}
}

int main(void) {
	@autoreleasepool {
		// CoreGraphics generic colors.
		CGColorRef c = CGColorCreateGenericRGB(1, 0, 0, 1);
		expectSpace("generic RGB space", c, kCGColorSpaceGenericRGB);
		expectPixel("generic red", c, 255, 38, 0, 3);
		CGColorRelease(c);
		c = CGColorCreateGenericRGB(0, 1, 0, 1);
		expectPixel("generic green", c, 0, 249, 0, 3);
		CGColorRelease(c);
		c = CGColorCreateGenericRGB(0, 0, 1, 1);
		expectPixel("generic blue", c, 4, 51, 255, 3);
		CGColorRelease(c);
		c = CGColorCreateGenericRGB(0.5, 0.5, 0.5, 1);
		expectPixel("generic mid gray RGB", c, 146, 146, 146, 3);
		CGColorRelease(c);
		c = CGColorCreateGenericRGB(0.2, 0.6, 0.9, 1);
		expectPixel("generic 0.2 0.6 0.9", c, 61, 171, 235, 3);
		CGColorRelease(c);
		c = CGColorCreateGenericGray(0.25, 1);
		expectSpace("generic gray space", c, kCGColorSpaceGenericGray);
		expectPixel("generic gray 0.25", c, 81, 81, 81, 3);
		CGColorRelease(c);
		c = CGColorCreateGenericGray(0.5, 1);
		expectPixel("generic gray 0.5", c, 146, 146, 146, 3);
		CGColorRelease(c);
		c = CGColorCreateGenericGray(1, 1);
		expectPixel("generic white", c, 255, 255, 255, 0);
		CGColorRelease(c);

		// The calibrated constructors.
		NSColor* n = [NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1];
		expectSpace("calibrated RGB space", n.CGColor, kCGColorSpaceGenericRGB);
		expectPixel("calibrated red", n.CGColor, 255, 38, 0, 3);
		n = [NSColor colorWithCalibratedRed:.2 green:.6 blue:.9 alpha:1];
		expectPixel("calibrated 0.2 0.6 0.9", n.CGColor, 61, 171, 235, 3);
		n = [NSColor colorWithCalibratedWhite:.5 alpha:1];
		expectSpace("calibrated white space", n.CGColor, kCGColorSpaceGenericGray);
		expectPixel("calibrated white 0.5", n.CGColor, 146, 146, 146, 3);
		n = [NSColor colorWithCalibratedHue:.6 saturation:.5 brightness:.8 alpha:1];
		expectPixel("calibrated HSB", n.CGColor, 120, 162, 214, 3);
		CGColorSpaceRef nsSpace = n.colorSpace.CGColorSpace;
		if (nsSpace == NULL || !CFEqual(CGColorSpaceGetName(nsSpace), kCGColorSpaceGenericRGB)) {
			printf("FAIL calibrated colour's NSColorSpace is not Generic RGB\n");
			g_fail++;
		}
		CGColorSpaceRef generic = NSColorSpace.genericRGBColorSpace.CGColorSpace;
		if (generic == NULL || !CFEqual(CGColorSpaceGetName(generic), kCGColorSpaceGenericRGB)) {
			printf("FAIL +[NSColorSpace genericRGBColorSpace]\n");
			g_fail++;
		}
		generic = NSColorSpace.genericGrayColorSpace.CGColorSpace;
		if (generic == NULL || !CFEqual(CGColorSpaceGetName(generic), kCGColorSpaceGenericGray)) {
			printf("FAIL +[NSColorSpace genericGrayColorSpace]\n");
			g_fail++;
		}

		// Colors that are not in a generic space keep their numbers in an sRGB context.
		expectPixel("redColor", NSColor.redColor.CGColor, 255, 0, 0, 0);
		expectPixel("orangeColor", NSColor.orangeColor.CGColor, 255, 128, 0, 1);
		expectPixel("brownColor", NSColor.brownColor.CGColor, 153, 102, 51, 1);
		expectPixel("grayColor", NSColor.grayColor.CGColor, 128, 128, 128, 1);
		expectPixel("darkGrayColor", NSColor.darkGrayColor.CGColor, 85, 85, 85, 1);
		expectPixel("device RGB", [NSColor colorWithDeviceRed:.2 green:.6 blue:.9 alpha:1].CGColor, 51, 153, 230, 1);
		expectPixel("device white", [NSColor colorWithDeviceWhite:.5 alpha:1].CGColor, 128, 128, 128, 1);
		expectPixel("colorWithRed", [NSColor colorWithRed:.2 green:.6 blue:.9 alpha:1].CGColor, 51, 153, 230, 1);
		expectPixel("colorWithSRGBRed", [NSColor colorWithSRGBRed:.2 green:.6 blue:.9 alpha:1].CGColor, 51, 153, 230, 1);
		expectPixel("colorWithHue", [NSColor colorWithHue:.6 saturation:.5 brightness:.8 alpha:1].CGColor, 102, 143, 204, 1);
	}
	printf(g_fail == 0 ? "PASS\n" : "FAIL (%d)\n", g_fail);
	return g_fail != 0;
}
