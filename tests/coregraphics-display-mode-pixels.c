/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>

// Needs a display (run on the X server of the guest). Run it with GDK_SCALE=2
// (or the X11BackingScale preference) to check a scaled display: the mode
// width and height, CGDisplayPixelsWide/High and CGDisplayBounds are in
// points, and only CGDisplayModeGetPixelWidth/Height are device pixels.
int main(void) {
    const char *env = getenv("GDK_SCALE");
    size_t scale = env ? (size_t) atoi(env) : 1;
    if (scale < 1)
        scale = 1;
    CGDirectDisplayID display = CGMainDisplayID();
    if (display == kCGNullDirectDisplay) {
        printf("no display\n");
        return 2;
    }

    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
    if (!mode)
        return 10;
    size_t width = CGDisplayModeGetWidth(mode), height = CGDisplayModeGetHeight(mode);
    size_t pixelWidth = CGDisplayModeGetPixelWidth(mode), pixelHeight = CGDisplayModeGetPixelHeight(mode);
    printf("mode %zux%zu pixels %zux%zu\n", width, height, pixelWidth, pixelHeight);
    if (pixelWidth == 0 || pixelHeight == 0)
        return 11;
    // The mode is addressed in points; its pixel size is scale times that.
    if (pixelWidth != width * scale || pixelHeight != height * scale)
        return 12;
    // The display's own size is in points as well, and so is its bounds.
    CGRect bounds = CGDisplayBounds(display);
    if (CGDisplayPixelsWide(display) != width || CGDisplayPixelsHigh(display) != height ||
        (size_t) bounds.size.width != width || (size_t) bounds.size.height != height)
        return 17;

    CFStringRef encoding = CGDisplayModeCopyPixelEncoding(mode);
    if (!encoding)
        return 13;
    char text[64] = "";
    CFStringGetCString(encoding, text, sizeof text, kCFStringEncodingUTF8);
    printf("encoding %s\n", text);
    // 24- and 32-bit modes use the 32-bit direct pixel format.
    if (CFStringGetLength(encoding) != 32)
        return 14;
    CFRelease(encoding);
    CGDisplayModeRelease(mode);

    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, NULL);
    if (!modes || CFArrayGetCount(modes) == 0)
        return 15;
    for (CFIndex i = 0; i < CFArrayGetCount(modes); i++) {
        CGDisplayModeRef each = (CGDisplayModeRef) CFArrayGetValueAtIndex(modes, i);
        size_t w = CGDisplayModeGetWidth(each), h = CGDisplayModeGetHeight(each);
        if (CGDisplayModeGetPixelWidth(each) == 0 || CGDisplayModeGetPixelHeight(each) == 0)
            return 16;
        // Rounding to whole points can lose half a point at fractional sizes.
        if (CGDisplayModeGetPixelWidth(each) / scale != w && (CGDisplayModeGetPixelWidth(each) + scale - 1) / scale != w)
            return 18;
        if (CGDisplayModeGetPixelHeight(each) / scale != h && (CGDisplayModeGetPixelHeight(each) + scale - 1) / scale != h)
            return 19;
    }
    CFRelease(modes);
    return 0;
}
