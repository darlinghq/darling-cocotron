// Copyright (C) 2026 Lubos Dolezel
//
// The text colours of the light appearance report the components of macOS 10.14, resolved in sRGB. Expected
// values were read through the public API on macOS 10.14.4 and 26.7.3 (black-box observation, see
// vd-upstream/mac-probes/aqua-leftovers-colors.m); test_quirk_control_text_color_alpha pins the QUIRK-tagged
// colours in DarlingDisplay. Passes on macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s line %d: %s\n", __func__, __LINE__, #c); failures++; } } while (0)

static BOOL srgbIs(NSColor *color, double r, double g, double b, double a) {
    NSColor *c = [color colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    if (c == nil) return NO;
    BOOL ok = fabs([c redComponent] - r) < 0.003 && fabs([c greenComponent] - g) < 0.003 &&
              fabs([c blueComponent] - b) < 0.003 && fabs([c alphaComponent] - a) < 0.003;
    if (!ok)
        fprintf(stderr, "  got %.3f %.3f %.3f %.3f\n", [c redComponent], [c greenComponent], [c blueComponent],
                [c alphaComponent]);
    return ok;
}

static void test_quirk_control_text_color_alpha(void) {
    CHECK(srgbIs([NSColor controlTextColor], 0, 0, 0, 0.847));
    CHECK(srgbIs([NSColor selectedControlTextColor], 0, 0, 0, 0.847));
    CHECK(srgbIs([NSColor windowFrameTextColor], 0, 0, 0, 0.847));
    // In the calibrated white space the alpha is kept too.
    NSColor *w = [[NSColor controlTextColor] colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
    CHECK(w != nil && fabs([w whiteComponent]) < 0.003 && fabs([w alphaComponent] - 0.847) < 0.003);
}

static void test_other_text_colors(void) {
    CHECK(srgbIs([NSColor labelColor], 0, 0, 0, 0.847));
    CHECK(srgbIs([NSColor secondaryLabelColor], 0, 0, 0, 0.498));
    CHECK(srgbIs([NSColor quaternaryLabelColor], 0, 0, 0, 0.098));
    CHECK(srgbIs([NSColor disabledControlTextColor], 0, 0, 0, 0.247));
    CHECK(srgbIs([NSColor placeholderTextColor], 0, 0, 0, 0.247));
    CHECK(srgbIs([NSColor headerTextColor], 0, 0, 0, 0.847));
    CHECK(srgbIs([NSColor textColor], 0, 0, 0, 1));
    CHECK(srgbIs([NSColor alternateSelectedControlTextColor], 1, 1, 1, 1));
    CHECK(srgbIs([NSColor selectedMenuItemTextColor], 1, 1, 1, 1));
    CHECK(srgbIs([NSColor unemphasizedSelectedTextColor], 0, 0, 0, 1));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_control_text_color_alpha();
        test_other_text_colors();
    }
    if (failures) { printf("FAIL (%d)\n", failures); return 1; }
    printf("PASS\n");
    return 0;
}
