// Copyright (C) 2026 Lubos Dolezel
//
// Pop-up and pull-down buttons look like the Aqua ones of macOS 10.14 in the light appearance: a white
// bezel with a blue end cap on the right in an active window, holding white chevrons; a disabled button
// is fainter and has no blue. Expected values were sampled from renders of 120 point wide buttons on
// Mac OS X 10.14.4 (black-box observation; QUIRK-tagged drawing in NSGraphicsStyle (NSPopUpButtonAqua)).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static BOOL gActive = YES;

@interface ActiveWindow : NSWindow
@end
@implementation ActiveWindow
- (BOOL) isKeyWindow { return gActive; }
- (BOOL) isMainWindow { return gActive; }
@end

@interface ActiveApp : NSApplication
@end
@implementation ActiveApp
- (BOOL) isActive { return gActive; }
@end

static NSWindow *window;

static NSBitmapImageRep *render(BOOL pullsDown, NSControlSize size, BOOL enabled, BOOL pressed) {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 120, 26) pullsDown: pullsDown];
    [[window contentView] addSubview: popup];
    if (pullsDown)
        [popup addItemWithTitle: @"Action"];
    [popup addItemsWithTitles: @[ @"First", @"Second" ]];
    [[popup cell] setControlSize: size];
    [popup setFont: [NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: size]]];
    [popup sizeToFit];
    [popup setFrameSize: NSMakeSize(120, [popup frame].size.height)];
    [popup setEnabled: enabled];
    [[popup cell] setHighlighted: pressed];
    NSBitmapImageRep *rep = [popup bitmapImageRepForCachingDisplayInRect: [popup bounds]];
    [popup cacheDisplayInRect: [popup bounds] toBitmapImageRep: rep];
    [popup removeFromSuperview];
    return rep;
}

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

// the bezel's right edge in the middle row, and the middle row (first and last row with alpha >= 128
// in a column left of the cap)
static void bezelExtent(NSBitmapImageRep *rep, int *right, int *midRow) {
    int c[4], top = -1, bottom = -1;
    *right = -1;
    for (int y = 0; y < (int) [rep pixelsHigh]; y++) {
        rgba(rep, 30, y, c);
        if (c[3] >= 128) {
            if (top < 0)
                top = y;
            bottom = y;
        }
    }
    *midRow = (top + bottom) / 2;
    for (int x = 0; x < (int) [rep pixelsWide]; x++) {
        rgba(rep, x, *midRow, c);
        if (c[3] >= 128)
            *right = x;
    }
}

int main(void)
{
    @autoreleasepool {
        [ActiveApp sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
        [window makeKeyAndOrderFront: nil];
        int c[4], right, mid;

        // a new pop-up button has the rounded bezel style
        CHECK([[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 26) pullsDown: NO] bezelStyle] == NSBezelStyleRounded);

        for (int pullsDown = 0; pullsDown < 2; pullsDown++) {
            NSBitmapImageRep *rep = render(pullsDown, NSControlSizeRegular, YES, NO);
            bezelExtent(rep, &right, &mid);
            CHECK(right > 100 && right < 120);
            // the cap: blue, with the gradient of a default push button (darker lower down)
            rgba(rep, right - 3, mid, c);
            CHECK(c[3] == 255 && c[2] > 220 && c[0] < 110 && c[1] > 90 && c[1] < 170);
            rgba(rep, right - 4, mid - 7, c);
            CHECK(c[3] == 255 && c[2] > 230 && c[0] > 40 && c[0] < 130);
            rgba(rep, right - 4, mid + 7, c);
            CHECK(c[3] == 255 && c[2] > 230 && c[0] < 40);
            // the body left of the cap is white, and the cap starts 16 points from the right edge
            rgba(rep, right - 20, mid - 6, c);
            CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245 && c[3] == 255);
            rgba(rep, right - 17, mid - 6, c);
            CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245);
            rgba(rep, right - 14, mid - 6, c);
            CHECK(c[0] < 120);

            // disabled: no blue, half strength
            rep = render(pullsDown, NSControlSizeRegular, NO, NO);
            bezelExtent(rep, &right, &mid);
            rgba(rep, right - 3, mid, c);
            CHECK(c[3] > 90 && c[3] < 200 && c[2] > 240);
        }

        // in a window that is not active the cap is white too (observed on Mac OS X 10.14.4)
        gActive = NO;
        NSWindow *activeWindow = window;
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        NSBitmapImageRep *inactive = render(NO, NSControlSizeRegular, YES, NO);
        bezelExtent(inactive, &right, &mid);
        rgba(inactive, right - 3, mid, c);
        CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245 && c[3] == 255);
        gActive = YES;
        window = activeWindow;

        // control sizes: the cap is 14 and 12 points wide
        NSBitmapImageRep *rep = render(NO, NSControlSizeSmall, YES, NO);
        bezelExtent(rep, &right, &mid);
        rgba(rep, right - 12, mid - 5, c);
        CHECK(c[0] < 130 && c[2] > 220);
        rgba(rep, right - 16, mid - 5, c);
        CHECK(c[0] > 240);
        rep = render(NO, NSControlSizeMini, YES, NO);
        bezelExtent(rep, &right, &mid);
        rgba(rep, right - 10, mid - 4, c);
        CHECK(c[0] < 130 && c[2] > 220);
        rgba(rep, right - 14, mid - 4, c);
        CHECK(c[0] > 240);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
