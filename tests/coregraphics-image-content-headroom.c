/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * CGImage content headroom (macOS 15): CGImageCreateWithContentHeadroom,
 * CGImageCreateCopyWithContentHeadroom, CGImageGetContentHeadroom and
 * CGImageCalculateContentHeadroom. Expectations follow the public header
 * contract and a black-box run on macOS 26.7.3 (headroom 0 is "unknown", at
 * least 1 otherwise; only extended range, PQ and HLG spaces take a headroom;
 * unknown PQ/HLG headroom reads as kCGDefaultHDRImageContentHeadroom, unknown
 * extended range headroom as 0, an SDR image as 1).
 */
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL line %d: %s\n", __LINE__, #cond);                     \
            failures++;                                                        \
        }                                                                      \
    } while (0)

// Onyx2D has no 16-bit float pixel format, so every image is 8-bit; macOS 26 accepts a
// content headroom on 8-bit images in these colour spaces as well.
enum { kSDR8, kHalf };

static CGImageRef make(float headroom, int create, CFStringRef name, int kind) {
    size_t bpc = 8, bpp = bpc * 4, bpr = 2 * bpp / 8;
    size_t size = bpr * 2;
    uint8_t *buf = calloc(1, size);
    for (size_t i = 0; i < size; i++)
        buf[i] = 0x80;
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buf, size, NULL);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(name);
    CGBitmapInfo info = kCGImageAlphaPremultipliedLast;
    CGImageRef image;
    if (create)
        image = CGImageCreateWithContentHeadroom(headroom, 2, 2, bpc, bpp, bpr, space, info, provider, NULL, false,
                                                 kCGRenderingIntentDefault);
    else
        image = CGImageCreate(2, 2, bpc, bpp, bpr, space, info, provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
    return image;
}

int main(void) {
    CHECK(fabsf(kCGDefaultHDRImageContentHeadroom - 4.92611f) < 0.001f);
    CHECK(CGImageGetContentHeadroom(NULL) == 0);
    CHECK(CGImageCalculateContentHeadroom(NULL) == 0);
    CHECK(CGImageCreateCopyWithContentHeadroom(2, NULL) == NULL);

    CGImageRef sdr = make(0, 0, kCGColorSpaceSRGB, kSDR8);
    CHECK(sdr != NULL);
    CHECK(CGImageGetContentHeadroom(sdr) == 1);
    CHECK(CGImageCreateCopyWithContentHeadroom(2, sdr) == NULL);
    CHECK(make(2, 1, kCGColorSpaceSRGB, kSDR8) == NULL);
    CHECK(make(0, 1, kCGColorSpaceSRGB, kSDR8) == NULL);

    CGImageRef ext = make(0, 0, kCGColorSpaceExtendedSRGB, kHalf);
    CHECK(ext != NULL);
    if (ext == NULL || sdr == NULL)
        return 1;
    CHECK(CGImageGetContentHeadroom(ext) == 0);
    CHECK(CGImageCalculateContentHeadroom(ext) == 0);

    float valid[] = {0, 1, 2, 4};
    for (int i = 0; i < 4; i++) {
        CGImageRef copy = CGImageCreateCopyWithContentHeadroom(valid[i], ext);
        CHECK(copy != NULL);
        CHECK(CGImageGetContentHeadroom(copy) == valid[i]);
        CHECK(CGImageGetWidth(copy) == 2 && CGImageGetBitsPerComponent(copy) == 8);
        CHECK(CGImageGetContentHeadroom(ext) == 0); // the original is unchanged
        CGImageRef created = make(valid[i], 1, kCGColorSpaceExtendedSRGB, kHalf);
        CHECK(created != NULL);
        CHECK(CGImageGetContentHeadroom(created) == valid[i]);
        // copies and sub-images keep the headroom
        CGImageRef inrect = CGImageCreateWithImageInRect(copy, CGRectMake(0, 0, 1, 1));
        CHECK(inrect != NULL && CGImageGetContentHeadroom(inrect) == valid[i]);
        CGImageRef plain = CGImageCreateCopy(copy);
        CHECK(plain != NULL && CGImageGetContentHeadroom(plain) == valid[i]);
        CGImageRelease(inrect);
        CGImageRelease(plain);
        CGImageRelease(copy);
        CGImageRelease(created);
    }

    float invalid[] = {0.5f, -1, NAN};
    for (int i = 0; i < 3; i++) {
        CHECK(CGImageCreateCopyWithContentHeadroom(invalid[i], ext) == NULL);
        CHECK(make(invalid[i], 1, kCGColorSpaceExtendedSRGB, kHalf) == NULL);
    }

    CFStringRef hdr[] = {kCGColorSpaceITUR_2100_PQ, kCGColorSpaceITUR_2100_HLG};
    for (int i = 0; i < 2; i++) {
        CGImageRef unknown = make(0, 1, hdr[i], kHalf);
        CHECK(unknown != NULL);
        CHECK(fabsf(CGImageGetContentHeadroom(unknown) - kCGDefaultHDRImageContentHeadroom) < 0.001f);
        CGImageRef known = make(2, 1, hdr[i], kHalf);
        CHECK(known != NULL && CGImageGetContentHeadroom(known) == 2);
        CGImageRef plain = make(0, 0, hdr[i], kHalf);
        CHECK(plain != NULL);
        CHECK(fabsf(CGImageGetContentHeadroom(plain) - kCGDefaultHDRImageContentHeadroom) < 0.001f);
        CGImageRelease(unknown);
        CGImageRelease(known);
        CGImageRelease(plain);
    }

    CGImageRelease(ext);
    CGImageRelease(sdr);
    if (failures == 0)
        printf("PASS: CGImage content headroom\n");
    return failures != 0;
}
