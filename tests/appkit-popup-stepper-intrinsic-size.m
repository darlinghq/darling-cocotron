// Copyright (C) 2026 Lubos Dolezel
//
// Intrinsic sizes of a pop-up button and a stepper, as observed on macOS 10.14.4 (the values of
// macOS 26.7.3 are different and not followed).
//  - test_quirk_popup_widest_item_width: a pop-up button (not a pull-down) is as wide as its widest
//    item whichever item is selected: the widest title plus 32, 28 and 33 points, rounded up, at the
//    regular, small and mini control sizes. Text widths come from the control's own font,
//    so the test holds whatever the font is.
//  - test_quirk_stepper_intrinsic_size: a stepper's intrinsic size with its alignment insets added is
//    19x27, 15x22 and 13x15 points at the three control sizes (it was 10000x10000 before).
//
// Build: clang -fobjc-arc -framework AppKit appkit-popup-stepper-intrinsic-size.m
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static CGFloat width(NSString *title, NSFont *font) {
    return [title sizeWithAttributes:@{NSFontAttributeName: font}].width;
}

static void test_quirk_popup_widest_item_width(void) {
    NSControlSize sizes[3] = {NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini};
    CGFloat extra[3] = {32, 28, 33};
    NSArray *titles = @[@"Short", @"Western (Mac OS Roman)", @"Mid length"];
    for (int k = 0; k < 3; k++) {
        NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 50, 20) pullsDown:NO];
        [[popup cell] setControlSize:sizes[k]];
        NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:sizes[k]]];
        [popup setFont:font];
        [popup addItemsWithTitles:titles];
        CGFloat expected = ceil(width(@"Western (Mac OS Roman)", font) + extra[k]);
        for (NSInteger selected = 0; selected < 3; selected++) {
            [popup selectItemAtIndex:selected];
            CHECK([popup intrinsicContentSize].width == expected);
        }
    }
    // A pop-up with one short item is not smaller than that item needs.
    NSPopUpButton *single = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 50, 20) pullsDown:NO];
    [single addItemWithTitle:@"A"];
    CHECK([single intrinsicContentSize].width >= 32);
}

static void test_quirk_stepper_intrinsic_size(void) {
    NSControlSize sizes[3] = {NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini};
    NSSize expected[3] = {{19, 27}, {15, 22}, {13, 15}};
    for (int k = 0; k < 3; k++) {
        NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [[stepper cell] setControlSize:sizes[k]];
        NSSize intrinsic = [stepper intrinsicContentSize];
        NSEdgeInsets insets = [stepper alignmentRectInsets];
        CHECK(intrinsic.width + insets.left + insets.right == expected[k].width);
        CHECK(intrinsic.height + insets.top + insets.bottom == expected[k].height);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_popup_widest_item_width();
        test_quirk_stepper_intrinsic_size();
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
