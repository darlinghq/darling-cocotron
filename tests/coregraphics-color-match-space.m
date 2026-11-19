/*
 Copyright (C) 2026 Lubos Dolezel
 Darling is free software under the GNU GPL version 3 or later.
*/
// CGColorCreateCopyByMatchingToColorSpace for the kinds of source colour and target space
// that are not plain RGB/gray: indexed colours, pattern colours (with and without a base
// space) and the generic CMYK space. Expected values were printed by a probe on
// macOS 26.7.3 (black-box observation); the tolerance covers Apple's ICC profile
// quantisation (0.015 for the generic spaces, 0.003 otherwise). Also passes on macOS.
// Build without ARC.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

static int g_fail;

static void expect(const char *what, int ok)
{
	if (!ok) { printf("FAIL: %s\n", what); g_fail = 1; }
}

static void drawPattern(void *info, CGContextRef c) { CGContextFillRect(c, CGRectMake(0, 0, 2, 2)); }

// Matches color to the named (or device) space and compares the components.
static void check(const char *what, CGColorRef color, CFStringRef name, int device, const double *want, int count, double tol)
{
	CGColorSpaceRef space = device == 1 ? CGColorSpaceCreateDeviceRGB()
		: device == 2 ? CGColorSpaceCreateDeviceCMYK() : CGColorSpaceCreateWithName(name);
	char msg[160];
	snprintf(msg, sizeof msg, "%s: target space exists", what);
	expect(msg, space != NULL);
	if (!space) return;
	CGColorRef out = CGColorCreateCopyByMatchingToColorSpace(space, kCGRenderingIntentDefault, color, NULL);
	snprintf(msg, sizeof msg, "%s: result is not NULL", what);
	expect(msg, out != NULL);
	if (out)
	{
		snprintf(msg, sizeof msg, "%s: component count", what);
		expect(msg, CGColorGetNumberOfComponents(out) == (size_t)count);
		if (CGColorGetNumberOfComponents(out) == (size_t)count)
		{
			const CGFloat *p = CGColorGetComponents(out);
			for (int k = 0; k < count; k++)
				if (fabs(p[k] - want[k]) > tol)
				{
					printf("FAIL: %s: component %d is %f, expected %f\n", what, k, p[k], want[k]);
					g_fail = 1;
				}
		}
		CGColorRelease(out);
	}
	CGColorSpaceRelease(space);
}

static void expectNULL(const char *what, CGColorRef color, CFStringRef name, int device)
{
	CGColorSpaceRef space = device == 2 ? CGColorSpaceCreateDeviceCMYK() : CGColorSpaceCreateWithName(name);
	CGColorRef out = CGColorCreateCopyByMatchingToColorSpace(space, kCGRenderingIntentDefault, color, NULL);
	expect(what, out == NULL);
	if (out) CGColorRelease(out);
	CGColorSpaceRelease(space);
}

int main(void)
{
	CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

	// Indexed colour: palette entry 1 is blue.
	{
		unsigned char table[6] = { 255, 0, 0, 0, 0, 255 };
		CGColorSpaceRef indexed = CGColorSpaceCreateIndexed(srgb, 1, table);
		CGFloat c[2] = { 1, 1 };
		CGColorRef color = CGColorCreate(indexed, c);
		expect("indexed colour exists", color != NULL);
		const double blue[4] = { 0, 0, 1, 1 };
		const double p3[4] = { 0, 0, 0.9608, 1 };
		const double gray[2] = { 0.2118, 1 };
		check("indexed to sRGB", color, kCGColorSpaceSRGB, 0, blue, 4, 0.003);
		check("indexed to device RGB", color, NULL, 1, blue, 4, 0.003);
		check("indexed to generic RGB", color, kCGColorSpaceGenericRGB, 0, blue, 4, 0.015);
		check("indexed to extended sRGB", color, kCGColorSpaceExtendedSRGB, 0, blue, 4, 0.003);
		check("indexed to linear sRGB", color, kCGColorSpaceLinearSRGB, 0, blue, 4, 0.003);
		check("indexed to Display P3", color, kCGColorSpaceDisplayP3, 0, p3, 4, 0.003);
		check("indexed to generic gray", color, kCGColorSpaceGenericGray, 0, gray, 2, 0.015);
		CGColorRelease(color);
		CGColorSpaceRelease(indexed);
	}

	// Pattern colour with a base space: the base colour is matched.
	{
		CGPatternCallbacks cb = { 0, drawPattern, NULL };
		CGColorSpaceRef patternSpace = CGColorSpaceCreatePattern(srgb);
		CGPatternRef pattern = CGPatternCreate(NULL, CGRectMake(0, 0, 2, 2), CGAffineTransformIdentity, 2, 2,
			kCGPatternTilingConstantSpacing, false, &cb);
		CGFloat c[4] = { 1, 0, 0, 1 };
		CGColorRef color = CGColorCreateWithPattern(patternSpace, pattern, c);
		expect("pattern colour exists", color != NULL);
		expect("pattern colour keeps base components", CGColorGetNumberOfComponents(color) == 4);
		const double red[4] = { 1, 0, 0, 1 };
		const double p3[4] = { 0.9175, 0.2004, 0.1385, 1 };
		const double gray[2] = { 0.4339, 1 };
		check("pattern with base to sRGB", color, kCGColorSpaceSRGB, 0, red, 4, 0.003);
		check("pattern with base to device RGB", color, NULL, 1, red, 4, 0.003);
		check("pattern with base to Display P3", color, kCGColorSpaceDisplayP3, 0, p3, 4, 0.003);
		check("pattern with base to generic gray", color, kCGColorSpaceGenericGray, 0, gray, 2, 0.015);
		CGColorRelease(color);
		CGPatternRelease(pattern);
		CGColorSpaceRelease(patternSpace);
	}

	// Pattern colour without a base space (a coloured pattern) has no colour to match.
	{
		CGPatternCallbacks cb = { 0, drawPattern, NULL };
		CGColorSpaceRef patternSpace = CGColorSpaceCreatePattern(NULL);
		CGPatternRef pattern = CGPatternCreate(NULL, CGRectMake(0, 0, 2, 2), CGAffineTransformIdentity, 2, 2,
			kCGPatternTilingConstantSpacing, true, &cb);
		CGFloat alpha = 1;
		CGColorRef color = CGColorCreateWithPattern(patternSpace, pattern, &alpha);
		expect("coloured pattern exists", color != NULL);
		expectNULL("coloured pattern to sRGB is NULL", color, kCGColorSpaceSRGB, 0);
		expectNULL("coloured pattern to generic gray is NULL", color, kCGColorSpaceGenericGray, 0);
		expectNULL("coloured pattern to device CMYK is NULL", color, NULL, 2);
		CGColorRelease(color);
		CGPatternRelease(pattern);
		CGColorSpaceRelease(patternSpace);
	}

	// The generic CMYK space exists; CMYK values are kept between it and device CMYK, and the
	// conversion from RGB succeeds with the alpha kept (the exact values depend on Apple's ICC profile).
	{
		CGColorSpaceRef cmyk = CGColorSpaceCreateWithName(kCGColorSpaceGenericCMYK);
		expect("generic CMYK space exists", cmyk != NULL && CGColorSpaceGetNumberOfComponents(cmyk) == 4);
		CGColorSpaceRelease(cmyk);

		CGColorRef source = CGColorCreateGenericCMYK(0.1, 0.2, 0.3, 0.4, 1);
		const double same[5] = { 0.1, 0.2, 0.3, 0.4, 1 };
		check("generic CMYK to generic CMYK", source, kCGColorSpaceGenericCMYK, 0, same, 5, 0.0001);
		check("generic CMYK to device CMYK", source, NULL, 2, same, 5, 0.0001);
		CGColorRelease(source);

		CGColorSpaceRef device = CGColorSpaceCreateDeviceCMYK();
		CGFloat c[5] = { 0.1, 0.2, 0.3, 0.4, 1 };
		CGColorRef deviceColor = CGColorCreate(device, c);
		check("device CMYK to generic CMYK", deviceColor, kCGColorSpaceGenericCMYK, 0, same, 5, 0.0001);
		CGColorRelease(deviceColor);
		CGColorSpaceRelease(device);

		CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
		const double none[5] = { 0, 0, 0, 0, 1 };
		check("white to generic CMYK", white, kCGColorSpaceGenericCMYK, 0, none, 5, 0.003);
		CGColorRelease(white);

		CGColorRef translucent = CGColorCreateSRGB(0.2, 0.6, 0.9, 0.5);
		CGColorSpaceRef target = CGColorSpaceCreateWithName(kCGColorSpaceGenericCMYK);
		CGColorRef out = CGColorCreateCopyByMatchingToColorSpace(target, kCGRenderingIntentDefault, translucent, NULL);
		expect("sRGB to generic CMYK is not NULL", out != NULL);
		if (out)
		{
			expect("sRGB to generic CMYK has 5 components", CGColorGetNumberOfComponents(out) == 5);
			expect("sRGB to generic CMYK keeps alpha", fabs(CGColorGetAlpha(out) - 0.5) < 1e-6);
			CGColorRelease(out);
		}
		CGColorSpaceRelease(target);
		CGColorRelease(translucent);
	}

	CGColorSpaceRelease(srgb);
	printf(g_fail ? "FAIL\n" : "PASS\n");
	return g_fail;
}
