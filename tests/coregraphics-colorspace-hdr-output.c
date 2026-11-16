// Copyright (C) 2026 Lubos Dolezel
//
// CGColorSpaceIsHDR and CGColorSpaceSupportsOutput for named color spaces.
// Expected answers were observed on macOS 26.7.3 (see the QUIRK comments).
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

static int failures;

static void check(CFStringRef name, int hdr) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(name);
    if (space == NULL)
        return; // a space this implementation cannot create
    char buffer[64];
    CFStringGetCString(name, buffer, sizeof buffer, kCFStringEncodingUTF8);
    if (CGColorSpaceIsHDR(space) != hdr) {
        fprintf(stderr, "FAIL: CGColorSpaceIsHDR(%s) != %d\n", buffer, hdr);
        failures++;
    }
    if (!CGColorSpaceSupportsOutput(space)) {
        fprintf(stderr, "FAIL: CGColorSpaceSupportsOutput(%s) is false\n", buffer);
        failures++;
    }
    CGColorSpaceRelease(space);
}

int main(void) {
    check(kCGColorSpaceSRGB, 0);
    check(kCGColorSpaceGenericRGB, 0);
    check(kCGColorSpaceGenericGrayGamma2_2, 0);
    check(kCGColorSpaceAdobeRGB1998, 0);
    check(kCGColorSpaceDisplayP3, 0);
    check(kCGColorSpaceExtendedSRGB, 0);
    check(kCGColorSpaceLinearSRGB, 0);
    check(kCGColorSpaceITUR_709, 0);
    check(kCGColorSpaceITUR_2020, 0);
    check(kCGColorSpaceITUR_2100_PQ, 1);
    check(kCGColorSpaceITUR_2100_HLG, 1);
    check(kCGColorSpaceROMMRGB, 0);
    check(kCGColorSpaceDCIP3, 0);
    check(kCGColorSpaceGenericCMYK, 0);
    check(kCGColorSpaceGenericLab, 0);
    check(kCGColorSpaceGenericXYZ, 0);
    check(kCGColorSpaceACESCGLinear, 0);

    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    if (CGColorSpaceIsHDR(rgb) || !CGColorSpaceSupportsOutput(rgb)) {
        fprintf(stderr, "FAIL: device RGB\n");
        failures++;
    }
    unsigned char table[3] = {0, 0, 0};
    CGColorSpaceRef indexed = CGColorSpaceCreateIndexed(rgb, 0, table);
    if (indexed != NULL && (CGColorSpaceSupportsOutput(indexed) || CGColorSpaceIsHDR(indexed))) {
        fprintf(stderr, "FAIL: an indexed space does not support output\n");
        failures++;
    }
    if (failures == 0)
        printf("PASS: color space HDR and output queries\n");
    return failures ? 1 : 0;
}
