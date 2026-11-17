// Copyright (C) 2026 Lubos Dolezel
//
// -[NSView init] initialises the view with a zero frame (it is -initWithFrame: with NSZeroRect), and so
// zero bounds. A view created that way and later given contents takes its size from them; a leftover 1 x 1
// frame is wrong because code that tests for an unset size sees a size.
// Checked on macOS 10.14.4 and 26.7.3.
//
// Build: clang -fobjc-arc -framework AppKit appkit-view-init-zero-frame.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface PlainSubclass : NSView
@end
@implementation PlainSubclass
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSView *view = [[NSView alloc] init];
        CHECK(NSEqualRects([view frame], NSZeroRect));
        CHECK(NSEqualRects([view bounds], NSZeroRect));

        NSView *subclass = [[PlainSubclass alloc] init];
        CHECK(NSEqualRects([subclass frame], NSZeroRect));

        // initWithFrame: still takes the frame it is given
        NSView *framed = [[NSView alloc] initWithFrame: NSMakeRect(1, 2, 3, 4)];
        CHECK(NSEqualRects([framed frame], NSMakeRect(1, 2, 3, 4)));

        [view setFrameSize: NSMakeSize(445, 32)];
        CHECK(NSEqualSizes([view frame].size, NSMakeSize(445, 32)));
        CHECK(NSEqualSizes([view bounds].size, NSMakeSize(445, 32)));
    }
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
