// Copyright (C) 2026 Lubos Dolezel
//
// Hidden table columns in a cell-based NSTableView and its header. The contract is the
// documentation of -[NSTableColumn isHidden]
// (https://developer.apple.com/documentation/appkit/nstablecolumn/ishidden): a hidden column is
// not shown but stays in the table's tableColumns and in its numberOfColumns. A column that is
// not shown takes no room, so the columns after it move up and a point is never in it. The
// documentation is silent on the rest; these are pinned by black-box observation on macOS 26.7.3: a hidden
// column takes no width at all, its share of the intercell spacing included; sizeLastColumnToFit resizes the
// last column that is shown; the autoresizing styles leave hidden columns alone
// (test_autoresizing_skips_hidden_columns).
// Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-table-hidden-columns.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Source : NSObject <NSTableViewDataSource>
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 3; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return [NSString stringWithFormat:@"%@ %ld", [c identifier], (long)row];
}
@end

static NSWindow *window;
static NSTableView *table;
static NSScrollView *scroll;

// Three columns of 100, 50 and 80 points with 3 points of spacing: they span 0-103, 103-156, 156-239
static void setup(void)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 500, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 500, 250)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 239, 250)] autorelease];
    [table setIntercellSpacing:NSMakeSize(3, 2)];
    CGFloat widths[3] = {100, 50, 80};
    NSString *names[3] = {@"a", @"b", @"c"};
    for (int i = 0; i < 3; i++)
    {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:names[i]] autorelease];
        [column setMinWidth:10];
        [column setWidth:widths[i]];
        [table addTableColumn:column];
    }
    [table setDataSource:[[[Source alloc] init] autorelease]];
    [scroll setDocumentView:table];
    [window setContentView:scroll];
    [table reloadData];
}

static NSTableColumn *column(NSInteger i) { return [[table tableColumns] objectAtIndex:i]; }

static void test_visible_columns_are_unchanged(void)
{
    setup();
    CHECK(NSMinX([table rectOfColumn:1]) == 103 && NSWidth([table rectOfColumn:1]) == 53);
    CHECK(NSMinX([table rectOfColumn:2]) == 156 && NSWidth([table rectOfColumn:2]) == 83);
    CHECK(NSWidth([table rectOfRow:0]) == 239);
    CHECK([table columnAtPoint:NSMakePoint(120, 5)] == 1);
}

static void test_a_hidden_column_stays_in_the_table(void)
{
    setup();
    [column(1) setHidden:YES];
    CHECK([[table tableColumns] count] == 3);
    CHECK([table numberOfColumns] == 3);
    CHECK([column(1) isHidden]);
}

static void test_rects_close_the_gap(void)
{
    setup();
    [column(1) setHidden:YES];
    CHECK(NSWidth([table rectOfColumn:1]) == 0);
    CHECK(NSMinX([table rectOfColumn:2]) == 103);
    CHECK(NSWidth([table rectOfColumn:2]) == 83);
    CHECK(NSWidth([table rectOfRow:0]) == 186);
    NSRect cell = [table frameOfCellAtColumn:2 row:0];
    CHECK(NSMinX(cell) >= 103 && NSMinX(cell) < 106);
    CHECK([table frameOfCellAtColumn:1 row:0].size.width == 0);
}

static void test_a_point_is_never_in_a_hidden_column(void)
{
    setup();
    [column(1) setHidden:YES];
    CHECK([table columnAtPoint:NSMakePoint(10, 5)] == 0);
    CHECK([table columnAtPoint:NSMakePoint(120, 5)] == 2);
    CHECK([table columnAtPoint:NSMakePoint(180, 5)] == 2);
    CHECK([table columnAtPoint:NSMakePoint(200, 5)] == -1);
    // the range covering the whole table still names the hidden column between its neighbours
    NSRange all = [table columnsInRect:NSMakeRect(0, 0, 186, 20)];
    CHECK(all.location == 0 && NSMaxRange(all) == 3);
}

// The range is one run of columns; a rect over the whole table reaches the last shown column
static void test_ranges_over_whole_rects(void)
{
    setup();
    [column(0) setWidth:200]; // first column wider than the hidden one after it
    [column(1) setHidden:YES];
    NSRange all = [table columnsInRect:NSMakeRect(0, 0, 286, 20)];
    CHECK(all.location == 0 && all.length == 3);
    NSRange inFirst = [table columnsInRect:NSMakeRect(0, 0, 100, 20)];
    CHECK(inFirst.location == 0 && inFirst.length == 1);
    NSRange across = [table columnsInRect:NSMakeRect(150, 0, 100, 20)];
    CHECK(across.location == 0 && across.length == 3);
    NSRange inLast = [table columnsInRect:NSMakeRect(220, 0, 10, 20)];
    CHECK(inLast.location == 2 && inLast.length == 1);

    // unequal widths, nothing hidden: the range reaches the column the rect's right edge is in
    [column(1) setHidden:NO];
    NSRange third = [table columnsInRect:NSMakeRect(0, 0, 260, 20)]; // columns span 0-203, 203-256, 256-339
    CHECK(third.location == 0 && third.length == 3);
    NSRange two = [table columnsInRect:NSMakeRect(0, 0, 250, 20)];
    CHECK(two.location == 0 && two.length == 2);
}

static void test_a_hidden_first_column(void)
{
    setup();
    [column(0) setHidden:YES];
    CHECK([table columnAtPoint:NSMakePoint(10, 5)] == 1);
    CHECK(NSMinX([table rectOfColumn:1]) == 0);
    NSRange all = [table columnsInRect:NSMakeRect(0, 0, 186, 20)];
    CHECK(all.location == 1 && all.length == 2); // starts at a column that is shown
}

static void test_unhiding_restores_the_layout(void)
{
    setup();
    [column(1) setHidden:YES];
    [column(1) setHidden:NO];
    CHECK(NSMinX([table rectOfColumn:2]) == 156);
    CHECK(NSWidth([table rectOfRow:0]) == 239);
}

static void test_size_last_column_to_fit(void)
{
    setup();
    [column(1) setHidden:YES];
    [table sizeLastColumnToFit];
    CGFloat clip = NSWidth([[table superview] bounds]);
    CHECK([column(2) width] == clip - 103 - 3);
    CHECK([column(1) width] == 50);

    // the last column that is shown takes the slack, not the hidden one after it
    setup();
    [column(2) setHidden:YES];
    [table sizeLastColumnToFit];
    clip = NSWidth([[table superview] bounds]);
    CHECK([column(1) width] == clip - 103 - 3);
    CHECK([column(2) width] == 80);
}

static void test_autoresizing_skips_hidden_columns(void)
{
    setup();
    [column(1) setHidden:YES];
    [table sizeToFit]; // shares what the clip view has left between the columns that are shown
    CGFloat clip = NSWidth([[table superview] bounds]);
    CHECK([column(1) width] == 50);
    CHECK([column(0) width] + 3 + [column(2) width] + 3 == clip);
}

static void test_header(void)
{
    setup();
    NSTableHeaderView *header = (NSTableHeaderView *)[table headerView];
    [column(1) setHidden:YES];
    CHECK(NSWidth([header headerRectOfColumn:1]) == 0);
    CHECK(NSMinX([header headerRectOfColumn:2]) == 103);
    CHECK(NSWidth([header headerRectOfColumn:2]) == 83);
    CHECK([header columnAtPoint:NSMakePoint(120, 5)] == 2);
    CHECK([header columnAtPoint:NSMakePoint(10, 5)] == 0);
    CHECK([[header tableView] numberOfColumns] == 3);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_visible_columns_are_unchanged();
        test_a_hidden_column_stays_in_the_table();
        test_rects_close_the_gap();
        test_a_point_is_never_in_a_hidden_column();
        test_ranges_over_whole_rects();
        test_a_hidden_first_column();
        test_unhiding_restores_the_layout();
        test_size_last_column_to_fit();
        test_autoresizing_skips_hidden_columns();
        test_header();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
