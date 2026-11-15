/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// CGDirectPalette.h: palette objects. Expected values were observed black-box
// on Mac OS X 10.14.4 (i386 and x86_64) and match the classic Mac 8-bit color
// table described in Inside Macintosh: Advanced Color Imaging. Exit code 0 is
// success, otherwise the number of the failed check.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGDirectPalette.h>
#include <math.h>
#include <stdio.h>

static int near(float a, float b) {
    return fabsf(a - b) < 0.0005f;
}

static int colorIs(CGDirectPaletteRef palette, CGTableCount index, unsigned rgb) {
    CGDeviceColor c = CGPaletteGetColorAtIndex(palette, index);
    return near(c.red, ((rgb >> 16) & 0xFF) / 255.0f) && near(c.green, ((rgb >> 8) & 0xFF) / 255.0f) &&
           near(c.blue, (rgb & 0xFF) / 255.0f);
}

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

int main(void) {
    // The default palette: 256 entries, a color cube, ramps, white and black exchanged at the ends.
    CGDirectPaletteRef def = CGPaletteCreateDefaultColorPalette();
    CHECK(1, def != NULL);
    CHECK(2, CGPaletteGetNumberOfSamples(def) == 256);
    CHECK(3, colorIs(def, 0, 0x000000));
    CHECK(4, colorIs(def, 1, 0xFFFFCC));
    CHECK(5, colorIs(def, 2, 0xFFFF99));
    CHECK(6, colorIs(def, 7, 0xFFCCCC));
    CHECK(7, colorIs(def, 100, 0x993333));
    CHECK(8, colorIs(def, 214, 0x000033));
    CHECK(9, colorIs(def, 215, 0xEE0000));
    CHECK(10, colorIs(def, 224, 0x110000));
    CHECK(11, colorIs(def, 225, 0x00EE00));
    CHECK(12, colorIs(def, 235, 0x0000EE));
    CHECK(13, colorIs(def, 245, 0xEEEEEE));
    CHECK(14, colorIs(def, 254, 0x111111));
    CHECK(15, colorIs(def, 255, 0xFFFFFF));
    // Out of range reads as black.
    CHECK(16, colorIs(def, 256, 0x000000) && colorIs(def, 100000, 0x000000));
    // It is a CoreFoundation object (a CFData), so CFRetain and CFRelease apply.
    CHECK(17, CFGetTypeID((CFTypeRef) def) == CFDataGetTypeID());
    CFRetain((CFTypeRef) def);
    CHECK(18, CFGetRetainCount((CFTypeRef) def) == 2);
    CFRelease((CFTypeRef) def);
    CHECK(19, CFGetRetainCount((CFTypeRef) def) == 1);

    // Nearest color lookup.
    CGDeviceColor white = {1, 1, 1}, black = {0, 0, 0}, red = {1, 0, 0}, grey = {0.5f, 0.5f, 0.5f};
    CHECK(20, CGPaletteGetIndexForColor(def, white) == 255);
    CHECK(21, CGPaletteGetIndexForColor(def, black) == 0);
    CHECK(22, CGPaletteGetIndexForColor(def, red) == 35);
    CHECK(23, CGPaletteGetIndexForColor(def, grey) == 250);
    CGDeviceColor odd = {0.3f, 0.6f, 0.9f}, nearBlack = {0.1f, 0.1f, 0.1f}, nearRed = {0.1f, 0, 0};
    CHECK(24, CGPaletteGetIndexForColor(def, odd) == 121);
    CHECK(25, CGPaletteGetIndexForColor(def, nearBlack) == 254);
    CHECK(26, CGPaletteGetIndexForColor(def, nearRed) == 224);
    CGDeviceColor slightlyOut = {1.5f, 0.5f, 0.5f}, belowZero = {-0.0001f, 0.5f, 0.5f};
    CHECK(27, CGPaletteGetIndexForColor(def, slightlyOut) == 21);
    CHECK(28, CGPaletteGetIndexForColor(def, belowZero) == 201);

    // QUIRK test: colors far outside 0...1 have no nearest entry (see CGPaletteGetIndexForColor).
    CGDeviceColor farBelow = {-1, -1, -1}, farAbove = {5, 5, 5};
    CHECK(29, CGPaletteGetIndexForColor(def, farBelow) == kCGPaletteNoIndex);   // quirk_index_for_distant_color
    CHECK(30, CGPaletteGetIndexForColor(def, farAbove) == kCGPaletteNoIndex);   // quirk_index_for_distant_color
    CGDeviceColor farMixed1 = {1.6f, 1.7f, 1.5f}, farMixed2 = {1.7f, 1.7f, -0.3f}, nearOut = {-0.3f, -0.3f, -0.3f};
    CHECK(31, CGPaletteGetIndexForColor(def, farMixed1) == kCGPaletteNoIndex);  // quirk_index_for_distant_color
    CHECK(32, CGPaletteGetIndexForColor(def, farMixed2) == kCGPaletteNoIndex);  // quirk_index_for_distant_color
    CHECK(33, CGPaletteGetIndexForColor(def, nearOut) == 0);
    // Exact ties between entries (values from the Mac): the lower index wins unless the rounding of the levels decides.
    CGDeviceColor tie1 = {0.3f, 0.3f, 0.3f}, tie2 = {0.9f, 0.9f, 0.9f}, tie3 = {0.5f, 0.5f, 1.5f};
    CGDeviceColor tie4 = {0.5f, 1.5f, 0.3f}, tie5 = {1.5f, 0.5f, 0.6f}, tie6 = {0.5f, 1.5f, 0.6f}, tie7 = {1.5f, 0.5f, 0.3f};
    CHECK(34, CGPaletteGetIndexForColor(def, tie1) == 251);
    CHECK(35, CGPaletteGetIndexForColor(def, tie2) == 246);
    CHECK(36, CGPaletteGetIndexForColor(def, tie3) == 126);
    CHECK(37, CGPaletteGetIndexForColor(def, tie4) == 111);
    CHECK(38, CGPaletteGetIndexForColor(def, tie5) == 20);
    CHECK(39, CGPaletteGetIndexForColor(def, tie6) == 110);
    CHECK(40, CGPaletteGetIndexForColor(def, tie7) == 21);

    // Copies are independent; equality compares the entries.
    CGDirectPaletteRef fresh = CGPaletteCreateDefaultColorPalette();
    CGDirectPaletteRef copy = CGPaletteCreateCopy(fresh);
    CHECK(41, copy != NULL && copy != fresh && CGPaletteIsEqualToPalette(fresh, copy));
    CGPaletteSetColorAtIndex(copy, red, 5);
    CHECK(42, colorIs(copy, 5, 0xFF0000));
    CHECK(43, colorIs(fresh, 5, 0xFFFF00));
    CHECK(44, !CGPaletteIsEqualToPalette(fresh, copy));
    CHECK(45, CGPaletteIsEqualToPalette(def, def));
    // Values are stored without clamping.
    CGPaletteSetColorAtIndex(copy, red, 300);
    CHECK(46, CGPaletteGetNumberOfSamples(copy) == 256);
    CGDeviceColor unclamped = {2.0f, -1.0f, 0.5f};
    CGPaletteSetColorAtIndex(copy, unclamped, 6);
    CGDeviceColor got = CGPaletteGetColorAtIndex(copy, 6);
    CHECK(47, got.red == 2.0f && got.green == -1.0f && got.blue == 0.5f);
    CGPaletteRelease(copy);
    CGPaletteRelease(fresh);

    // Capacity: entries start as the default palette.
    CGDirectPaletteRef cap10 = CGPaletteCreateWithCapacity(10);
    CHECK(48, cap10 && CGPaletteGetNumberOfSamples(cap10) == 10 && colorIs(cap10, 6, 0xFFCCFF));
    CGDirectPaletteRef cap5 = CGPaletteCreateWithCapacity(5), cap5b = CGPaletteCreateWithCapacity(5);
    CHECK(49, !CGPaletteIsEqualToPalette(cap5, cap10) && CGPaletteIsEqualToPalette(cap5, cap5b));
    CGPaletteRelease(cap10);
    CGPaletteRelease(cap5);
    CGPaletteRelease(cap5b);
    CGDirectPaletteRef zero = CGPaletteCreateWithCapacity(0);
    CHECK(50, zero != NULL && CGPaletteGetNumberOfSamples(zero) == 0);
    CGDeviceColor anyColor = {0.5f, 0.5f, 0.5f};
    CHECK(51, CGPaletteGetIndexForColor(zero, anyColor) == kCGPaletteNoIndex);
    CGPaletteRelease(zero);

    // Samples.
    CGDeviceByteColor bytes[3] = {{255, 0, 128}, {1, 2, 3}, {0, 0, 0}};
    CGDirectPaletteRef byteP = CGPaletteCreateWithByteSamples(bytes, 3);
    CHECK(52, byteP && CGPaletteGetNumberOfSamples(byteP) == 3);
    CHECK(53, colorIs(byteP, 0, 0xFF0080) && colorIs(byteP, 1, 0x010203));
    CGDeviceColor samples[2] = {{0.25f, 0.5f, 0.75f}, {1.5f, 0, 0}};
    CGDirectPaletteRef sampleP = CGPaletteCreateWithSamples(samples, 2);
    got = CGPaletteGetColorAtIndex(sampleP, 1);
    CHECK(54, CGPaletteGetNumberOfSamples(sampleP) == 2 && got.red == 1.5f);
    CGDirectPaletteRef emptyP = CGPaletteCreateWithSamples(NULL, 0);
    CHECK(55, emptyP != NULL && CGPaletteGetNumberOfSamples(emptyP) == 0);
    CGPaletteRelease(emptyP);
    CGPaletteRelease(sampleP);

    // Blending moves each entry towards the color; the fraction is limited to 0...1.
    CGDirectPaletteRef half = CGPaletteCreateFromPaletteBlendedWithColor(byteP, 0.5f, white);
    got = CGPaletteGetColorAtIndex(half, 0);
    CHECK(56, near(got.red, 1.0f) && near(got.green, 0.5f) && near(got.blue, 0.75098f));
    got = CGPaletteGetColorAtIndex(half, 2);
    CHECK(57, near(got.red, 0.5f) && near(got.green, 0.5f) && near(got.blue, 0.5f));
    CGDirectPaletteRef none = CGPaletteCreateFromPaletteBlendedWithColor(def, 0.0f, nearBlack);
    CHECK(58, CGPaletteIsEqualToPalette(def, none));
    CGDirectPaletteRef full = CGPaletteCreateFromPaletteBlendedWithColor(def, 2.0f, nearBlack);
    got = CGPaletteGetColorAtIndex(full, 7);
    CHECK(59, near(got.red, 0.1f) && near(got.green, 0.1f) && near(got.blue, 0.1f));
    CGDirectPaletteRef negative = CGPaletteCreateFromPaletteBlendedWithColor(def, -1.0f, nearBlack);
    CHECK(60, colorIs(negative, 7, 0xFFCCCC));
    CGPaletteRelease(half);
    CGPaletteRelease(none);
    CGPaletteRelease(full);
    CGPaletteRelease(negative);
    CGPaletteRelease(byteP);

    // No display here has an indexed pixel format, so there is no palette for one.
    CHECK(61, CGPaletteCreateWithDisplay(0) == NULL);

    CGPaletteRelease(def);

    // A capacity beyond 256 (last, and never released, like the check after it).
    CGDirectPaletteRef cap = CGPaletteCreateWithCapacity(300);
    CHECK(62, cap && CGPaletteGetNumberOfSamples(cap) == 300);
    CHECK(63, colorIs(cap, 0, 0x000000) && colorIs(cap, 3, 0xFFFF66) && colorIs(cap, 250, 0x777777));
    CHECK(64, colorIs(cap, 256, 0x000000) && colorIs(cap, 299, 0x000000));
    // Setting an index past the end changes nothing (last: the macOS used for the expected values damages the heap).
    CGPaletteSetColorAtIndex(cap, red, 300);
    CHECK(65, CGPaletteGetNumberOfSamples(cap) == 300 && colorIs(cap, 299, 0x000000));
    printf("PASS\n");
    return 0;
}
