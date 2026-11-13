/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

// Needs a display (run on the X server of the guest).
int main(void) {
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
    // A mode never has fewer pixels than points, and never none at all.
    if (pixelWidth == 0 || pixelHeight == 0)
        return 11;
    if (pixelWidth < width || pixelHeight < height)
        return 12;

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
        if (CGDisplayModeGetPixelWidth(each) == 0 || CGDisplayModeGetPixelHeight(each) == 0)
            return 16;
    }
    CFRelease(modes);
    return 0;
}
