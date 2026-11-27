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
 * and the texture of nextDrawable has the layer's pixelFormat. That an assigned colorspace survives a later pixelFormat change was not
 * observed; this implementation keeps it.
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
					expect(drawable != nil && drawable.texture.pixelFormat == formats[i].format, what, layer.colorspace);
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

		// not observed on macOS: an assigned colorspace is kept (this implementation's choice)
		CAMetalLayer *assigned = [CAMetalLayer layer];
		CGColorSpaceRef chosen = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
		assigned.colorspace = chosen;
		assigned.pixelFormat = MTLPixelFormatBGRA10_XR;
		expect(isNamed(assigned.colorspace, kCGColorSpaceDisplayP3), "an assigned colorspace survives a later pixelFormat (not observed on macOS)", assigned.colorspace);
		if (chosen != NULL)
			CGColorSpaceRelease(chosen);
	}
	if (failures) {
		printf("FAILED: %d\n", failures);
		return 1;
	}
	printf("ALL PASSED\n");
	return 0;
}
