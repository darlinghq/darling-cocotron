// Copyright (C) 2026 Lubos Dolezel
//
// Legacy scrollers as macOS 10.14.4 builds and draws them (the values of macOS 26.7.3 are different and not
// followed).
//  - test_quirk_scroller_part_geometry: the knob, the pages before and after it and the slot of enabled
//    scrollers: the knob's travel starts and ends 2 points inside the slot, the knob is floor(proportion x
//    (length - 4)) long and at least 20, there are no arrow buttons. The table rows are from the probe
//    mac-probes/ua5-scroller-parts.m run on 10.14.4: length, knob proportion, value, then knob y and height,
//    height of the page before it and y and height of the page after it.
//  - test_quirk_scroller_drawing: a 15 point wide scroller has a track of very light gray with a darker line
//    along each long edge, and a mid gray knob 8 points wide in the middle (4 points in from the left edge);
//    a scroller that is not enabled shows no knob.
//  - test_quirk_scroller_widths: scrollerWidthForControlSize:scrollerStyle: is 15, 11 and 11 for legacy
//    scrollers of the regular, small and mini control sizes, and 16, 14 and 14 for overlay scrollers.
//  - test_quirk_scroller_control_sizes: a small (or mini) scroller has an 11 point artwork with a knob 6
//    points wide, 3 points in from the left; the artwork lies against the right edge, so a regular knob in an
//    11 point scroller starts at its left edge, and a small knob in a 15 point scroller starts 7 points in.
//    The knob keeps its color while highlighted.
//  - test_quirk_overlay_scroller_drawing: -drawKnob of an overlay scroller draws a dark capsule 7 points
//    wide (5 for the small size) that ends 2 points before the right edge; over white it is a gray of 0.49.
//  - test_quirk_scroll_view_corner: the square between the vertical and horizontal legacy scrollers of a scroll
//    view is the track's very light gray, with a line of 0.93 along its right and bottom edges.
// The drawing values are from mac-probes/aqua-scroller-divider.m and -mixed.m run on 10.14.4.
//
// Rows where the knob's position is a fraction of a point before rounding are left out: macOS 10.14.4 rounds
// those up or down in a way the probe did not explain, and the knob is then one point off here.
// Build: clang -framework AppKit appkit-scroller-parts.m
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static const double table[][8] = {
    {60, 0.05, 0.00, 2, 20, 2, 22, 38},
    {60, 0.30, 0.25, 11, 20, 11, 31, 29},
    {60, 0.50, 1.00, 30, 28, 30, 58, 2},
    {60, 0.90, 1.00, 8, 50, 7, 58, 2},
    {120, 0.30, 0.00, 2, 34, 2, 37, 83},
    {120, 1.00, 0.25, 2, 116, 2, 118, 2},
    {300, 0.05, 0.00, 2, 20, 2, 22, 278},
    {300, 0.50, 0.25, 39, 148, 39, 187, 113},
    {300, 0.90, 1.00, 32, 266, 31, 298, 2}
};

static void test_quirk_scroller_part_geometry(void) {
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        const double *row = table[i];
        NSScroller *s = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, 15, row[0])];
        [s setEnabled:YES];
        [s setKnobProportion:row[1]];
        [s setDoubleValue:row[2]];
        NSRect knob = [s rectForPart:NSScrollerKnob], before = [s rectForPart:NSScrollerDecrementPage];
        NSRect after = [s rectForPart:NSScrollerIncrementPage], slot = [s rectForPart:NSScrollerKnobSlot];
        CHECK(knob.origin.y == row[3] && knob.size.height == row[4]);
        CHECK(before.size.height == row[5]);
        CHECK(after.origin.y == row[6] && after.size.height == row[7]);
        CHECK(slot.origin.y == 0 && slot.size.height == row[0]);
        CHECK(knob.size.width == 15);
        CHECK(NSIsEmptyRect([s rectForPart:NSScrollerIncrementLine]) && NSIsEmptyRect([s rectForPart:NSScrollerDecrementLine]));
    }
    // Horizontal: the same along x.
    NSScroller *h = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, 120, 15)];
    [h setEnabled:YES];
    [h setKnobProportion:0.3];
    [h setDoubleValue:0.5];
    NSRect knob = [h rectForPart:NSScrollerKnob];
    CHECK(knob.origin.x == 43 && knob.size.width == 34 && knob.size.height == 15);
    // A scroller that is not enabled has the same knob rectangle.
    [h setEnabled:NO];
    CHECK(NSEqualRects([h rectForPart:NSScrollerKnob], knob));
}

static NSColor *pixel(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    return [[rep colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
}

static NSBitmapImageRep *render(NSView *view) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:view.frame styleMask:NSWindowStyleMaskTitled
            backing:NSBackingStoreBuffered defer:NO];
    [w setContentView:view];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}

static void test_quirk_scroller_drawing(void) {
    NSScroller *s = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, 15, 120)];
    [s setEnabled:YES];
    [s setKnobProportion:0.3];
    [s setDoubleValue:0.5];
    NSBitmapImageRep *rep = render(s);
    // The knob rectangle is y 43..76 from the top (the scroller is flipped, row 0 is its top).
    CHECK(fabs([pixel(rep, 7, 60) whiteComponent] - 0.76) < 0.04);   // the knob
    CHECK(fabs([pixel(rep, 3, 60) whiteComponent] - 0.98) < 0.03);   // the track beside the knob
    CHECK(fabs([pixel(rep, 12, 60) whiteComponent] - 0.98) < 0.03);
    CHECK(fabs([pixel(rep, 0, 20) whiteComponent] - 0.91) < 0.04);   // the line along the edge
    CHECK(fabs([pixel(rep, 14, 20) whiteComponent] - 0.93) < 0.04);
    CHECK(fabs([pixel(rep, 7, 20) whiteComponent] - 0.98) < 0.03);   // the track outside the knob
    CHECK(fabs([pixel(rep, 4, 44) whiteComponent] - 0.98) < 0.03);   // the corner of the knob rectangle
    [s setEnabled:NO];
    rep = render(s);
    CHECK(fabs([pixel(rep, 7, 60) whiteComponent] - 0.98) < 0.03);   // no knob when not enabled
}

static void test_quirk_scroller_widths(void) {
    CHECK([NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy] == 15);
    CHECK([NSScroller scrollerWidthForControlSize:NSControlSizeSmall scrollerStyle:NSScrollerStyleLegacy] == 11);
    CHECK([NSScroller scrollerWidthForControlSize:NSControlSizeMini scrollerStyle:NSScrollerStyleLegacy] == 11);
    CHECK([NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleOverlay] == 16);
    CHECK([NSScroller scrollerWidthForControlSize:NSControlSizeSmall scrollerStyle:NSScrollerStyleOverlay] == 14);
    CHECK([NSScroller scrollerWidthForControlSize:NSControlSizeMini scrollerStyle:NSScrollerStyleOverlay] == 14);
}

static BOOL isKnob(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSColor *c = [rep colorAtX:x y:y];
    return [c alphaComponent] > 0.9 && fabs([pixel(rep, x, y) whiteComponent] - 0.76) < 0.04;
}

// The columns of row y that the knob covers, as first and last column; -1 when there are none.
static void knobColumns(NSBitmapImageRep *rep, NSInteger y, NSInteger *first, NSInteger *last) {
    *first = *last = -1;
    for (NSInteger x = 0; x < [rep pixelsWide]; x++)
        if (isKnob(rep, x, y)) {
            if (*first < 0)
                *first = x;
            *last = x;
        }
}

static NSScroller *legacyScroller(CGFloat width, NSControlSize size) {
    NSScroller *s = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, width, 120)];
    [s setScrollerStyle:NSScrollerStyleLegacy];
    [s setControlSize:size];
    [s setEnabled:YES];
    [s setKnobProportion:0.3];
    [s setDoubleValue:0.5];
    return s;
}

static void test_quirk_scroller_control_sizes(void) {
    NSInteger first, last;
    NSBitmapImageRep *rep = render(legacyScroller(11, NSControlSizeSmall));

    knobColumns(rep, 60, &first, &last);
    CHECK(first == 3 && last == 8);
    CHECK(fabs([pixel(rep, 0, 20) whiteComponent] - 0.91) < 0.04);   // the line along the left edge
    CHECK(fabs([pixel(rep, 10, 20) whiteComponent] - 0.93) < 0.04);  // and along the right edge
    CHECK(fabs([pixel(rep, 5, 20) whiteComponent] - 0.98) < 0.03);

    rep = render(legacyScroller(11, NSControlSizeMini));
    knobColumns(rep, 60, &first, &last);
    CHECK(first == 3 && last == 8);

    rep = render(legacyScroller(11, NSControlSizeRegular));
    knobColumns(rep, 60, &first, &last);
    CHECK(first == 0 && last == 7);

    rep = render(legacyScroller(15, NSControlSizeSmall));
    knobColumns(rep, 60, &first, &last);
    CHECK(first == 7 && last == 12);

    NSScroller *h = legacyScroller(15, NSControlSizeRegular);
    [h highlight:YES];
    rep = render(h);
    knobColumns(rep, 60, &first, &last);
    CHECK(first == 4 && last == 11);

    // a horizontal small scroller: the knob is 3 points below the top edge and 6 points high
    NSScroller *hs = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, 120, 11)];
    [hs setScrollerStyle:NSScrollerStyleLegacy];
    [hs setControlSize:NSControlSizeSmall];
    [hs setEnabled:YES];
    [hs setKnobProportion:0.3];
    [hs setDoubleValue:0.5];
    rep = render(hs);
    CHECK(!isKnob(rep, 60, 2) && isKnob(rep, 60, 3) && isKnob(rep, 60, 8) && !isKnob(rep, 60, 9));
}

static void test_quirk_overlay_scroller_drawing(void) {
    for (int i = 0; i < 2; i++) {
        NSControlSize size = i ? NSControlSizeSmall : NSControlSizeRegular;
        CGFloat width = [NSScroller scrollerWidthForControlSize:size scrollerStyle:NSScrollerStyleOverlay];
        NSScroller *s = [[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, width, 120)];
        [s setScrollerStyle:NSScrollerStyleOverlay];
        [s setControlSize:size];
        [s setEnabled:YES];
        [s setKnobProportion:0.3];
        [s setDoubleValue:0.5];

        // draw the knob alone over white, through the public drawing method
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger) width
                pixelsHigh:120 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, width, 120));
        [s drawKnob];
        [NSGraphicsContext restoreGraphicsState];

        NSInteger first = -1, last = -1;
        for (NSInteger x = 0; x < (NSInteger) width; x++)
            if (fabs([pixel(rep, x, 60) whiteComponent] - 0.49) < 0.05) {
                if (first < 0)
                    first = x;
                last = x;
            }
        CHECK(last == (NSInteger) width - 3);
        CHECK(last - first + 1 == (i ? 5 : 7));
        CHECK(fabs([pixel(rep, 1, 60) whiteComponent] - 1) < 0.03);   // no track under the knob
    }
}

static void test_quirk_scroll_view_corner(void) {
    NSScrollView *view = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 120, 100)];
    [view setHasVerticalScroller:YES];
    [view setHasHorizontalScroller:YES];
    [view setScrollerStyle:NSScrollerStyleLegacy];
    [view setBorderType:NSNoBorder];
    [view setDocumentView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)]];
    NSBitmapImageRep *rep = render(view);
    [view tile];
    rep = render(view);
    // the corner is x 105..119, y 85..99 from the top left
    CHECK(fabs([pixel(rep, 112, 92) whiteComponent] - 0.98) < 0.012);
    CHECK(fabs([pixel(rep, 119, 92) whiteComponent] - 0.93) < 0.03);
    CHECK(fabs([pixel(rep, 112, 99) whiteComponent] - 0.93) < 0.03);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_scroller_part_geometry();
        test_quirk_scroller_drawing();
        test_quirk_scroller_widths();
        test_quirk_scroller_control_sizes();
        test_quirk_overlay_scroller_drawing();
        test_quirk_scroll_view_corner();
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
