// Copyright (C) 2026 Lubos Dolezel
//
// -testPart: finds the part of an enabled scroller under a point, as documented: the knob, the page areas
// before and after it, and NSScrollerNoPart outside the scroller. Vertical and horizontal scrollers. The
// vertical page areas are not pinned to a particular part: macOS 26.7.3 reports them the other way round
// for a scroller outside a window, and macOS leaves -hitPart alone, which is only for mouse tracking.
// Build: clang -framework AppKit appkit-scroller-hit-test.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSPoint center(NSRect r) {
    return NSMakePoint(NSMidX(r), NSMidY(r));
}

static void check_parts(NSScroller *s, BOOL exactPages) {
    NSRect knob = [s rectForPart: NSScrollerKnob];
    NSRect before = [s rectForPart: NSScrollerDecrementPage];
    NSRect after = [s rectForPart: NSScrollerIncrementPage];
    CHECK([s testPart: center(knob)] == NSScrollerKnob);
    // The page areas are found; which of the two is which follows the scroller's orientation.
    NSScrollerPart p1 = [s testPart: center(before)], p2 = [s testPart: center(after)];
    CHECK((p1 == NSScrollerDecrementPage || p1 == NSScrollerIncrementPage));
    CHECK((p2 == NSScrollerDecrementPage || p2 == NSScrollerIncrementPage));
    CHECK(p1 != p2);
    if (exactPages) {
        CHECK(p1 == NSScrollerDecrementPage);
        CHECK(p2 == NSScrollerIncrementPage);
    }
    CHECK([s testPart: NSMakePoint(-5, -5)] == NSScrollerNoPart);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSScroller *v = [[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 200)];
        [v setEnabled: YES];
        [v setKnobProportion: 0.3];
        [v setDoubleValue: 0.5];
        NSRect knob = [v rectForPart: NSScrollerKnob];
        CHECK(!NSIsEmptyRect(knob));
        CHECK(!NSIsEmptyRect([v rectForPart: NSScrollerDecrementPage]));
        CHECK(!NSIsEmptyRect([v rectForPart: NSScrollerIncrementPage]));
        check_parts(v, NO);

        NSScroller *h = [[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 200, 15)];
        [h setEnabled: YES];
        [h setKnobProportion: 0.3];
        [h setDoubleValue: 0.5];
        check_parts(h, YES);
    }
    puts(failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
