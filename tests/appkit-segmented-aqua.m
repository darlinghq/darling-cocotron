// Copyright (C) 2026 Lubos Dolezel
//
// A rounded segmented control looks like the Aqua one of macOS 10.14 in the light appearance: one white
// rounded strip (20 points high at the regular size), a blue selected segment with a white label in an active
// window, light dividers elsewhere. Expected values were sampled from renders of a three segment control
// (One, Two, Three; the second selected) on Mac OS X 10.14.4 (black-box observation; QUIRK-tagged drawing in
// NSSegmentedCell and NSGraphicsStyle (NSTabViewAqua)).
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
@interface ActiveApp : NSApplication
@end
@implementation ActiveApp
- (BOOL) isActive { return YES; }
@end

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

int main(void)
{
    @autoreleasepool {
        [ActiveApp sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSWindow *window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 100)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
        [window makeKeyAndOrderFront: nil];
        NSSegmentedControl *control = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 200, 24)];
        [control setSegmentCount: 3];
        [control setSegmentStyle: NSSegmentStyleRounded];
        [control setLabel: @"One" forSegment: 0];
        [control setLabel: @"Two" forSegment: 1];
        [control setLabel: @"Three" forSegment: 2];
        [control setTrackingMode: NSSegmentSwitchTrackingSelectOne];
        [control setSelectedSegment: 1];
        [[window contentView] addSubview: control];
        [control sizeToFit];
        NSRect frame = [control frame];
        // the Mojave control is 162 points wide for these labels; fonts differ, so only a range is pinned
        CHECK(frame.size.width > 100 && frame.size.width < 200);
        NSBitmapImageRep *rep = [control bitmapImageRepForCachingDisplayInRect: [control bounds]];
        [control cacheDisplayInRect: [control bounds] toBitmapImageRep: rep];
        int w = (int) [rep pixelsWide], h = (int) [rep pixelsHigh], c[4];

        // the strip is 20 points high with its top edge row translucent and white inside; find its rows in a
        // column of the first segment
        int top = -1, bottom = -1;
        for (int y = 0; y < h; y++) {
            rgba(rep, 10, y, c);
            if (c[3] > 0 && top < 0)
                top = y;
            if (c[3] == 255)
                bottom = y;
        }
        CHECK(top >= 0 && bottom - top >= 17 && bottom - top <= 20);
        rgba(rep, 10, top + 4, c);
        CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245 && c[3] == 255);
        // the selected (second) segment is blue in the middle of the strip: find it by scanning the row
        int blueFirst = -1, blueLast = -1;
        for (int x = 0; x < w; x++) {
            rgba(rep, x, top + 2, c);
            if (c[2] > 230 && c[0] < 140 && c[3] == 255) {
                if (blueFirst < 0)
                    blueFirst = x;
                blueLast = x;
            }
        }
        CHECK(blueFirst > 30 && blueFirst < 70);
        CHECK(blueLast - blueFirst > 35 && blueLast - blueFirst < 75);
        // blue gets darker towards the bottom
        rgba(rep, blueFirst + 3, top + 2, c);
        int upper = c[0];
        rgba(rep, blueFirst + 3, bottom - 2, c);
        CHECK(c[0] < upper && c[2] > 230);
        // the last segment is white again, and a divider separates it from the selected one only if they
        // do not touch (they do), so no gray line there
        rgba(rep, MIN(blueLast + 6, w - 3), top + 2, c);
        CHECK(c[0] > 200 && c[3] == 255);
        // outside the strip's vertical extent nothing but its shadow
        rgba(rep, 20, 0, c);
        CHECK(top == 0 || c[3] < 40);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
