// Copyright (C) 2026 Lubos Dolezel
//
// -[NSSliderCell barRectFlipped:] of a linear slider reports the bar rectangle of macOS 10.14: across the slider
// it depends on the thickness of the view, the control size, the tick marks and the argument. Expected values were
// read through the public API on macOS 10.14.4 (black-box observation, see
// vd-upstream/mac-probes/aqua-leftovers-bar.m); test_quirk_slider_bar_rect pins the QUIRK-tagged behaviour of the
// same name in NSSliderCell. Passes on macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

// older SDK headers lack the declaration
@interface NSSliderCell (BarRectDeclaration)
- (NSRect) barRectFlipped: (BOOL) flipped;
@end

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s line %d: %s\n", __func__, __LINE__, #c); failures++; } } while (0)

static NSRect barRect(BOOL vertical, int thickness, NSControlSize size, int ticks, BOOL flipped) {
    NSSlider *sl = [[[NSSlider alloc] initWithFrame: vertical ? NSMakeRect(0, 0, thickness, 200) : NSMakeRect(0, 0, 200, thickness)] autorelease];
    [sl setMinValue: 0];
    [sl setMaxValue: 100];
    [sl setDoubleValue: 40];
    [[sl cell] setControlSize: size];
    if (vertical)
        [sl setFrameSize: NSMakeSize(thickness, 200)];
    if (ticks) {
        [sl setNumberOfTickMarks: 5];
        [sl setTickMarkPosition: ticks == 1 ? (vertical ? NSTickMarkRight : NSTickMarkBelow) : (vertical ? NSTickMarkLeft : NSTickMarkAbove)];
    }
    return [[sl cell] barRectFlipped: flipped];
}

static void test_quirk_slider_bar_rect(void) {
    NSControlSize sizes[3] = {NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini};
    // a 30 point thick view, as in the probe output: horizontal {x, y, width, height} for flipped NO and YES
    int h30[3][3][2] = {{{12, 12}, {15, 10}, {9, 16}}, {{12, 12}, {15, 10}, {10, 15}}, {{12, 12}, {14, 11}, {11, 14}}};
    int widths[3] = {194, 198, 198};
    int heights[3] = {5, 5, 4};
    int insets[3] = {3, 1, 1};
    for (int z = 0; z < 3; z++)
        for (int t = 0; t < 3; t++)
            for (int f = 0; f < 2; f++) {
                NSRect r = barRect(NO, 30, sizes[z], t, f);
                CHECK(r.origin.y == h30[z][t][f] && r.size.height == heights[z]);
                CHECK(r.origin.x == insets[z] && r.size.width == widths[z]);
            }
    // vertical sliders: x across (the argument makes no difference), y and height along
    int v30[3][3] = {{13, 9, 16}, {13, 10, 15}, {14, 12, 15}};
    for (int z = 0; z < 3; z++)
        for (int t = 0; t < 3; t++)
            for (int f = 0; f < 2; f++) {
                NSRect r = barRect(YES, 30, sizes[z], t, f);
                CHECK(r.origin.x == v30[z][t] && r.size.width == heights[z]);
                CHECK(r.origin.y == insets[z] && r.size.height == widths[z]);
            }
    // other thicknesses: odd leftovers (horizontal, regular, ticks below, not flipped: floor(h / 2), flipped:
    // floor((h - 10) / 2)); regular without ticks floor((h - 5) / 2)
    CHECK(barRect(NO, 11, NSControlSizeRegular, 1, NO).origin.y == 5 && barRect(NO, 12, NSControlSizeRegular, 1, NO).origin.y == 6);
    CHECK(barRect(NO, 11, NSControlSizeRegular, 1, YES).origin.y == 0 && barRect(NO, 12, NSControlSizeRegular, 1, YES).origin.y == 1);
    CHECK(barRect(NO, 11, NSControlSizeRegular, 0, NO).origin.y == 3 && barRect(NO, 40, NSControlSizeRegular, 0, NO).origin.y == 17);
    CHECK(barRect(NO, 10, NSControlSizeRegular, 2, NO).origin.y == -1 && barRect(NO, 40, NSControlSizeMini, 2, YES).origin.y == 19);
    CHECK(barRect(YES, 10, NSControlSizeRegular, 2, NO).origin.x == 6 && barRect(YES, 40, NSControlSizeMini, 1, NO).origin.x == 17);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_slider_bar_rect();
    }
    if (failures) { printf("FAIL (%d)\n", failures); return 1; }
    printf("PASS\n");
    return 0;
}
