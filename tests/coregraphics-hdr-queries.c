/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CGColorSpaceUsesITUR_2100TF and CGColorSpaceIsHLGBased: true for spaces
 * whose transfer function is defined in ITU-R BT.2100 (PQ or HLG), and for HLG
 * only, respectively; false for other spaces and for NULL. Also checks the
 * CGColorRenderingIntent enum values.
 */
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

_Static_assert(sizeof(CGColorRenderingIntent) == 4, "CGColorRenderingIntent is 32-bit");
_Static_assert(kCGRenderingIntentDefault == 0 && kCGRenderingIntentAbsoluteColorimetric == 1 &&
               kCGRenderingIntentRelativeColorimetric == 2 && kCGRenderingIntentPerceptual == 3 &&
               kCGRenderingIntentSaturation == 4, "documented intent values");

static void query(CFStringRef name, bool tf2100, bool hlg, int line) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(name);
    if (!space) {
        printf("FAIL: no space for name (line %d)\n", line);
        failures++;
        return;
    }
    if (CGColorSpaceUsesITUR_2100TF(space) != tf2100) {
        printf("FAIL: UsesITUR_2100TF (line %d)\n", line);
        failures++;
    }
    if (CGColorSpaceIsHLGBased(space) != hlg) {
        printf("FAIL: IsHLGBased (line %d)\n", line);
        failures++;
    }
    CGColorSpaceRelease(space);
}

int main(void) {
    query(kCGColorSpaceITUR_2100_PQ, true, false, __LINE__);
    query(kCGColorSpaceITUR_2100_HLG, true, true, __LINE__);
    query(kCGColorSpaceSRGB, false, false, __LINE__);
    query(kCGColorSpaceDisplayP3, false, false, __LINE__);
    query(kCGColorSpaceExtendedLinearSRGB, false, false, __LINE__);
    query(kCGColorSpaceITUR_2020, false, false, __LINE__);

    CGColorSpaceRef device = CGColorSpaceCreateDeviceRGB();
    CHECK(!CGColorSpaceUsesITUR_2100TF(device));
    CHECK(!CGColorSpaceIsHLGBased(device));
    CGColorSpaceRelease(device);

    CHECK(!CGColorSpaceUsesITUR_2100TF(NULL));
    CHECK(!CGColorSpaceIsHLGBased(NULL));

    if (failures == 0) {
        printf("ALL PASSED\n");
        return 0;
    }
    return 1;
}
