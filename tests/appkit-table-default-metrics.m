// Copyright (C) 2026 Lubos Dolezel
//
// The metrics of a new NSTableView and NSOutlineView, how the columns follow
// the clip view's width, and the table's corner view with overlay scrollers.
// The expected values were observed on macOS 10.14.4 (black-box).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdarg.h>

static int failures;

static void fail(const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    fprintf(stderr, "FAIL ");
    vfprintf(stderr, format, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    failures++;
}

@interface Rows : NSObject
@end
@implementation Rows
- (NSInteger) numberOfRowsInTableView: (NSTableView *) table { return 3; }
- (id) tableView: (NSTableView *) table objectValueForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    return @"v";
}
@end

static NSTableView *tableIn(NSScrollView *sv, int count, CGFloat width) {
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    for (int i = 0; i < count; i++) {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]]
                autorelease];
        [column setWidth: width];
        [table addTableColumn: column];
    }
    [sv setDocumentView: table];
    return table;
}

static NSScrollView *scrollView(NSScrollerStyle style, CGFloat width) {
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, width, 200)] autorelease];
    [sv setHasVerticalScroller: YES];
    [sv setScrollerStyle: style];
    return sv;
}

static void expectColumns(const char *what, NSTableView *table, int count, ...) {
    va_list ap;
    va_start(ap, count);
    for (int i = 0; i < count; i++) {
        CGFloat expected = va_arg(ap, double);
        CGFloat width = [[[table tableColumns] objectAtIndex: i] width];
        if (width != expected)
            fail("%s: column %d is %g wide, expected %g", what, i, width, expected);
    }
    va_end(ap);
}

static void test_defaults(void) {
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    if ([table rowHeight] != 17)
        fail("rowHeight %g, expected 17", [table rowHeight]);
    if (!NSEqualSizes([table intercellSpacing], NSMakeSize(3, 2)))
        fail("intercellSpacing {%g,%g}, expected {3,2}", [table intercellSpacing].width,
             [table intercellSpacing].height);
    if ([table columnAutoresizingStyle] != NSTableViewLastColumnOnlyAutoresizingStyle)
        fail("columnAutoresizingStyle %ld, expected last column only", (long) [table columnAutoresizingStyle]);
    NSOutlineView *outline = [[[NSOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    if ([outline rowHeight] != 17 || [outline indentationPerLevel] != 16)
        fail("outline rowHeight %g indentation %g, expected 17 and 16", [outline rowHeight],
             [outline indentationPerLevel]);

    Rows *rows = [[Rows new] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: @"a"] autorelease];
    [table addTableColumn: column];
    [table setDataSource: (id) rows];
    [table reloadData];
    NSRect row = [table rectOfRow: 1];
    if (!NSEqualRects(row, NSMakeRect(0, 19, 103, 19)))
        fail("rectOfRow:1 {%g,%g,%g,%g}, expected {0,19,103,19}", row.origin.x, row.origin.y, row.size.width,
             row.size.height);
}

// Putting a table into a scroll view and laying it out leaves the column
// widths alone, also when the columns leave space.
static void test_columns_not_widened(void) {
    for (int style = 0; style < 2; style++) {
        NSScrollView *sv = scrollView(style, 330);
        NSTableView *table = tableIn(sv, 3, 100);
        [sv tile];
        [table tile];
        expectColumns(style ? "overlay 3x100 in 330" : "legacy 3x100 in 330", table, 3, 100.0, 100.0, 100.0);

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 330, 200)
                                                       styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        sv = scrollView(style, 330);
        [sv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        table = tableIn(sv, 1, 100);
        [window setContentView: sv];
        expectColumns(style ? "overlay 1x100 in window" : "legacy 1x100 in window", table, 1, 100.0);
        [window setContentSize: NSMakeSize(430, 200)];
        expectColumns(style ? "overlay 1x100, window 430" : "legacy 1x100, window 430", table, 1, 100.0);
        [window close];
    }
}

// QUIRK: when the clip view changes width, the columns are resized only if
// they did not fit the new width or exactly filled the old one. See
// -[NSTableView resizeWithOldSuperviewSize:].
static void test_quirk_autoresizing_with_space_left(void) {
    NSScrollView *sv = scrollView(NSScrollerStyleLegacy, 330);
    NSTableView *table = tableIn(sv, 3, 100);
    [sv setFrameSize: NSMakeSize(400, 200)];
    expectColumns("last column, 330 -> 400 with space left", table, 3, 100.0, 100.0, 100.0);
    [sv setFrameSize: NSMakeSize(300, 200)];
    expectColumns("last column, -> 300", table, 3, 100.0, 100.0, 76.0);
    [sv setFrameSize: NSMakeSize(400, 200)];
    expectColumns("last column, filled, -> 400", table, 3, 100.0, 100.0, 176.0);

    sv = scrollView(NSScrollerStyleLegacy, 400);
    table = tableIn(sv, 3, 100);
    [table setColumnAutoresizingStyle: NSTableViewUniformColumnAutoresizingStyle];
    [sv setFrameSize: NSMakeSize(410, 200)];
    expectColumns("uniform, 400 -> 410 with space left", table, 3, 100.0, 100.0, 100.0);
    [sv setFrameSize: NSMakeSize(300, 200)];
    expectColumns("uniform, -> 300", table, 3, 92.0, 92.0, 92.0);
    [sv setFrameSize: NSMakeSize(400, 200)];
    expectColumns("uniform, filled, -> 400", table, 3, 126.0, 125.0, 125.0);

    sv = scrollView(NSScrollerStyleLegacy, 400);
    table = tableIn(sv, 3, 100);
    [table setColumnAutoresizingStyle: NSTableViewReverseSequentialColumnAutoresizingStyle];
    [sv setFrameSize: NSMakeSize(300, 200)];
    expectColumns("reverse sequential, -> 300", table, 3, 76.0, 100.0, 100.0);
    [sv setFrameSize: NSMakeSize(400, 200)];
    expectColumns("reverse sequential, filled, -> 400", table, 3, 176.0, 100.0, 100.0);

    sv = scrollView(NSScrollerStyleOverlay, 400);
    table = tableIn(sv, 3, 100);
    [table setColumnAutoresizingStyle: NSTableViewNoColumnAutoresizing];
    [sv setFrameSize: NSMakeSize(300, 200)];
    expectColumns("no autoresizing, -> 300", table, 3, 100.0, 100.0, 100.0);
}

// sizeLastColumnToFit fills the clip view, sizeToFit fits all columns uniformly.
static void test_fitting(void) {
    for (int style = 0; style < 2; style++) {
        NSScrollView *sv = scrollView(style, 400);
        NSTableView *table = tableIn(sv, 3, 100);
        [table sizeLastColumnToFit];
        expectColumns(style ? "overlay sizeLastColumnToFit" : "legacy sizeLastColumnToFit", table, 3, 100.0, 100.0,
                      style ? 191.0 : 176.0);
        sv = scrollView(style, 400);
        table = tableIn(sv, 3, 100);
        [table sizeToFit];
        if (style)
            expectColumns("overlay sizeToFit", table, 3, 131.0, 130.0, 130.0);
        else
            expectColumns("legacy sizeToFit", table, 3, 126.0, 125.0, 125.0);
    }
}

// QUIRK: no corner view of its own with overlay scrollers. See -[NSTableView cornerView].
static void test_quirk_corner_view_overlay(void) {
    NSScrollView *sv = scrollView(NSScrollerStyleOverlay, 330);
    NSTableView *table = tableIn(sv, 2, 100);
    if ([table cornerView] != nil)
        fail("corner view with overlay scrollers");
    [sv setScrollerStyle: NSScrollerStyleLegacy];
    [sv tile];
    if ([table cornerView] == nil || [[table cornerView] superview] != sv)
        fail("no corner view in the scroll view with legacy scrollers");

    table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSView *custom = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 30, 30)] autorelease];
    [table setCornerView: custom];
    sv = scrollView(NSScrollerStyleOverlay, 330);
    [sv setDocumentView: table];
    if ([table cornerView] != custom)
        fail("a corner view set by the application is not kept with overlay scrollers");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_defaults();
        test_columns_not_widened();
        test_quirk_autoresizing_with_space_left();
        test_fitting();
        test_quirk_corner_view_overlay();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
