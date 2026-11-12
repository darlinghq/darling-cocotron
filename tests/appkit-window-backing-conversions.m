/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSWindow's backing conversions scale by -backingScaleFactor and are
// inverses of each other, for rects, points and sizes. No window is shown.
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
        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(0, 0, 100, 80)
                          styleMask: NSWindowStyleMaskTitled
                            backing: NSBackingStoreBuffered
                              defer: YES];
        CGFloat scale = [window backingScaleFactor];
        expect(scale >= 1.0, "backingScaleFactor is at least 1");

        NSRect rect = NSMakeRect(3, 5, 20, 40);
        NSRect backing = [window convertRectToBacking: rect];
        expect(fabs(backing.origin.x - 3 * scale) < 1e-9 &&
               fabs(backing.origin.y - 5 * scale) < 1e-9 &&
               fabs(backing.size.width - 20 * scale) < 1e-9 &&
               fabs(backing.size.height - 40 * scale) < 1e-9,
               "convertRectToBacking scales origin and size");
        NSRect back = [window convertRectFromBacking: backing];
        expect(fabs(back.origin.x - 3) < 1e-9 && fabs(back.origin.y - 5) < 1e-9 &&
               fabs(back.size.width - 20) < 1e-9 && fabs(back.size.height - 40) < 1e-9,
               "convertRectFromBacking inverts convertRectToBacking");

        NSPoint point = [window convertPointToBacking: NSMakePoint(7, 9)];
        expect(fabs(point.x - 7 * scale) < 1e-9 && fabs(point.y - 9 * scale) < 1e-9,
               "convertPointToBacking scales the point");
        point = [window convertPointFromBacking: point];
        expect(fabs(point.x - 7) < 1e-9 && fabs(point.y - 9) < 1e-9,
               "convertPointFromBacking inverts convertPointToBacking");

        NSSize size = [window convertSizeToBacking: NSMakeSize(11, 13)];
        expect(fabs(size.width - 11 * scale) < 1e-9 && fabs(size.height - 13 * scale) < 1e-9,
               "convertSizeToBacking scales the size");
        size = [window convertSizeFromBacking: size];
        expect(fabs(size.width - 11) < 1e-9 && fabs(size.height - 13) < 1e-9,
               "convertSizeFromBacking inverts convertSizeToBacking");

        // The size conversion does not move anything: the origin is not used.
        NSRect zero = [window convertRectToBacking: NSZeroRect];
        expect(NSEqualRects(zero, NSZeroRect), "the empty rect stays empty");
        [window release];
    }
    printf("window backing conversions: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
