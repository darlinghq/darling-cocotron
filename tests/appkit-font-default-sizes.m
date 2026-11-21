// Copyright (C) 2026 Lubos Dolezel
//
// The NSFont size class methods and the default sizes of the font factory
// methods (size 0 or negative), as macOS 10.14.4 reports them (black-box
// observation; 26.7.3 agrees except where a check says so).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK_SIZE(what, value, expected) do { \
    CGFloat v_ = (value); \
    if (v_ != (expected)) { \
        fprintf(stderr, "FAIL %s: %g, expected %g\n", what, v_, (double) (expected)); \
        failures++; \
    } } while (0)

static void test_size_class_methods(void) {
    CHECK_SIZE("systemFontSize", [NSFont systemFontSize], 13);
    CHECK_SIZE("smallSystemFontSize", [NSFont smallSystemFontSize], 11);
    CHECK_SIZE("labelFontSize", [NSFont labelFontSize], 10);
    CHECK_SIZE("systemFontSizeForControlSize regular", [NSFont systemFontSizeForControlSize: NSControlSizeRegular], 13);
    CHECK_SIZE("systemFontSizeForControlSize small", [NSFont systemFontSizeForControlSize: NSControlSizeSmall], 11);
    CHECK_SIZE("systemFontSizeForControlSize mini", [NSFont systemFontSizeForControlSize: NSControlSizeMini], 9);
}

static void test_default_sizes(void) {
    CHECK_SIZE("systemFontOfSize:0", [[NSFont systemFontOfSize: 0] pointSize], 13);
    CHECK_SIZE("boldSystemFontOfSize:0", [[NSFont boldSystemFontOfSize: 0] pointSize], 13);
    CHECK_SIZE("messageFontOfSize:0", [[NSFont messageFontOfSize: 0] pointSize], 13);
    CHECK_SIZE("labelFontOfSize:0", [[NSFont labelFontOfSize: 0] pointSize], 10);
    CHECK_SIZE("titleBarFontOfSize:0", [[NSFont titleBarFontOfSize: 0] pointSize], 13);
    CHECK_SIZE("controlContentFontOfSize:0", [[NSFont controlContentFontOfSize: 0] pointSize], 12);
    // a negative size also means the default size
    CHECK_SIZE("systemFontOfSize:-1", [[NSFont systemFontOfSize: -1] pointSize], 13);
    CHECK_SIZE("labelFontOfSize:-1", [[NSFont labelFontOfSize: -1] pointSize], 10);
    // an explicit size is kept
    CHECK_SIZE("systemFontOfSize:20", [[NSFont systemFontOfSize: 20] pointSize], 20);
    CHECK_SIZE("labelFontOfSize:15", [[NSFont labelFontOfSize: 15] pointSize], 15);
    CHECK_SIZE("menuFontOfSize:15", [[NSFont menuFontOfSize: 15] pointSize], 15);
}

// The title bar font is the regular face on 10.14.
static void test_title_bar_font(void) {
    NSFont *font = [NSFont titleBarFontOfSize: 0];
    if ([[NSFontManager sharedFontManager] traitsOfFont: font] & NSBoldFontMask) {
        fprintf(stderr, "FAIL titleBarFontOfSize:0 is bold (%s)\n", [[font fontName] UTF8String]);
        failures++;
    }
}

// QUIRK: menuFontOfSize:0 gives 13 points, menuBarFontOfSize:0 14 on 10.14
// (13 on macOS 26). See +[NSFont menuFontOfSize:].
static void test_quirk_menu_fonts(void) {
    CHECK_SIZE("menuFontOfSize:0", [[NSFont menuFontOfSize: 0] pointSize], 13);
    CHECK_SIZE("menuFontOfSize:-1", [[NSFont menuFontOfSize: -1] pointSize], 13);
    if (NSAppKitVersionNumber < 2000)
        CHECK_SIZE("menuBarFontOfSize:0", [[NSFont menuBarFontOfSize: 0] pointSize], 14);
}

// QUIRK: the palette and tool tip fonts default to 11 points. See
// +[NSFont paletteFontOfSize:].
static void test_quirk_palette_tooltip_fonts(void) {
    CHECK_SIZE("paletteFontOfSize:0", [[NSFont paletteFontOfSize: 0] pointSize], 11);
    CHECK_SIZE("toolTipsFontOfSize:0", [[NSFont toolTipsFontOfSize: 0] pointSize], 11);
}

// QUIRK: the fixed pitch user font defaults to 10 points on 10.14 (11 on macOS
// 26). See +[NSFont userFixedPitchFontOfSize:].
static void test_quirk_user_fonts(void) {
    CHECK_SIZE("userFontOfSize:0", [[NSFont userFontOfSize: 0] pointSize], 12);
    if (NSAppKitVersionNumber < 2000)
        CHECK_SIZE("userFixedPitchFontOfSize:0", [[NSFont userFixedPitchFontOfSize: 0] pointSize], 10);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_size_class_methods();
        test_default_sizes();
        test_title_bar_font();
        test_quirk_menu_fonts();
        test_quirk_palette_tooltip_fonts();
        test_quirk_user_fonts();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
