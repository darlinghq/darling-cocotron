// Copyright (C) 2026 Lubos Dolezel
//
// A segmented control whose segments are wider together than the control frame still shows the whole strip:
// the segments shrink to fit instead of the last one being cut off at the right edge of the frame, so the
// rounded right end of the strip is drawn inside the frame. Documented contract: a control draws within its bounds.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface ActiveWindow : NSWindow
@end
@implementation ActiveWindow
- (BOOL) isKeyWindow { return YES; }
- (BOOL) isMainWindow { return YES; }
@end

static int alphaAt(NSBitmapImageRep *rep, int x, int y) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    return (int) lround([color alphaComponent] * 255);
}

static NSBitmapImageRep *render(CGFloat width, NSWindow *window) {
    NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, width, 24)];
    [control setSegmentCount: 3];
    [control setSegmentStyle: NSSegmentStyleRounded];
    [control setLabel: @"Overview" forSegment: 0];
    [control setLabel: @"Details" forSegment: 1];
    [control setLabel: @"Settings" forSegment: 2];
    [control setTrackingMode: NSSegmentSwitchTrackingSelectOne];
    [control setSelectedSegment: 0];
    [[window contentView] addSubview: control];
    [control setFrame: NSMakeRect(0, 0, width, 24)];
    NSBitmapImageRep *rep = [control bitmapImageRepForCachingDisplayInRect: [control bounds]];
    [control cacheDisplayInRect: [control bounds] toBitmapImageRep: rep];
    return rep;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 100)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
        [window makeKeyAndOrderFront: nil];

        NSBitmapImageRep *wideRep = render(300, window);
        NSBitmapImageRep *rep = render(70, window);
        int w = (int) [rep pixelsWide], h = (int) [rep pixelsHigh];
        int ww = (int) [wideRep pixelsWide];
        // rows of the strip in a column inside the first segment
        int top = -1, bottom = -1;
        for (int y = 0; y < h; y++) {
            if (alphaAt(rep, 10, y) > 0 && top < 0)
                top = y;
            if (alphaAt(rep, 10, y) == 255)
                bottom = y;
        }
        CHECK(top >= 0 && bottom > top);
        int mid = (top + bottom) / 2;
        // the strip reaches the right edge of the frame at its middle row ...
        CHECK(alphaAt(rep, w - 2, mid) == 255);
        // ... and ends there with its rounded corner, instead of continuing past the frame cut off
        CHECK(alphaAt(rep, w - 1, top + 1) < 200);
        CHECK(alphaAt(rep, w - 1, bottom - 1) < 200);
        // a wide frame is not stretched: the strip stops short of its right edge
        CHECK(alphaAt(wideRep, ww - 2, mid) == 0);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
