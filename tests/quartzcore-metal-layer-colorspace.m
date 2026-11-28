/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The colorspace of a CAMetalLayer follows its pixelFormat. Observed on macOS 27.0.1 (26A434, arm64) with a probe that only
 * reads layer properties (no window, no capture): a new layer has no colorspace; setting pixelFormat sets one, the same whether
 * wantsExtendedDynamicRangeContent is NO or YES and whichever property is set first, and turning wantsExtendedDynamicRangeContent
 * back off changes nothing:
 *   BGRA10_XR, BGRA10_XR_sRGB, BGR10_XR, BGR10_XR_sRGB  kCGColorSpaceExtendedSRGB
 *   RGBA16Float                                          kCGColorSpaceExtendedLinearSRGB
 *   BGRA8Unorm                                           kCGColorSpaceSRGB
 * and the texture of nextDrawable has the layer's pixelFormat. Also observed there (probes layer-assign and layer-reformat): an unassigned layer takes the
 * default of every format it changes to (RGB10A2Unorm gets sRGB); a non-nil colorspace the application assigned, even one equal to a default, is
 * kept by every later pixelFormat, assigned before or after the first one; assigning nil reads nil at once and the next pixelFormat applies
 * the default again.
 * Needs no display. The drawable checks need a Metal device; they print SKIP without one.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void expect(BOOL ok, const char *what, CGColorSpaceRef space) {
	CFStringRef name = space ? CGColorSpaceCopyName(space) : NULL;
	char buffer[128] = "nil";
	if (name != NULL) {
		CFStringGetCString(name, buffer, sizeof buffer, kCFStringEncodingUTF8);
		CFRelease(name);
	}
	printf("%s %s (colorspace %s)\n", ok ? "PASS" : "FAIL", what, buffer);
	if (!ok)
		failures++;
}

static BOOL isNamed(CGColorSpaceRef space, CFStringRef expected) {
	if (space == NULL)
		return expected == NULL;
	CFStringRef name = CGColorSpaceCopyName(space);
	BOOL equal = name != NULL && expected != NULL && CFEqual(name, expected);
	if (name != NULL)
		CFRelease(name);
	return equal;
}

int main(void) {
	@autoreleasepool {
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		const struct { MTLPixelFormat format; const char *name; CFStringRef space; } formats[] = {
			{ MTLPixelFormatBGRA10_XR, "BGRA10_XR", kCGColorSpaceExtendedSRGB },
			{ MTLPixelFormatBGRA10_XR_sRGB, "BGRA10_XR_sRGB", kCGColorSpaceExtendedSRGB },
			{ MTLPixelFormatBGR10_XR, "BGR10_XR", kCGColorSpaceExtendedSRGB },
			{ MTLPixelFormatBGR10_XR_sRGB, "BGR10_XR_sRGB", kCGColorSpaceExtendedSRGB },
			{ MTLPixelFormatRGBA16Float, "RGBA16Float", kCGColorSpaceExtendedLinearSRGB },
			{ MTLPixelFormatBGRA8Unorm, "BGRA8Unorm", kCGColorSpaceSRGB },
		};
		for (size_t i = 0; i < sizeof formats / sizeof formats[0]; i++) {
			for (int edr = 0; edr < 2; edr++) {
				char what[160];
				CAMetalLayer *layer = [CAMetalLayer layer];
				expect(layer.colorspace == NULL, "a new layer has no colorspace", layer.colorspace);

				layer.device = device;
				layer.drawableSize = CGSizeMake(16, 16);
				layer.pixelFormat = formats[i].format;
				layer.wantsExtendedDynamicRangeContent = edr;
				snprintf(what, sizeof what, "%s edr=%d: pixelFormat sets the colorspace", formats[i].name, edr);
				expect(layer.pixelFormat == formats[i].format && isNamed(layer.colorspace, formats[i].space), what, layer.colorspace);
				if (device != nil) {
					id<CAMetalDrawable> drawable = [layer nextDrawable];
					snprintf(what, sizeof what, "%s edr=%d: the drawable's texture has the layer's pixelFormat", formats[i].name, edr);
					if (drawable == nil)
						printf("SKIP %s edr=%d: this layer has no drawable without a window\n", formats[i].name, edr);
					else
						expect(drawable.texture.pixelFormat == formats[i].format, what, layer.colorspace);
				} else {
					printf("SKIP %s edr=%d: no Metal device for the drawable\n", formats[i].name, edr);
				}

				CAMetalLayer *other = [CAMetalLayer layer];
				other.wantsExtendedDynamicRangeContent = edr;
				snprintf(what, sizeof what, "%s edr=%d: wantsExtendedDynamicRangeContent alone sets no colorspace", formats[i].name, edr);
				expect(other.colorspace == NULL, what, other.colorspace);
				other.pixelFormat = formats[i].format;
				snprintf(what, sizeof what, "%s edr=%d: then pixelFormat sets it", formats[i].name, edr);
				expect(isNamed(other.colorspace, formats[i].space), what, other.colorspace);
				if (edr) {
					other.wantsExtendedDynamicRangeContent = NO;
					snprintf(what, sizeof what, "%s: turning wantsExtendedDynamicRangeContent off keeps it", formats[i].name);
					expect(isNamed(other.colorspace, formats[i].space), what, other.colorspace);
				}
			}
		}

		// RGB10A2Unorm gets sRGB
		CAMetalLayer *ten = [CAMetalLayer layer];
		ten.pixelFormat = MTLPixelFormatRGB10A2Unorm;
		expect(isNamed(ten.colorspace, kCGColorSpaceSRGB), "RGB10A2Unorm sets sRGB", ten.colorspace);

		// an unassigned layer takes the default of every format it is changed to
		const struct { MTLPixelFormat from, to; CFStringRef space; } changes[] = {
			{ MTLPixelFormatBGRA10_XR, MTLPixelFormatRGBA16Float, kCGColorSpaceExtendedLinearSRGB },
			{ MTLPixelFormatBGRA10_XR, MTLPixelFormatBGRA8Unorm, kCGColorSpaceSRGB },
			{ MTLPixelFormatRGBA16Float, MTLPixelFormatBGRA10_XR, kCGColorSpaceExtendedSRGB },
			{ MTLPixelFormatBGRA8Unorm, MTLPixelFormatRGBA16Float, kCGColorSpaceExtendedLinearSRGB },
			{ MTLPixelFormatRGB10A2Unorm, MTLPixelFormatBGRA10_XR, kCGColorSpaceExtendedSRGB },
		};
		for (size_t i = 0; i < sizeof changes / sizeof changes[0]; i++) {
			CAMetalLayer *layer = [CAMetalLayer layer];
			layer.pixelFormat = changes[i].from;
			layer.pixelFormat = changes[i].to;
			expect(isNamed(layer.colorspace, changes[i].space), "an unassigned layer takes the default of the format it changes to", layer.colorspace);
		}

		// an assigned colorspace is kept by every later pixelFormat, assigned before or after the first one, even when it equals a default
		CGColorSpaceRef p3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
		CGColorSpaceRef extended = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
		CAMetalLayer *before = [CAMetalLayer layer];
		before.colorspace = p3;
		before.pixelFormat = MTLPixelFormatBGRA10_XR;
		expect(isNamed(before.colorspace, kCGColorSpaceDisplayP3), "an assigned colorspace is kept by the first pixelFormat", before.colorspace);
		before.pixelFormat = MTLPixelFormatRGBA16Float;
		expect(isNamed(before.colorspace, kCGColorSpaceDisplayP3), "and by a later one", before.colorspace);
		CAMetalLayer *after = [CAMetalLayer layer];
		after.pixelFormat = MTLPixelFormatBGRA8Unorm;
		after.colorspace = p3;
		after.pixelFormat = MTLPixelFormatBGRA10_XR;
		expect(isNamed(after.colorspace, kCGColorSpaceDisplayP3), "a colorspace assigned after the first pixelFormat is kept", after.colorspace);
		CAMetalLayer *same = [CAMetalLayer layer];
		same.pixelFormat = MTLPixelFormatBGRA10_XR;
		same.colorspace = extended;
		same.pixelFormat = MTLPixelFormatBGRA8Unorm;
		expect(isNamed(same.colorspace, kCGColorSpaceExtendedSRGB), "an assigned colorspace equal to a default is kept too", same.colorspace);

		// assigning nil reads nil at once, and the next pixelFormat applies the default again
		before.colorspace = NULL;
		expect(before.colorspace == NULL, "assigning nil reads nil", before.colorspace);
		before.pixelFormat = MTLPixelFormatBGRA10_XR;
		expect(isNamed(before.colorspace, kCGColorSpaceExtendedSRGB), "the next pixelFormat applies the default again", before.colorspace);
		before.pixelFormat = MTLPixelFormatBGRA8Unorm;
		expect(isNamed(before.colorspace, kCGColorSpaceSRGB), "and it is unassigned again", before.colorspace);
		CGColorSpaceRelease(p3);
		CGColorSpaceRelease(extended);
	}
	if (failures) {
		printf("FAILED: %d\n", failures);
		return 1;
	}
	printf("ALL PASSED\n");
	return 0;
}
