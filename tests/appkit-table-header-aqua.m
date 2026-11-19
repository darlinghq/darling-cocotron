// Copyright (C) 2026 Lubos Dolezel
//
// Table headers look like the Aqua ones of macOS 10.14 in the light appearance. The expected values are from
// renders of a 330 x 17 header with three 100 point columns (103 with the intercell spacing) on Mac OS X 10.14.4
// (black-box observation, probes mac-probes/aqua-table-header*.m; QUIRK-tagged code in NSGraphicsStyle
// (NSTableView), NSTableHeaderCell, NSTableHeaderView, NSImageSystemTemplates and DarlingDisplay).
//  - test_header_basics: white inside, light gray lines along the top and bottom edge.
//  - test_quirk_header_lines: the separator is in the last column of points of every column, the last one too,
//    3 points shorter than the header at each end, (229,229,229); right of the last column the header has its
//    lines but no separator.
//  - test_quirk_pressed_cell: a highlighted header cell is (220,220,220) between the top line and a white line
//    above the bottom line, and has no separator.
//  - test_quirk_header_cell_defaults: a new header cell has the 11 point system font, headerTextColor, tail
//    truncation, and title and drawing rects equal to its bounds.
//  - test_quirk_header_colors: headerColor is gray 0.667 and headerTextColor black at alpha 0.847 (sRGB).
//  - test_quirk_sort_indicator_images: NSAscendingSortIndicator and NSDescendingSortIndicator are 9 x 9 point
//    template images of a chevron pointing up or down, 75% black.
//  - test_quirk_sort_indicator: -sortIndicatorRectForBounds: is 9 x 9 points, 4 points from the right edge and
//    centred vertically; -drawSortIndicatorWithFrame:... draws the chevron one point to the right of it at full
//    strength for priority 0 and nothing for other priorities.
//  - test_quirk_indicator_image: the header draws a template indicator image in black at half opacity, the
//    NSAscendingSortIndicator chevron half as dark as on its own, and other images as they are.
//  - test_quirk_sorted_column: the column the table is sorted by shows a bold title and the full-strength
//    indicator (also when an indicator image is set for it); the highlighted table column a bold title.
//  - test_quirk_title_position: titles are inset 2 points from the left, 4 from the right (14 when right
//    aligned) and centred vertically.
//  - test_quirk_corner_view: the visible corner next to a legacy vertical scroller has the header lines but no
//    separator.
// Build: clang -framework AppKit appkit-table-header-aqua.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

static int gray(NSBitmapImageRep *rep, int x, int y) {
    int c[4];
    rgba(rep, x, y, c);
    return c[0];
}

@interface Rows : NSObject
@end
@implementation Rows
- (NSInteger) numberOfRowsInTableView: (NSTableView *) t { return 30; }
- (id) tableView: (NSTableView *) t objectValueForTableColumn: (NSTableColumn *) c row: (NSInteger) r { return @""; }
@end

static NSScrollView *makeTable(NSTableView **out) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 330, 120)];
    [scroll setBorderType: NSNoBorder];
    NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 330, 120)];
    for (int i = 0; i < 3; i++) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]];
        [[column headerCell] setStringValue: @"Title"];
        [column setWidth: 100];
        [table addTableColumn: column];
    }
    [scroll setDocumentView: table];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 330, 120)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setContentView: scroll];
    NSView *header = [table headerView];
    [header setFrameSize: NSMakeSize(330, 17)];
    *out = table;
    return scroll;
}

static NSBitmapImageRep *render(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    return rep;
}

// a header cell drawn on its own into a flipped 103 x 17 bitmap, as the header view draws it; indicator > 0
// adds the ascending, < 0 the descending indicator of priority |indicator| - 1
static NSBitmapImageRep *renderCell(NSTableHeaderView *header, NSTableHeaderCell *cell, int indicator) {
    NSRect r = NSMakeRect(0, 0, 103, 17);
    NSBitmapImageRep *rep = [header bitmapImageRepForCachingDisplayInRect: r];
    CGContextRef cg = [[NSGraphicsContext graphicsContextWithBitmapImageRep: rep] CGContext];
    CGContextTranslateCTM(cg, 0, 17);
    CGContextScaleCTM(cg, 1, -1);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithCGContext: cg flipped: YES]];
    [cell drawWithFrame: r inView: header];
    if (indicator)
        [cell drawSortIndicatorWithFrame: r inView: header ascending: indicator > 0 priority: abs(indicator) - 1];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static int darkest(NSBitmapImageRep *rep, int x0, int x1, int y0, int y1) {
    int result = 255;
    for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++)
            result = MIN(result, gray(rep, x, y));
    return result;
}

static void test_header_basics(void) {
    NSTableView *table;
    makeTable(&table);
    NSBitmapImageRep *rep = render([table headerView]);
    int h = (int) [rep pixelsHigh], c[4];

    CHECK(h == 17);
    // white inside, away from the titles
    rgba(rep, 1, 8, c);
    CHECK(c[3] == 255 && c[0] >= 250 && c[1] >= 250 && c[2] >= 250);
    for (int x = 0; x < 2; x++) {
        rgba(rep, 1 + x * 150, 0, c);
        CHECK(c[3] == 255 && abs(c[0] - 214) <= 3);
        rgba(rep, 1 + x * 150, h - 1, c);
        CHECK(c[3] == 255 && abs(c[0] - 214) <= 3);
    }
    // no separator at the left edge of the first column
    CHECK(gray(rep, 0, 8) > 245);
}

static void test_quirk_header_lines(void) {
    NSTableView *table;
    makeTable(&table);
    NSTableHeaderView *header = (NSTableHeaderView *) [table headerView];
    NSBitmapImageRep *rep = render(header);

    for (int col = 0; col < 3; col++) {
        // 102 and 205 for the first two columns; the last one may be widened to the header's width
        int x = (int) NSMaxX([header headerRectOfColumn: col]) - 1;
        CHECK(col == 2 || x == 103 * col + 102);
        CHECK(gray(rep, x, 0) == 214 && gray(rep, x, 16) == 214);
        CHECK(gray(rep, x, 1) > 250 && gray(rep, x, 2) > 250);
        for (int y = 3; y <= 13; y++)
            CHECK(abs(gray(rep, x, y) - 229) <= 3);
        CHECK(gray(rep, x, 14) > 250 && gray(rep, x, 15) > 250);
        // not at the first point of the next column
        if (x + 1 < 330)
            CHECK(gray(rep, x + 1, 8) > 250);
    }
    // the header is drawn on to its right edge, without a separator after the last column
    int last = (int) NSMaxX([header headerRectOfColumn: 2]);
    for (int x = last; x < (int) NSWidth([header bounds]); x++) {
        CHECK(gray(rep, x, 0) == 214 && gray(rep, x, 16) == 214);
        for (int y = 1; y <= 15; y++)
            CHECK(gray(rep, x, y) > 250);
    }
}

static void test_quirk_pressed_cell(void) {
    NSTableView *table;
    makeTable(&table);
    NSTableHeaderView *header = (NSTableHeaderView *) [table headerView];
    NSTableHeaderCell *cell = [[[table tableColumns] objectAtIndex: 0] headerCell];

    [cell setHighlighted: YES];
    NSBitmapImageRep *rep = renderCell(header, cell, 0);
    [cell setHighlighted: NO];

    CHECK(gray(rep, 1, 0) == 214 && gray(rep, 1, 16) == 214);
    for (int y = 1; y <= 14; y++)
        CHECK(abs(gray(rep, 1, y) - 220) <= 3);
    CHECK(gray(rep, 1, 15) > 250);
    // no separator
    CHECK(abs(gray(rep, 102, 8) - 220) <= 3);

    rep = renderCell(header, cell, 0);
    CHECK(gray(rep, 1, 8) > 250 && abs(gray(rep, 102, 8) - 229) <= 3);
}

static void test_quirk_header_cell_defaults(void) {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"c"];
    NSTableHeaderCell *cell = [column headerCell];
    NSColor *text = [[cell textColor] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    NSRect bounds = NSMakeRect(0, 0, 103, 17);

    CHECK([cell isKindOfClass: [NSTableHeaderCell class]]);
    CHECK([[cell font] pointSize] == 11);
    CHECK(text != nil && [text redComponent] < 0.01 && fabs([text alphaComponent] - 0.847) < 0.01);
    CHECK([cell lineBreakMode] == NSLineBreakByTruncatingTail);
    CHECK(NSEqualRects([cell titleRectForBounds: bounds], bounds));
    CHECK(NSEqualRects([cell drawingRectForBounds: bounds], bounds));
}

static void test_quirk_header_colors(void) {
    NSColor *header = [[NSColor headerColor] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    NSColor *text = [[NSColor headerTextColor] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];

    CHECK(fabs([header redComponent] - 0.667) < 0.01 && fabs([header greenComponent] - 0.667) < 0.01 &&
          fabs([header blueComponent] - 0.667) < 0.01 && [header alphaComponent] == 1);
    CHECK([text redComponent] < 0.01 && [text greenComponent] < 0.01 && [text blueComponent] < 0.01 &&
          fabs([text alphaComponent] - 0.847) < 0.01);
}

// the image drawn over white into a 9 x 9 bitmap; rows counted from the top
static NSBitmapImageRep *renderImage(NSImage *image) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 9 pixelsHigh: 9
        bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSCalibratedRGBColorSpace
        bytesPerRow: 0 bitsPerPixel: 0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0, 0, 9, 9));
    [image drawInRect: NSMakeRect(0, 0, 9, 9) fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static void test_quirk_sort_indicator_images(void) {
    NSImage *up = [NSImage imageNamed: @"NSAscendingSortIndicator"];
    NSImage *down = [NSImage imageNamed: @"NSDescendingSortIndicator"];

    CHECK(up != nil && down != nil);
    if (up == nil || down == nil)
        return;
    CHECK(NSEqualSizes([up size], NSMakeSize(9, 9)) && NSEqualSizes([down size], NSMakeSize(9, 9)));
    CHECK([up isTemplate] && [down isTemplate]);
    NSBitmapImageRep *rep = renderImage(up);
    // the tip at the top, the ends at the bottom left and right, nothing inside or around
    CHECK(abs(gray(rep, 4, 2) - 66) <= 20);
    CHECK(abs(gray(rep, 1, 5) - 66) <= 20 && abs(gray(rep, 7, 5) - 66) <= 20);
    CHECK(gray(rep, 4, 5) > 240 && gray(rep, 4, 0) > 245 && gray(rep, 4, 7) > 245);
    CHECK(gray(rep, 0, 5) > 230 && gray(rep, 8, 5) > 230);
    rep = renderImage(down);
    CHECK(abs(gray(rep, 4, 6) - 66) <= 20);
    CHECK(abs(gray(rep, 1, 3) - 66) <= 20 && abs(gray(rep, 7, 3) - 66) <= 20);
    CHECK(gray(rep, 4, 3) > 240 && gray(rep, 4, 1) > 245 && gray(rep, 4, 8) > 245);
}

static void test_quirk_sort_indicator(void) {
    NSTableView *table;
    makeTable(&table);
    NSTableHeaderView *header = (NSTableHeaderView *) [table headerView];
    NSTableHeaderCell *cell = [[[table tableColumns] objectAtIndex: 0] headerCell];

    CHECK(NSEqualRects([cell sortIndicatorRectForBounds: NSMakeRect(0, 0, 103, 17)], NSMakeRect(90, 4, 9, 9)));
    CHECK(NSEqualRects([cell sortIndicatorRectForBounds: NSMakeRect(0, 0, 103, 25)], NSMakeRect(90, 8, 9, 9)));
    CHECK(NSEqualRects([cell sortIndicatorRectForBounds: NSMakeRect(0, 0, 103, 30)], NSMakeRect(90, 11, 9, 9)));
    CHECK(NSEqualRects([cell sortIndicatorRectForBounds: NSMakeRect(103, 0, 103, 17)], NSMakeRect(193, 4, 9, 9)));

    // ascending: an upward chevron at x 92..98, rows 6..9, at full strength
    NSBitmapImageRep *rep = renderCell(header, cell, 1);
    CHECK(gray(rep, 95, 6) < 100);
    CHECK(gray(rep, 92, 9) < 100 && gray(rep, 98, 9) < 100);
    CHECK(gray(rep, 95, 9) > 240 && gray(rep, 95, 4) > 245 && gray(rep, 95, 11) > 245);
    CHECK(gray(rep, 91, 9) > 220);
    // descending: a downward chevron, rows 7..10
    rep = renderCell(header, cell, -1);
    CHECK(gray(rep, 95, 10) < 100);
    CHECK(gray(rep, 92, 7) < 100 && gray(rep, 98, 7) < 100);
    CHECK(gray(rep, 95, 7) > 240);
    // a secondary sort draws nothing
    rep = renderCell(header, cell, 2);
    CHECK(darkest(rep, 85, 101, 2, 14) > 220);
}

static void test_quirk_indicator_image(void) {
    NSTableView *table;
    makeTable(&table);
    NSTableColumn *c0 = [[table tableColumns] objectAtIndex: 0], *c1 = [[table tableColumns] objectAtIndex: 1];
    int c[4];

    // the named chevron set as the indicator image is half as dark as on its own (about 160 over white)
    [table setIndicatorImage: [NSImage imageNamed: @"NSAscendingSortIndicator"] inTableColumn: c0];
    NSBitmapImageRep *rep = render([table headerView]);
    int tip = darkest(rep, 93, 95, 5, 7);
    CHECK(tip > 135 && tip < 190);
    CHECK(gray(rep, 91, 9) < 215 && gray(rep, 97, 9) < 215);

    // an opaque template image: its coverage in black at half opacity, filling x 193..201, rows 4..12
    NSBitmapImageRep *bits = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 9 pixelsHigh: 9
        bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSCalibratedRGBColorSpace
        bytesPerRow: 0 bitsPerPixel: 0];
    for (int y = 0; y < 9; y++)
        for (int x = 0; x < 9; x++)
            [bits setColor: [NSColor redColor] atX: x y: y];
    NSImage *red = [[NSImage alloc] initWithSize: NSMakeSize(9, 9)];
    [red addRepresentation: bits];
    NSImage *template = [red copy];
    [template setTemplate: YES];
    [table setIndicatorImage: template inTableColumn: c1];
    rep = render([table headerView]);
    rgba(rep, 197, 8, c);
    CHECK(abs(c[0] - 128) <= 12 && abs(c[1] - 128) <= 12 && abs(c[2] - 128) <= 12);
    CHECK(abs(gray(rep, 193, 4) - 128) <= 12 && abs(gray(rep, 201, 12) - 128) <= 12);
    CHECK(gray(rep, 192, 8) > 245 && gray(rep, 202, 8) > 245 && gray(rep, 197, 3) > 245 && gray(rep, 197, 13) > 245);

    // other images are drawn as they are, not tinted (green is allowed some room: the calibrated red of the
    // bitmap may be matched to the screen's colour space)
    [table setIndicatorImage: red inTableColumn: c1];
    rep = render([table headerView]);
    rgba(rep, 197, 8, c);
    CHECK(c[0] > 240 && c[1] < 60 && c[2] < 15);
}

static BOOL sameArea(NSBitmapImageRep *a, NSBitmapImageRep *b, int x0, int x1) {
    for (int y = 0; y < 17; y++)
        for (int x = x0; x <= x1; x++)
            if (gray(a, x, y) != gray(b, x, y))
                return NO;
    return YES;
}

static void test_quirk_sorted_column(void) {
    NSTableView *table;
    makeTable(&table);
    NSTableColumn *c0 = [[table tableColumns] objectAtIndex: 0], *c1 = [[table tableColumns] objectAtIndex: 1];

    [c0 setSortDescriptorPrototype: [NSSortDescriptor sortDescriptorWithKey: @"k0" ascending: YES]];
    [c1 setSortDescriptorPrototype: [NSSortDescriptor sortDescriptorWithKey: @"k1" ascending: YES]];
    NSBitmapImageRep *plain = render([table headerView]);

    // sorted by k1, descending: column 1 has a bold title and a full-strength downward chevron at x 195..201
    [table setSortDescriptors: [NSArray arrayWithObjects: [NSSortDescriptor sortDescriptorWithKey: @"k1" ascending: NO],
                                        [NSSortDescriptor sortDescriptorWithKey: @"k0" ascending: YES], nil]];
    CHECK([table indicatorImageInTableColumn: c1] == nil);
    NSBitmapImageRep *rep = render([table headerView]);
    CHECK(gray(rep, 198, 10) < 100 && gray(rep, 195, 7) < 100 && gray(rep, 201, 7) < 100);
    CHECK(gray(rep, 198, 7) > 240);
    CHECK(!sameArea(plain, rep, 104, 160));
    // the column of the secondary sort is unchanged
    CHECK(sameArea(plain, rep, 0, 102));

    // an indicator image set for the sorted column is not drawn: only the full-strength chevron
    [table setSortDescriptors: [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"k0" ascending: YES]]];
    [table setIndicatorImage: [NSImage imageNamed: @"NSAscendingSortIndicator"] inTableColumn: c0];
    rep = render([table headerView]);
    CHECK(gray(rep, 95, 6) < 100 && gray(rep, 92, 9) < 100);
    CHECK(gray(rep, 91, 9) > 220);
    [table setIndicatorImage: nil inTableColumn: c0];

    // a key no column has changes nothing
    [table setSortDescriptors: [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"zzz" ascending: NO]]];
    CHECK(sameArea(plain, render([table headerView]), 0, 329));
    [table setSortDescriptors: [NSArray array]];

    // the highlighted table column: a bold title, nothing else
    [table setHighlightedTableColumn: c1];
    rep = render([table headerView]);
    CHECK(!sameArea(plain, rep, 104, 160));
    CHECK(sameArea(plain, rep, 161, 205));
    [table setHighlightedTableColumn: nil];
}

// the bounding box (x0, x1, y0, y1) of title ink (< 200) between columns from and to
static void inkBox(NSBitmapImageRep *rep, int from, int to, int *box) {
    box[0] = 1000; box[1] = -1; box[2] = 1000; box[3] = -1;
    for (int y = 1; y < 16; y++)
        for (int x = from; x <= to; x++)
            if (gray(rep, x, y) < 200) {
                box[0] = MIN(box[0], x); box[1] = MAX(box[1], x);
                box[2] = MIN(box[2], y); box[3] = MAX(box[3], y);
            }
}

static void test_quirk_title_position(void) {
    NSTableView *table;
    makeTable(&table);
    NSArray *columns = [table tableColumns];
    [[[columns objectAtIndex: 1] headerCell] setAlignment: NSTextAlignmentCenter];
    [[[columns objectAtIndex: 2] headerCell] setAlignment: NSTextAlignmentRight];
    for (int i = 0; i < 3; i++)
        [[[columns objectAtIndex: i] headerCell] setStringValue: @"MMMM"];
    NSBitmapImageRep *rep = render([table headerView]);
    int box[4];

    inkBox(rep, 0, 101, box);
    CHECK(box[0] >= 2 && box[0] <= 4);
    // vertically centred: Mojave's 11 point title has ink on rows 4..11
    CHECK(box[2] >= 3 && box[3] <= 13 && fabs((box[2] + box[3]) / 2.0 - 7.5) <= 1.5);
    inkBox(rep, 103, 204, box);
    CHECK(fabs((box[0] + box[1]) / 2.0 - 153.5) <= 1.5);
    // right aligned: Mojave's title ends at x 294 in the column ending at 309
    int end = (int) NSMaxX([(NSTableHeaderView *) [table headerView] headerRectOfColumn: 2]);
    inkBox(rep, 206, end - 2, box);
    CHECK(box[1] >= end - 17 && box[1] <= end - 14);
}

static void test_quirk_corner_view(void) {
    NSTableView *table;
    NSScrollView *scroll = makeTable(&table);
    Rows *rows = [Rows new];
    [scroll setScrollerStyle: NSScrollerStyleLegacy];
    [scroll setHasVerticalScroller: YES];
    [table setDataSource: (id) rows];
    [scroll tile];
    [table reloadData];
    NSView *header = [table headerView];
    NSBitmapImageRep *rep = render(scroll);
    int h = (int) NSHeight([header frame]);
    int right = (int) NSMaxX([[header superview] frame]);

    CHECK(h == 17);
    CHECK(right >= 312 && right <= 318);
    for (int x = right; x < 330; x++) {
        CHECK(abs(gray(rep, x, 0) - 214) <= 3 && abs(gray(rep, x, h - 1) - 214) <= 3);
        for (int y = 1; y < h - 1; y++)
            CHECK(gray(rep, x, y) > 250);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_header_basics();
        test_quirk_header_lines();
        test_quirk_pressed_cell();
        test_quirk_header_cell_defaults();
        test_quirk_header_colors();
        test_quirk_sort_indicator_images();
        test_quirk_sort_indicator();
        test_quirk_indicator_image();
        test_quirk_sorted_column();
        test_quirk_title_position();
        test_quirk_corner_view();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
