// Copyright (C) 2026 Lubos Dolezel
//
// NSTabView looks like the Aqua tab view of macOS 10.14 in the light appearance: the tabs are one
// segmented strip centred over the content box and straddling its top edge; the box is a lightly
// tinted rounded rectangle; the selected tab is blue in an active window; the labels are regular weight.
// The sample points were taken from renders of a 320x160 tab view with three tabs on Mac OS X 10.14.4
// (black-box observation; QUIRK-tagged drawing in NSGraphicsStyle (NSTabViewAqua) and NSTabView).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// a window and application that report themselves as the active ones so that the active look is drawn without a user
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

static NSBitmapImageRep *snapshot(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    return rep;
}

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

// first and last coordinate of fully opaque pixels in a row (vertical == 0) or a column
static void opaqueSpan(NSBitmapImageRep *rep, int fixed, int vertical, int *first, int *last) {
    int n = vertical ? (int) [rep pixelsHigh] : (int) [rep pixelsWide];
    *first = *last = -1;
    for (int i = 0; i < n; i++) {
        int c[4];
        rgba(rep, vertical ? fixed : i, vertical ? i : fixed, c);
        if (c[3] == 255) {
            if (*first < 0)
                *first = i;
            *last = i;
        }
    }
}

static NSTabView *makeTabView(NSWindow *window, NSControlSize size, NSArray *labels, NSInteger selected) {
    NSTabView *tabView = [[NSTabView alloc] initWithFrame: NSMakeRect(0, 0, 320, 160)];
    [[window contentView] addSubview: tabView];
    [tabView setControlSize: size];
    for (NSString *label in labels) {
        NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier: label];
        [item setLabel: label];
        [tabView addTabViewItem: item];
    }
    [tabView selectTabViewItemAtIndex: selected];
    return tabView;
}

int main(void)
{
    @autoreleasepool {
        [ActiveApp sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSWindow *window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 160)
                                                            styleMask: NSWindowStyleMaskTitled
                                                              backing: NSBackingStoreBuffered
                                                                defer: NO];
        [window makeKeyAndOrderFront: nil];
        NSArray *labels = @[ @"Archive Formats", @"Extraction", @"Advanced" ];
        NSTabView *tabView = makeTabView(window, NSControlSizeRegular, labels, 0);
        NSBitmapImageRep *rep = snapshot(tabView);
        int c[4];

        CHECK([rep pixelsWide] == 320 && [rep pixelsHigh] == 160);

        // the strip is centred and straddles the box's top edge (the view is flipped, y grows downward).
        // Mojave: opaque from x 15 to 304 at the middle of the strip, from y 7 to 25 at x 160.
        int first, last;
        opaqueSpan(rep, 16, 0, &first, &last);
        // (the width depends on the label font, so only the position range is pinned)
        CHECK(first >= 8 && first <= 17);
        CHECK(abs(first - (319 - last)) <= 1);
        opaqueSpan(rep, 160, 1, &first, &last);
        CHECK(abs(first - 7) <= 1 && abs(last - 25) <= 1);
        CHECK(first < 16 && last > 16);
        CHECK(NSEqualRects([tabView contentRect], NSMakeRect(10, 33, 300, 114)));

        // selected tab: blue, darker towards the bottom
        rgba(rep, 20, 8, c);
        CHECK(c[3] == 255 && c[2] > 220 && c[0] > 60 && c[0] < 160 && c[1] > 120);
        rgba(rep, 20, 24, c);
        CHECK(c[3] == 255 && c[2] > 220 && c[0] < 60 && c[1] < 130);
        // an unselected tab is white
        rgba(rep, 200, 9, c);
        CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245 && c[3] == 255);
        // outside the box and the strip nothing is drawn; inside the box the tint is about 4% black
        rgba(rep, 3, 100, c);
        CHECK(c[3] == 0);
        rgba(rep, 20, 100, c);
        CHECK(c[3] >= 6 && c[3] <= 16 && c[0] < 20);
        rgba(rep, 160, 4, c);
        CHECK(c[3] == 0);
        // the box spans 7 points from each side and stops 10 points above the bottom
        rgba(rep, 6, 100, c);
        CHECK(c[3] < 5);
        rgba(rep, 7, 100, c);
        CHECK(c[3] > 10);
        rgba(rep, 160, 148, c);
        CHECK(c[3] >= 6);
        rgba(rep, 160, 155, c);
        CHECK(c[3] == 0);

        // the selected tab is the one in the second position after selecting it: the first is white and
        // the second blue (it starts at x 137 in Mojave)
        [tabView selectTabViewItemAtIndex: 1];
        rep = snapshot(tabView);
        rgba(rep, 20, 9, c);
        CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245);
        rgba(rep, 143, 9, c);
        CHECK(c[2] > 220 && c[0] < 160);
        [tabView removeFromSuperview];

        // control sizes: strip height and box top follow the size (view y of the strip's top edge)
        static const struct { NSControlSize size; int top, bottom; } sizes[] = {
            { NSControlSizeSmall, 5, 20 }, { NSControlSizeMini, 3, 15 }
        };
        for (int i = 0; i < 2; i++) {
            tabView = makeTabView(window, sizes[i].size, @[ @"One", @"Two", @"Three" ], 0);
            rep = snapshot(tabView);
            opaqueSpan(rep, 160, 1, &first, &last);
            CHECK(abs(first - sizes[i].top) <= 1 && abs(last - sizes[i].bottom) <= 1);
            [tabView removeFromSuperview];
        }
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
