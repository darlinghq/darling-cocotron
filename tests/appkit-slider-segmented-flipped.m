// Copyright (C) 2026 Lubos Dolezel
//
// NSSlider and NSSegmentedControl are flipped views on macOS 10.14.4 and 26.7.3, and a vertical slider
// still has its minimum, and its first tick mark, at the bottom.
//
// Build: clang -fobjc-arc -framework AppKit appkit-slider-segmented-flipped.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        NSRect frame = NSMakeRect(10, 10, 200, 26);
        NSSlider *slider = [[NSSlider alloc] initWithFrame:frame];
        CHECK([slider isFlipped]);
        CHECK([[[NSSegmentedControl alloc] initWithFrame:frame] isFlipped]);

        // A vertical slider has its minimum at the bottom: the knob is further down (larger y in this flipped
        // view) at the minimum than at the maximum.
        NSSlider *vertical = [[NSSlider alloc] initWithFrame:NSMakeRect(10, 10, 26, 200)];
        [vertical setMinValue:0]; [vertical setMaxValue:10];
        [[window contentView] addSubview:vertical];
        [vertical setDoubleValue:0];
        [vertical display];
        CGFloat atMin = [[vertical cell] knobRectFlipped:YES].origin.y;
        [vertical setDoubleValue:10];
        CGFloat atMax = [[vertical cell] knobRectFlipped:YES].origin.y;
        CHECK(atMin > atMax);

        // The first tick mark of a vertical slider is at the bottom too.
        NSSlider *ticks = [[NSSlider alloc] initWithFrame:NSMakeRect(40, 10, 40, 200)];
        [ticks setMinValue:0]; [ticks setMaxValue:10]; [ticks setNumberOfTickMarks:3];
        [[window contentView] addSubview:ticks];
        [ticks display];
        CHECK([(NSSliderCell *)[ticks cell] rectOfTickMarkAtIndex:0].origin.y > [(NSSliderCell *)[ticks cell] rectOfTickMarkAtIndex:2].origin.y);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
