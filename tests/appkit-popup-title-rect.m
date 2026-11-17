// Copyright (C) 2026 Lubos Dolezel
//
// The title of a pop-up or pull-down button, as observed on macOS 10.14.4 (QUIRK-tagged in NSPopUpButtonCell):
//  - test_quirk_popup_title_left_aligned: the title is left aligned.
//  - test_quirk_popup_title_rect: -titleRectForBounds: starts 11 (pop-up, regular) from the left edge and leaves
//    32 points of the width for the arrows, with other values for the small and mini sizes and for pull-downs.
//  - test_popup_title_fits_intrinsic_width: a pop-up button as wide as its intrinsic content width draws any of
//    its titles in full (not shortened with an ellipsis); one 40 points narrower shortens the longest.
//  - test_quirk_popup_title_tightened: a title up to 4% wider than its area is drawn with tighter spacing
//    instead of being shortened.
//
// Build: clang -fobjc-arc -framework AppKit appkit-popup-title-rect.m
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSPopUpButton *makePopUp(BOOL pullsDown, NSControlSize size, CGFloat width) {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, width, 26) pullsDown:pullsDown];
    [[p cell] setControlSize:size];
    [p setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:size]]];
    [p addItemsWithTitles:@[@"Default Encoding", @"Western (Mac OS Roman)"]];
    return p;
}

static void test_quirk_popup_title_left_aligned(void) {
    CHECK([[makePopUp(NO, NSControlSizeRegular, 100) cell] alignment] == NSTextAlignmentLeft);
    CHECK([[makePopUp(YES, NSControlSizeSmall, 100) cell] alignment] == NSTextAlignmentLeft);
}

static void test_quirk_popup_title_rect(void) {
    // pop-up then pull-down; regular, small, mini: left inset and the width taken
    static const struct { BOOL pulls; NSControlSize size; CGFloat left, taken; } cases[] = {
        {NO, NSControlSizeRegular, 11, 32}, {NO, NSControlSizeSmall, 11, 31}, {NO, NSControlSizeMini, 11, 32},
        {YES, NSControlSizeRegular, 12, 34}, {YES, NSControlSizeSmall, 11, 33}, {YES, NSControlSizeMini, 10, 31},
    };
    for (int i = 0; i < 6; i++) {
        NSPopUpButton *p = makePopUp(cases[i].pulls, cases[i].size, 200);
        for (CGFloat w = 60; w <= 200; w += 140) {
            NSRect t = [[p cell] titleRectForBounds:NSMakeRect(0, 0, w, 26)];
            CHECK(t.origin.x == cases[i].left);
            CHECK(t.size.width == w - cases[i].taken);
        }
    }
}

// The width of the dark text pixels left of the arrows.
static int inkWidth(NSPopUpButton *p, int *left) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [[w contentView] addSubview:p];
    NSBitmapImageRep *rep = [p bitmapImageRepForCachingDisplayInRect:[p bounds]];
    [p cacheDisplayInRect:[p bounds] toBitmapImageRep:rep];
    int minx = 9999, maxx = -1, limit = (int)[p bounds].size.width - 21;
    for (int x = 0; x < limit; x++)
        for (int y = 0; y < (int)[rep pixelsHigh]; y++) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            if ([c alphaComponent] > .5 && [c redComponent] < .35 && [c greenComponent] < .35 && [c blueComponent] < .35) {
                if (x < minx) minx = x;
                if (x > maxx) maxx = x;
            }
        }
    [p removeFromSuperview];
    *left = minx;
    return maxx - minx + 1;
}

static void test_popup_title_fits_intrinsic_width(void) {
    NSControlSize sizes[2] = {NSControlSizeRegular, NSControlSizeSmall};
    NSString *titles[2] = {@"Default Encoding", @"Western (Mac OS Roman)"};
    for (int k = 0; k < 2; k++) {
        NSPopUpButton *p = makePopUp(NO, sizes[k], 100);
        CGFloat intrinsic = [p intrinsicContentSize].width;
        for (int i = 0; i < 2; i++) {
            [p selectItemAtIndex:i];
            CGFloat textWidth = [titles[i] sizeWithAttributes:@{NSFontAttributeName: [p font]}].width;
            int left;
            [p setFrameSize:NSMakeSize(intrinsic, 26)];
            // At the small size the widest title is about 3 points wider than the title area (the intrinsic width
            // adds 28, the area takes 31), so a character is dropped there on macOS as well.
            CHECK(inkWidth(p, &left) >= textWidth - (k == 1 && i == 1 ? 10 : 6));
            CHECK(left >= 11 && left <= 13);
            // 40 points narrower than the widest title needs: the longest one is shortened
            if (i == 1) {
                [p setFrameSize:NSMakeSize(intrinsic - 40, 26)];
                CHECK(inkWidth(p, &left) < textWidth - 10);
            }
        }
    }
}

// QUIRK test: a title up to 4% wider than its area is tightened, not shortened. A pop-up whose width is 3 points
// less than the title needs (area 3 points narrower than the text) draws all of it; one 8 points less shortens it.
static void test_quirk_popup_title_tightened(void) {
    NSControlSize sizes[2] = {NSControlSizeRegular, NSControlSizeSmall};
    CGFloat taken[2] = {32, 31};
    for (int k = 0; k < 2; k++) {
        NSPopUpButton *p = makePopUp(NO, sizes[k], 100);
        [p selectItemAtIndex:0];
        CGFloat textWidth = [@"Default Encoding" sizeWithAttributes:@{NSFontAttributeName: [p font]}].width;
        int left;
        [p setFrameSize:NSMakeSize(ceil(textWidth + taken[k] - 3), 26)];
        CHECK(inkWidth(p, &left) >= textWidth - 6);
        [p setFrameSize:NSMakeSize(ceil(textWidth + taken[k] - 9), 26)];
        CHECK(inkWidth(p, &left) < textWidth - 6);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_popup_title_left_aligned();
        test_quirk_popup_title_rect();
        test_popup_title_fits_intrinsic_width();
        test_quirk_popup_title_tightened();
        if (failures == 0)
            puts("PASS: pop-up button title");
        return failures != 0;
    }
}
