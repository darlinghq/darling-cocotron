/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// The legacy CGDisplay calls of CGDirectDisplay.h: mode dictionaries, best
// mode lookup, framebuffer queries, beam position and palette support.
// Needs a display (run on the X server of the guest). Expected values
// were observed on Mac OS X 10.14.4 (i386 and x86_64). Exit code 0 is success,
// otherwise the number of the failed check. Set CG_TEST_NO_FRAMEBUFFER_ACCESS
// to skip reading and writing through CGDisplayBaseAddress (on a real Mac the
// address need not be mapped for the process).
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

static long number(CFDictionaryRef dict, CFStringRef key, int *found) {
    CFNumberRef value = dict ? CFDictionaryGetValue(dict, key) : NULL;
    long result = 0;
    *found = value && CFGetTypeID(value) == CFNumberGetTypeID() &&
             CFNumberGetValue(value, kCFNumberLongType, &result);
    return result;
}

int main(void) {
    CGDirectDisplayID display = CGMainDisplayID();
    if (display == kCGNullDirectDisplay) {
        printf("no display\n");
        return 2;
    }
    int found;

    // kCGDirectMainDisplay stands for the main display.
    CHECK(1, kCGDirectMainDisplay == display);

    // The current mode and the list of modes carry the documented keys.
    CFDictionaryRef current = CGDisplayCurrentMode(display);
    CHECK(2, current != NULL);
    long width = number(current, kCGDisplayWidth, &found);
    CHECK(3, found && width > 0 && (size_t) width == CGDisplayPixelsWide(display));
    long height = number(current, kCGDisplayHeight, &found);
    CHECK(4, found && height > 0 && (size_t) height == CGDisplayPixelsHigh(display));
    long bpp = number(current, kCGDisplayBitsPerPixel, &found);
    CHECK(5, found && (bpp == 32 || bpp == 16 || bpp == 8));
    long samples = number(current, kCGDisplaySamplesPerPixel, &found);
    CHECK(6, found && samples == (bpp > 8 ? 3 : 1));
    long perSample = number(current, kCGDisplayBitsPerSample, &found);
    CHECK(7, found && perSample == (bpp >= 24 ? 8 : (bpp == 16 ? 5 : 8)));
    long rate = number(current, kCGDisplayRefreshRate, &found);
    CHECK(8, found && rate >= 0);
    long bytesPerRow = number(current, kCGDisplayBytesPerRow, &found);
    CHECK(9, found && bytesPerRow > 0 && (size_t) bytesPerRow == CGDisplayBytesPerRow(display));
    CHECK(10, CGDisplayBitsPerPixel(display) == (size_t) bpp && CGDisplaySamplesPerPixel(display) == (size_t) samples &&
              CGDisplayBitsPerSample(display) == (size_t) perSample);
    CFArrayRef modes = CGDisplayAvailableModes(display);
    CHECK(11, modes != NULL && CFArrayGetCount(modes) >= 1);
    for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
        CFDictionaryRef mode = CFArrayGetValueAtIndex(modes, i);
        long index = number(mode, kCGDisplayMode, &found);
        CHECK(12, found && index == (long) i);
        number(mode, kCGDisplayWidth, &found);
        CHECK(13, found);
        number(mode, kCGDisplayBitsPerPixel, &found);
        CHECK(14, found);
    }

    // Best mode: a request for the current mode is an exact match.
    boolean_t exact = 77;
    CFDictionaryRef best = CGDisplayBestModeForParameters(display, bpp, width, height, &exact);
    CHECK(15, best != NULL && exact == 1);
    CHECK(16, number(best, kCGDisplayWidth, &found) == width && number(best, kCGDisplayHeight, &found) == height);
    exact = 77;
    best = CGDisplayBestModeForParametersAndRefreshRate(display, bpp, width, height, 0, &exact);
    CHECK(17, best != NULL && exact == 1);
    // The exact flag may be left out.
    CHECK(18, CGDisplayBestModeForParameters(display, bpp, width, height, NULL) != NULL);
    // A request that no mode matches still gets the closest mode, not an exact one.
    exact = 77;
    best = CGDisplayBestModeForParameters(display, bpp, width + 1, height + 1, &exact);
    CHECK(19, best != NULL && exact == 0);
    exact = 77;
    best = CGDisplayBestModeForParameters(display, bpp, 100000, 100000, &exact);
    CHECK(20, best != NULL && exact == 0);
    exact = 77;
    best = CGDisplayBestModeForParameters(display, bpp, 1, 1, &exact);
    CHECK(21, best != NULL && exact == 0);
    // No mode has a pixel depth of 3: a shallower request is met by a deeper mode.
    exact = 77;
    best = CGDisplayBestModeForParameters(display, 3, width, height, &exact);
    CHECK(22, best != NULL && exact == 0 && number(best, kCGDisplayBitsPerPixel, &found) >= 8);
    // An unknown display has no modes and leaves the flag alone.
    exact = 77;
    CHECK(23, CGDisplayBestModeForParameters(0x7fffff01, 32, 640, 480, &exact) == NULL && exact == 77);
    // The refresh rate of a mode that reports none (flat panels) matches any request.
    if (rate == 0) {
        exact = 77;
        best = CGDisplayBestModeForParametersAndRefreshRate(display, bpp, width, height, 75.0, &exact);
        CHECK(24, best != NULL && exact == 1);
    }

    // Switching to the current mode works, to nothing does not.
    CHECK(25, CGDisplaySwitchToMode(display, current) == kCGErrorSuccess);
    CHECK(26, CGDisplaySwitchToMode(display, CGDisplayBestModeForParameters(display, bpp, width, height, NULL)) == kCGErrorSuccess);

    // Framebuffer queries.
    void *base = CGDisplayBaseAddress(display);
    CHECK(27, base != NULL && CGDisplayBaseAddress(display) == base);
    CHECK(28, CGDisplayBytesPerRow(0x7fffff01) == 0 && CGDisplayBitsPerPixel(0x7fffff01) == 0);
    if (!getenv("CG_TEST_NO_FRAMEBUFFER_ACCESS")) {
        // A whole mode's worth of pixels can be written, and addresses follow the row size.
        long pixelsHigh = number(current, CFSTR("kCGDisplayPixelsHigh"), &found);
        CHECK(29, found && pixelsHigh > 0);
        unsigned char *bytes = base;
        bytes[(size_t) bytesPerRow * pixelsHigh - 1] = 0x5A;
        CHECK(30, bytes[(size_t) bytesPerRow * pixelsHigh - 1] == 0x5A);
        CHECK(31, CGDisplayAddressForPosition(display, 3, 2) == bytes + 2 * (size_t) bytesPerRow + 3 * (bpp / 8));
        CHECK(32, CGDisplayAddressForPosition(display, -1, 0) == NULL && CGDisplayAddressForPosition(display, 0, -1) == NULL);
        CHECK(33, CGDisplayAddressForPosition(display, 0, 0) == base);
    }

    // The beam position is 0 and no palette can be set.
    CHECK(34, CGDisplayBeamPosition(display) == 0);
    CHECK(35, CGDisplayCanSetPalette(display) == 0);
    CGDirectPaletteRef palette = CGPaletteCreateDefaultColorPalette();
    CHECK(36, palette != NULL);
    CHECK(37, CGDisplaySetPalette(display, palette) == kCGErrorNoneAvailable);
    CGPaletteRelease(palette);
    CHECK(38, CGPaletteCreateWithDisplay(display) == NULL);

    printf("PASS\n");
    return 0;
}
