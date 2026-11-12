/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A new slider has the documented defaults (minimum 0, maximum 1, value 0), and
// laying out its knob with an empty range does not produce NaN. No window is
// shown.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSSlider *slider = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, 120, 24)];
        expect([slider minValue] == 0.0, "NSSlider minValue defaults to 0");
        expect([slider maxValue] == 1.0, "NSSlider maxValue defaults to 1");
        expect([slider doubleValue] == 0.0, "NSSlider value defaults to 0");

        NSSliderCell *cell = [[NSSliderCell alloc] init];
        expect([cell minValue] == 0.0 && [cell maxValue] == 1.0, "NSSliderCell defaults to 0...1");
        [cell release];

        // An empty range puts the knob at the start rather than at NaN.
        [slider setMinValue: 5];
        [slider setMaxValue: 5];
        [slider setDoubleValue: 5];
        NSRect knob = [[slider cell] knobRectFlipped: NO];
        expect(!isnan(knob.origin.x) && !isnan(knob.origin.y) && !isinf(knob.origin.x),
               "the knob rect is finite for an empty range");
        [slider release];
    }
    printf("slider default values: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
