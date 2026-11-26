// Copyright (C) 2026 Darling developers
//
// The ICC data of the generic colour spaces comes from the ColorSync profiles of the platform: CGColorSpaceCopyICCData of
// kCGColorSpaceGenericRGB and kCGColorSpaceGenericGray gives the profile that ColorSyncProfileCreateWithName returns for
// kColorSyncGenericRGBProfile and kColorSyncGenericGrayProfile, with the descriptions "Generic RGB Profile" and "Generic Gray
// Profile". Observed on macOS 26.7.3 and 10.14.4 (x86_64, i386): the same MD5 digest, these descriptions. A colour space made
// from that data converts like the named one.
#include <ColorSync/ColorSync.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int g_fail;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_fail++; } } while (0)

static void checkSpace(CFStringRef name, CFStringRef profileName, const char* description)
{
	CGColorSpaceRef space = CGColorSpaceCreateWithName(name);
	CFDataRef data = space ? CGColorSpaceCopyICCData(space) : NULL;
	ColorSyncProfileRef fromSpace = data ? ColorSyncProfileCreate(data, NULL) : NULL;
	ColorSyncProfileRef named = ColorSyncProfileCreateWithName(profileName);
	CHECK(fromSpace != NULL && named != NULL);
	if (fromSpace && named)
	{
		ColorSyncMD5 a = ColorSyncProfileGetMD5(fromSpace), b = ColorSyncProfileGetMD5(named);
		CHECK(memcmp(&a, &b, sizeof a) == 0);
		CFStringRef text = ColorSyncProfileCopyDescriptionString(fromSpace);
		CFStringRef wanted = CFStringCreateWithCString(NULL, description, kCFStringEncodingASCII);
		CHECK(text != NULL && CFEqual(text, wanted));
		if (text)
			CFRelease(text);
		CFRelease(wanted);
	}

	// A colour space made from the data of the space converts like it.
	CGColorSpaceRef copy = data ? CGColorSpaceCreateWithICCData(data) : NULL;
	CHECK(copy != NULL && CGColorSpaceGetNumberOfComponents(copy) == CGColorSpaceGetNumberOfComponents(space));
	CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
	const CGFloat in[4] = { 0.5, 0.5, 0.5, 1 };
	CGColorRef a = copy ? CGColorCreate(copy, in) : NULL, b = CGColorCreate(space, in);
	CGColorRef ra = a ? CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentRelativeColorimetric, a, NULL) : NULL;
	CGColorRef rb = CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentRelativeColorimetric, b, NULL);
	CHECK(ra != NULL && rb != NULL && fabs(CGColorGetComponents(ra)[0] - CGColorGetComponents(rb)[0]) < 0.003);
	CHECK(rb != NULL && fabs(CGColorGetComponents(rb)[0] - 0.572307) < 0.003); // gray 0.5 in both spaces (observed)
	if (ra)
		CGColorRelease(ra);
	if (rb)
		CGColorRelease(rb);
	if (a)
		CGColorRelease(a);
	CGColorRelease(b);
	CGColorSpaceRelease(srgb);
	if (copy)
		CGColorSpaceRelease(copy);
	if (fromSpace)
		CFRelease(fromSpace);
	if (named)
		CFRelease(named);
	if (data)
		CFRelease(data);
	CGColorSpaceRelease(space);
}

int main(void)
{
	checkSpace(kCGColorSpaceGenericRGB, kColorSyncGenericRGBProfile, "Generic RGB Profile");
	checkSpace(kCGColorSpaceGenericGray, kColorSyncGenericGrayProfile, "Generic Gray Profile");
	if (g_fail == 0)
		printf("PASS\n");
	return g_fail != 0;
}
