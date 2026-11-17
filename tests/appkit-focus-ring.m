// Copyright (C) 2026 Lubos Dolezel
//
// Keyboard focus rings. A control that has the keyboard focus in the key window is surrounded by the soft blue Aqua
// ring instead of a dotted or black frame; NSFocusRingTypeNone draws nothing; NSSetFocusRingStyle makes the next
// fill or stroke draw a ring around its shape. Expected values were read and sampled on Mac OS X 10.14.4 (blue
// control tint, 1x): +[NSColor keyboardFocusIndicatorColor], the -focusRingMaskBounds of a focused text field and of
// the other views, and the pixels around a focused rounded push button rendered with -cacheDisplayInRect:. The
// pieces that Mojave does not show in such a render (the ring of a text field or of a custom view that draws a
// focus ring mask, and NSSetFocusRingStyle into a bitmap) run on Darling only.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

// declared by the SDK of macOS; the SDK headers of the source tree used to cross-compile guest tests lack them
@interface NSCell (FocusRingMask)
- (NSRect)focusRingMaskBoundsForFrame:(NSRect)cellFrame inView:(NSView *)controlView;
@end
extern void NSSetFocusRingStyle(NSFocusRingPlacement placement);

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The probe window and application report themselves active, so that a session without a user at the console
// (a window that is not frontmost) still draws the focused look.
@interface ActiveWindow : NSWindow
@end
@implementation ActiveWindow
- (BOOL)isKeyWindow { return YES; }
- (BOOL)isMainWindow { return YES; }
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface ActiveApp : NSApplication
@end
@implementation ActiveApp
- (BOOL)isActive { return YES; }
@end

// A custom view that draws a focus ring mask: its bounds, as documented for -drawFocusRingMask.
@interface MaskView : NSView
@end
@implementation MaskView
- (BOOL)acceptsFirstResponder { return YES; }
- (NSRect)focusRingMaskBounds { return [self bounds]; }
- (void)drawFocusRingMask { NSRectFill([self bounds]); }
- (void)drawRect:(NSRect)r { [[NSColor whiteColor] set]; NSRectFill([self bounds]); }
@end

static BOOL onDarling(void) { return access("/Volumes/SystemRoot", F_OK) == 0; }

static void spin(void) {
    for (int i = 0; i < 8; i++)
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
}

static NSBitmapImageRep *render(NSView *view) {
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

// the ring colour at full strength is (62, 150, 253): a pixel of the ring is blue-ish and, over a transparent
// background, carries the ring's alpha
static BOOL ringPixel(NSBitmapImageRep *rep, int x, int y, int minAlpha, int maxAlpha) {
    int c[4];

    rgba(rep, x, y, c);
    BOOL ring = c[3] >= minAlpha && c[3] <= maxAlpha && c[2] > 200 && c[0] < 100 && c[1] > 110 && c[1] < 190;

    if (!ring)
        fprintf(stderr, "  pixel (%d, %d) is (%d, %d, %d, %d)\n", x, y, c[0], c[1], c[2], c[3]);
    return ring;
}

static int alphaAt(NSBitmapImageRep *rep, int x, int y) {
    int c[4];

    rgba(rep, x, y, c);
    return c[3];
}

// the number of pixels of the rectangle that are dark and opaque: a black or dotted frame
static int darkPixels(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1) {
    int n = 0, c[4];

    for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++) {
            rgba(rep, x, y, c);
            n += c[3] > 100 && c[0] < 90 && c[1] < 90 && c[2] < 90;
        }
    return n;
}

// the mask of a cell, or an empty one where the cell has no such method (the check then reports the later failures
// instead of ending the run)
static NSRect cellMask(NSCell *cell, NSView *view) {
    if (![cell respondsToSelector: @selector(focusRingMaskBoundsForFrame:inView:)])
        return NSZeroRect;
    return [cell focusRingMaskBoundsForFrame: [view bounds] inView: view];
}

static BOOL rectEq(NSRect a, NSRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.01 && fabs(a.origin.y - b.origin.y) < 0.01 &&
           fabs(a.size.width - b.size.width) < 0.01 && fabs(a.size.height - b.size.height) < 0.01;
}

int main(void)
{
    @autoreleasepool {
        [ActiveApp sharedApplication];

        // test_quirk_keyboard_focus_indicator_color: the colour is a translucent blue (Mojave, blue tint)
        NSColor *indicator = [[NSColor keyboardFocusIndicatorColor] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
        CHECK(fabs([indicator redComponent] - 0.0) < 0.02);
        CHECK(fabs([indicator greenComponent] - 0.4039) < 0.02);
        CHECK(fabs([indicator blueComponent] - 0.9569) < 0.02);
        CHECK(fabs([indicator alphaComponent] - 0.2471) < 0.02);

        // the documented types: the default is the exterior ring; a new view and cell have the default type
        CHECK([NSView defaultFocusRingType] == NSFocusRingTypeExterior);
        CHECK([NSCell defaultFocusRingType] == NSFocusRingTypeExterior);
        CHECK(NSFocusRingTypeDefault == 0 && NSFocusRingTypeNone == 1 && NSFocusRingTypeExterior == 2);

        NSWindow *window = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(200, 200, 260, 140)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
        NSView *content = [window contentView];
        int H = (int) NSHeight([content bounds]);
        NSTextField *field = [[NSTextField alloc] initWithFrame: NSMakeRect(30, 90, 140, 22)];
        [field setStringValue: @"Text"];
        [content addSubview: field];
        NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(30, 40, 100, 32)];
        [button setTitle: @""];
        [button setBezelStyle: NSBezelStyleRounded];
        [content addSubview: button];
        MaskView *maskView = [[MaskView alloc] initWithFrame: NSMakeRect(180, 40, 60, 40)];
        [content addSubview: maskView];
        NSView *plain = [[NSView alloc] initWithFrame: NSMakeRect(180, 100, 40, 20)];
        [content addSubview: plain];
        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        spin();

        CHECK([field focusRingType] == NSFocusRingTypeDefault);
        CHECK([button focusRingType] == NSFocusRingTypeDefault);
        [button setFocusRingType: NSFocusRingTypeNone];
        CHECK([button focusRingType] == NSFocusRingTypeNone);
        [button setFocusRingType: NSFocusRingTypeDefault];

        // focusRingMaskBounds: nothing for a view without a focus, a view that draws no mask, and the cells; a text
        // field reports its bounds while it is being edited, whatever its ring type
        [window makeFirstResponder: content];
        CHECK(NSIsEmptyRect([field focusRingMaskBounds]));
        CHECK(NSIsEmptyRect([plain focusRingMaskBounds]));
        CHECK(NSIsEmptyRect(cellMask([field cell], field)));
        CHECK(NSIsEmptyRect(cellMask([button cell], button)));
        [window makeFirstResponder: field];
        spin();
        CHECK(rectEq([field focusRingMaskBounds], NSMakeRect(0, 0, 140, 22)));
        CHECK(NSIsEmptyRect([plain focusRingMaskBounds]));
        CHECK(NSIsEmptyRect([button focusRingMaskBounds]));
        CHECK(NSIsEmptyRect(cellMask([field cell], field)));
        [field setFocusRingType: NSFocusRingTypeNone];
        CHECK(rectEq([field focusRingMaskBounds], NSMakeRect(0, 0, 140, 22)));
        [field setFocusRingType: NSFocusRingTypeDefault];
        [window makeFirstResponder: maskView];
        CHECK(rectEq([maskView focusRingMaskBounds], NSMakeRect(0, 0, 60, 40)));

        // a focused push button: the ring runs along the bezel, 1 point of it at about half strength just outside the
        // edge and a faint point beyond; an unfocused one and one of type none have none
        // (the first of the pieces below that runs on Mojave and Darling alike)
        // the bezel's edge is the first drawn pixel of the unfocused button, from the left on the middle row and from
        // the top on a column through the middle (Darling and Mojave place the bezel differently in the frame)
        [window makeFirstResponder: content];
        spin();
        NSBitmapImageRep *rep = render(content);
        int midY = H - (int) NSMidY([button frame]), edgeX = -1, edgeTop = -1;
        for (int x = 0; x < 50 && edgeX < 0; x++)
            if (alphaAt(rep, x, midY) > 0)
                edgeX = x;
        for (int y = 0; y < H && edgeTop < 0; y++)
            if (alphaAt(rep, 80, y) > 0 && y > H - 80)
                edgeTop = y;
        CHECK(edgeX >= 28 && edgeX <= 40 && edgeTop >= H - 76 && edgeTop <= H - 64);
        for (int d = 1; d <= 3; d++) {
            CHECK(alphaAt(rep, edgeX - d, midY) == 0);
            CHECK(alphaAt(rep, 80, edgeTop - d) == 0);
        }

        [window makeFirstResponder: button];
        spin();
        rep = render(content);
        // test_quirk_focus_ring_push_button_profile
        CHECK(ringPixel(rep, edgeX - 1, midY, 90, 160));
        CHECK(ringPixel(rep, 80, edgeTop - 1, 90, 160));
        CHECK(alphaAt(rep, edgeX - 2, midY) < 50);
        CHECK(alphaAt(rep, 80, edgeTop - 2) < 50);
        CHECK(alphaAt(rep, edgeX - 3, midY) == 0);
        CHECK(alphaAt(rep, 80, edgeTop - 3) == 0);
        // no dotted or black frame inside the bezel of the button without a title
        CHECK(darkPixels(rep, edgeX + 3, edgeTop + 4, edgeX + 80, edgeTop + 15) == 0);

        [button setFocusRingType: NSFocusRingTypeNone];
        [content setNeedsDisplay: YES];
        spin();
        rep = render(content);
        for (int d = 1; d <= 3; d++) {
            CHECK(alphaAt(rep, edgeX - d, midY) == 0);
            CHECK(alphaAt(rep, 80, edgeTop - d) == 0);
        }
        [button setFocusRingType: NSFocusRingTypeDefault];

        // the outline of a text field bezel is blended over the window: drawn over an opaque light gray it is a
        // darker gray, not black (a copy of the translucent black would show as solid black in a window)
        {
            NSBitmapImageRep *gray = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                             pixelsWide: 140
                                                                             pixelsHigh: 22
                                                                          bitsPerSample: 8
                                                                        samplesPerPixel: 4
                                                                               hasAlpha: YES
                                                                               isPlanar: NO
                                                                         colorSpaceName: NSCalibratedRGBColorSpace
                                                                            bytesPerRow: 0
                                                                           bitsPerPixel: 0];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: gray]];
            [[NSColor colorWithCalibratedWhite: 236 / 255.0 alpha: 1] set];
            NSRectFill(NSMakeRect(0, 0, 140, 22));
            [[field cell] drawWithFrame: NSMakeRect(0, 0, 140, 22) inView: field];
            [NSGraphicsContext restoreGraphicsState];
            int c[4];
            rgba(gray, 70, 0, c);
            CHECK(c[0] > 180 && c[0] < 200 && c[3] == 255);
            rgba(gray, 0, 11, c);
            CHECK(c[0] > 180 && c[0] < 200 && c[3] == 255);
        }

        // an unfocused text field has no ring, a focused one has the blue ring outside its bezel and no black
        // frame; these renders do not show the ring on Mojave
        [window makeFirstResponder: field];
        spin();
        int fieldTop = H - 112, fieldMid = fieldTop + 11;
        rep = render(content);
        CHECK(darkPixels(rep, 20, fieldTop - 8, 29, fieldTop + 30) == 0);
        if (onDarling()) {
            CHECK(ringPixel(rep, 29, fieldMid, 90, 160));
            CHECK(ringPixel(rep, 100, fieldTop - 1, 90, 160));
            CHECK(ringPixel(rep, 170, fieldMid, 90, 160));
            CHECK(ringPixel(rep, 100, fieldTop + 22, 90, 160));
            CHECK(alphaAt(rep, 28, fieldMid) < 50);
            CHECK(alphaAt(rep, 27, fieldMid) == 0);

            // no ring when the type is none, and none for an unfocused field
            [field setFocusRingType: NSFocusRingTypeNone];
            [content setNeedsDisplay: YES];
            spin();
            rep = render(content);
            CHECK(alphaAt(rep, 29, fieldMid) == 0);
            CHECK(alphaAt(rep, 100, fieldTop - 1) == 0);
            [field setFocusRingType: NSFocusRingTypeDefault];
            [window makeFirstResponder: content];
            spin();
            rep = render(content);
            CHECK(alphaAt(rep, 29, fieldMid) == 0);
            CHECK(alphaAt(rep, 100, fieldTop - 1) == 0);

            // moving the focus away erases the ring from the window, not only from the next full redraw: the
            // views are redrawn with the invalidation of the focus change alone
            [window makeFirstResponder: field];
            [window displayIfNeeded];
            [window makeFirstResponder: content];
            [window displayIfNeeded];
            rep = render(content);
            CHECK(alphaAt(rep, 29, fieldMid) == 0);

            // a view that draws a focus ring mask gets a ring outside its bounds, drawn in its superview
            [window makeFirstResponder: maskView];
            spin();
            rep = render(content);
            int maskTop = H - 80, maskMid = maskTop + 20;
            CHECK(ringPixel(rep, 179, maskMid, 90, 160));
            CHECK(ringPixel(rep, 240, maskMid, 90, 160));
            CHECK(ringPixel(rep, 200, maskTop - 1, 90, 160));
            CHECK(ringPixel(rep, 200, maskTop + 40, 90, 160));
            CHECK(alphaAt(rep, 177, maskMid) == 0);

            // NSSetFocusRingStyle(NSFocusRingOnly) draws only the ring: around the rectangle, nothing in it
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                               pixelsWide: 60
                                                                               pixelsHigh: 40
                                                                            bitsPerSample: 8
                                                                          samplesPerPixel: 4
                                                                                 hasAlpha: YES
                                                                                 isPlanar: NO
                                                                           colorSpaceName: NSCalibratedRGBColorSpace
                                                                              bytesPerRow: 0
                                                                             bitsPerPixel: 0];
            for (int placement = 0; placement < 3; placement++) {
                [NSGraphicsContext saveGraphicsState];
                [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: bitmap]];
                [[NSColor clearColor] set];
                NSRectFillUsingOperation(NSMakeRect(0, 0, 60, 40), NSCompositeClear);
                [[NSColor redColor] set];
                [NSGraphicsContext saveGraphicsState];
                NSSetFocusRingStyle(placement);
                NSRectFill(NSMakeRect(10, 10, 40, 20));
                [NSGraphicsContext restoreGraphicsState];
                [NSGraphicsContext restoreGraphicsState];
                // bitmap row 0 is the top: the rectangle covers x 10..49, rows 10..29
                CHECK(ringPixel(bitmap, 9, 20, 90, 160));
                CHECK(ringPixel(bitmap, 30, 9, 90, 160));
                int c[4];
                rgba(bitmap, 30, 20, c);
                if (placement == NSFocusRingOnly)
                    CHECK(c[3] == 0);
                else
                    CHECK(c[0] > 250 && c[1] < 5 && c[3] == 255);
                // the style is restored with the graphics state: the next fill draws no ring
                [NSGraphicsContext saveGraphicsState];
                [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: bitmap]];
                NSRectFillUsingOperation(NSMakeRect(0, 0, 60, 40), NSCompositeClear);
                [[NSColor redColor] set];
                NSRectFill(NSMakeRect(10, 10, 40, 20));
                [NSGraphicsContext restoreGraphicsState];
                CHECK(alphaAt(bitmap, 9, 20) == 0);
            }
        }
        [window orderOut: nil];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
