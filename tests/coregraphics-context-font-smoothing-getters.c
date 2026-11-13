// Copyright (C) 2026 Lubos Dolezel
//
// The CoreGraphics context state getters and the font smoothing style.
// Defaults and save/restore behaviour as observed on macOS 26.7.3 for a
// bitmap context: antialiasing, font smoothing allowed and font smoothing
// requested are on, the style is 0x30. Antialiasing and "allows font
// smoothing" belong to the context, while the smoothing request and the style
// are part of the saved graphics state.
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

int main(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, 4, 4, 8, 16, space,
                                           kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CHECK(c != NULL, "context");
    if (c == NULL)
        return 1;

    CHECK(CGContextGetAllowsAntialiasing(c), "default allows antialiasing");
    CHECK(CGContextGetAllowsFontSmoothing(c), "default allows font smoothing");
    CHECK(CGContextGetShouldSmoothFonts(c), "default should smooth fonts");
    CHECK(CGContextGetFontSmoothingStyle(c) == 0x30, "default style 0x30");

    CGContextSaveGState(c);
    CGContextSetAllowsAntialiasing(c, false);
    CGContextSetAllowsFontSmoothing(c, false);
    CGContextSetShouldSmoothFonts(c, false);
    CGContextSetFontSmoothingStyle(c, 0x20);
    CHECK(!CGContextGetAllowsAntialiasing(c), "antialiasing off");
    CHECK(!CGContextGetAllowsFontSmoothing(c), "font smoothing not allowed");
    CHECK(!CGContextGetShouldSmoothFonts(c), "should smooth off");
    CHECK(CGContextGetFontSmoothingStyle(c) == 0x20, "style 0x20");

    CGContextRestoreGState(c);
    CHECK(!CGContextGetAllowsAntialiasing(c), "antialiasing is context state, not restored");
    CHECK(!CGContextGetAllowsFontSmoothing(c), "allows font smoothing is context state, not restored");
    CHECK(CGContextGetShouldSmoothFonts(c), "should smooth restored to on");
    CHECK(CGContextGetFontSmoothingStyle(c) == 0x30, "style restored to 0x30");

    CGContextSetAllowsAntialiasing(c, true);
    CGContextSetAllowsFontSmoothing(c, true);
    CHECK(CGContextGetAllowsAntialiasing(c) && CGContextGetAllowsFontSmoothing(c), "set back on");

    CGContextRelease(c);
    CGColorSpaceRelease(space);
    if (failures == 0)
        printf("PASS: font smoothing getters\n");
    return failures ? 1 : 0;
}
