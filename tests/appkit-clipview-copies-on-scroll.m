// Copyright (C) 2026 Lubos Dolezel
//
// With -copiesOnScroll set (the default), an NSClipView that scrolls by whole points keeps the pixels that stay
// visible and has the document view draw only the newly exposed strip; with it off the whole visible area is
// drawn again. Both ways the window shows the document as it is at the new scroll position. The document draws a
// grey level that depends on the row, so a wrongly moved or stale pixel shows. The test prints the drawn area
// per scroll step and the time of 300 steps for both settings, and checks that:
//  - the window's pixels match the document after scrolling by +40, -25, +7 and (with the content view's scroller
//    page moves) a whole page, in both settings;
//  - with copiesOnScroll the area drawn for a 40 point step is at most 40 rows of the visible width (plus a
//    pixel row); without it the area is only printed (a layer-backed macOS view draws none of it);
//  - after a fractional scroll position (the copy is not used) a whole one shows the right pixels again.
// Needs a window server. The window's pixels are read from its backing bitmap, which only a Darling window
// has; on macOS the pixel checks are skipped and only the drawn areas are printed and checked.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static int failures;
static double drawnArea;
static int drawCalls;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

static int levelAtRow(int y) { return (y * 37) % 200 + 20; }

@interface Doc : NSView
@end
@implementation Doc
- (BOOL) isFlipped { return YES; }
- (BOOL) isOpaque { return YES; }
- (void) drawRect: (NSRect) rect
{
    drawCalls++;
    drawnArea += rect.size.width * rect.size.height;
    for (int y = (int) floor(NSMinY(rect)); y < (int) ceil(NSMaxY(rect)); y++) {
        CGFloat g = levelAtRow(y) / 255.0;
        [[NSColor colorWithCalibratedRed: g green: g blue: g alpha: 1] setFill];
        NSRectFill(NSMakeRect(NSMinX(rect), y, NSWidth(rect), 1));
    }
}
@end

static void spin(double seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: until inMode: NSDefaultRunLoopMode dequeue: YES];
        if (e != nil)
            [NSApp sendEvent: e];
    }
}

// The number of visible rows whose pixels (window backing, at the clip view's left edge + 20) differ from
// what the document draws there.
static int wrongRows(NSWindow *window, NSClipView *clip, NSView *doc)
{
    CGContextRef port = (CGContextRef) [[window graphicsContext] graphicsPort];
    unsigned char *data = CGBitmapContextGetData(port);
    if (data == NULL)
        return 0; // no bitmap to read (macOS): only the drawn area is checked
    size_t bpr = CGBitmapContextGetBytesPerRow(port);
    size_t height = CGBitmapContextGetHeight(port);
    NSRect clipInWindow = [clip convertRect: [clip bounds] toView: nil];
    NSRect visible = [clip documentVisibleRect];
    int wrong = 0;
    for (int row = 0; row < (int) NSHeight(clipInWindow); row++) {
        // the window's top-left origin, rows from the top of the backing store
        int backingRow = (int) (height - (NSMaxY(clipInWindow))) + row;
        if (backingRow < 0 || backingRow >= (int) height)
            continue;
        unsigned char *p = data + backingRow * bpr + (size_t) ((NSMinX(clipInWindow) + 20) * 4);
        int docY = (int) floor(NSMinY(visible)) + row;
        int expected = levelAtRow(docY);
        if (abs(p[0] - expected) > 3 || abs(p[1] - expected) > 3 || abs(p[2] - expected) > 3)
            wrong++;
    }
    return wrong;
}

static void scrollAndShow(NSWindow *window, NSClipView *clip, NSScrollView *scroll, NSPoint point)
{
    [clip scrollToPoint: point];
    [scroll reflectScrolledClipView: clip];
    [window displayIfNeeded];
}

static void run(BOOL copies)
{
    NSString *label = copies ? @"copiesOnScroll" : @"no copy";
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 240) styleMask: NSWindowStyleMaskTitled
                                                      backing: NSBackingStoreBuffered defer: NO];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 240)];
    [scroll setHasVerticalScroller: NO];
    [scroll setBorderType: NSNoBorder];
    Doc *doc = [[Doc alloc] initWithFrame: NSMakeRect(0, 0, 300, 4000)];
    [scroll setDocumentView: doc];
    [window setContentView: scroll];
    NSClipView *clip = [scroll contentView];
    [clip setCopiesOnScroll: copies];
    [window orderFront: nil];
    spin(0.7);
    [window displayIfNeeded];
    expect(wrongRows(window, clip, doc) == 0, [NSString stringWithFormat: @"%@: initial display is right", label]);

    NSPoint steps[] = { { 0, 40 }, { 0, 15 }, { 0, 22 }, { 0, 2000 }, { 0, 1990 } };
    for (int i = 0; i < 5; i++) {
        drawnArea = 0;
        drawCalls = 0;
        scrollAndShow(window, clip, scroll, steps[i]);
        int wrong = wrongRows(window, clip, doc);
        printf("%s: scroll to y=%g: drawn area %.0f in %d calls, wrong rows %d\n", [label UTF8String], steps[i].y, drawnArea, drawCalls, wrong);
        expect(wrong == 0, [NSString stringWithFormat: @"%@: window correct after scrolling to y=%g", label, steps[i].y]);
        if (i == 0 || i == 4) {
            // a 40 and a 10 point step
            double step = i == 0 ? 40 : 10;
            double visibleArea = 300.0 * 240.0;
            if (copies)
                expect(drawnArea <= step * 300 * 1.2 + 300, [NSString stringWithFormat: @"%@: a %g point step draws only the exposed strip (%.0f)", label, step, drawnArea]);
            else
                printf("%s: a %g point step draws %.0f of %.0f visible\n", [label UTF8String], step, drawnArea, visibleArea);
        }
    }
    scrollAndShow(window, clip, scroll, NSMakePoint(0, 100.5));
    scrollAndShow(window, clip, scroll, NSMakePoint(0, 100));
    expect(wrongRows(window, clip, doc) == 0, [NSString stringWithFormat: @"%@: back to a whole position is correct", label]);

    struct timespec t0, t1;
    drawnArea = 0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < 300; i++)
        scrollAndShow(window, clip, scroll, NSMakePoint(0, 100 + (i % 50) * 3));
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("%s: 300 steps of 3 points: %.1f ms, drawn area %.0f\n", [label UTF8String],
           (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6, drawnArea);
    expect(wrongRows(window, clip, doc) == 0, [NSString stringWithFormat: @"%@: still correct after 300 steps", label]);
    [window orderOut: nil];
    [window release];
    [scroll release];
    [doc release];
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        run(NO);
        run(YES);
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
