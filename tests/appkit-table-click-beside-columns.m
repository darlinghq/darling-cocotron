// Copyright (C) 2026 Lubos Dolezel
//
// A click on a row of an NSTableView at a point to the right of the last column. The contract is
// the documentation of -[NSTableView clickedColumn]
// (https://developer.apple.com/documentation/appkit/nstableview/clickedcolumn), which reports -1
// for a click where no column lies. Such a click must not raise (it used to index the column
// array with -1), and clickedRow is still the row. The rest was observed on macOS 26.7.3 by delivering
// clicks to a table in a borderless window with -[NSWindow sendEvent:]: a click beside the columns
// selects the row and sends the action (clickedRow the row, clickedColumn -1); a double click also sends the
// double action and starts no edit; the delegate is not asked whether to track a cell there, while a click in a
// column asks once per click; a click below the last row clears the selection. That is possible because the
// table is as wide and as tall as its clip view after -reloadData, however narrow its columns are.
// Build: clang -framework AppKit appkit-table-click-beside-columns.m (no ARC)
// Build: clang -framework AppKit appkit-table-click-beside-columns.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public
    int actions, doubleActions, edits, tracks;
    NSInteger actionColumn, actionRow;
}
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 5; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row { return @"x"; }
- (void)tableView:(NSTableView *)t setObjectValue:(id)object forTableColumn:(NSTableColumn *)c row:(NSInteger)row { edits++; }
- (BOOL)tableView:(NSTableView *)t shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    tracks++;
    return NO;
}
- (void)clicked:(id)sender { actions++; actionColumn = [sender clickedColumn]; actionRow = [sender clickedRow]; }
- (void)doubleClicked:(id)sender { doubleActions++; actionColumn = [sender clickedColumn]; actionRow = [sender clickedRow]; }
@end

static NSWindow *window;
static NSTableView *table;
static NSInteger serial = 1;

static NSEvent *mouse(NSEventType type, NSPoint p, NSInteger clicks)
{
    return [NSEvent mouseEventWithType:type location:p modifierFlags:0 timestamp:[[NSProcessInfo processInfo] systemUptime]
                          windowNumber:[window windowNumber] context:nil eventNumber:serial++ clickCount:clicks pressure:1.0];
}

static void drain(void)
{
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                         inMode:NSDefaultRunLoopMode dequeue:YES]) != nil)
        [NSApp sendEvent:event];
}

// The mouse-up goes in first so that a tracking loop in mouseDown finds it
static void click(NSPoint inTable, NSInteger clicks)
{
    NSPoint p = [table convertPoint:inTable toView:nil];
    [NSApp postEvent:mouse(NSLeftMouseUp, p, clicks) atStart:NO];
    [window sendEvent:mouse(NSLeftMouseDown, p, clicks)];
    drain();
}

static Source *setup(void)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [column setWidth:100];
    [column setEditable:YES];
    [table addTableColumn:column];
    [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
    Source *source = [[[Source alloc] init] autorelease];
    [table setDataSource:source];
    [table setDelegate:source];
    [table setTarget:source];
    [table setAction:@selector(clicked:)];
    [table setDoubleAction:@selector(doubleClicked:)];
    [scroll setDocumentView:table];
    [window setContentView:scroll];
    [window makeKeyAndOrderFront:nil];
    [table reloadData];
    [table deselectAll:nil];
    drain();
    return source;
}

// The middle of a row, 250 points from the left: right of the 100 point column
static NSPoint beside(NSInteger row)
{
    NSRect r = [table rectOfRow:row];
    return NSMakePoint(250, NSMidY(r));
}

static void test_the_table_is_as_wide_as_its_clip_view(void)
{
    setup();
    NSRect clip = [[[table enclosingScrollView] contentView] bounds];
    CHECK(NSWidth([table frame]) >= NSWidth(clip) && NSHeight([table frame]) >= NSHeight(clip));
    CHECK(NSWidth([table frame]) > [[[table tableColumns] objectAtIndex:0] width]);
}

static void test_click_beside_the_columns(void)
{
    Source *source = setup();
    CHECK([table columnAtPoint:beside(2)] == -1);
    click(beside(2), 1);
    CHECK([table selectedRow] == 2);
    CHECK(source->actions == 1 && source->actionColumn == -1 && source->actionRow == 2);
}

static void test_the_delegate_is_not_asked_to_track_a_missing_cell(void)
{
    Source *source = setup();
    click(beside(1), 1);
    CHECK(source->tracks == 0);
    click(NSMakePoint(50, NSMidY([table rectOfRow:1])), 1);
    CHECK(source->tracks == 1); // a click in the column still asks
}

static void test_double_click_beside_the_columns(void)
{
    Source *source = setup();
    click(beside(3), 1);
    click(beside(3), 2);
    CHECK(source->doubleActions == 1);
    CHECK(source->actionColumn == -1 && source->actionRow == 3);
    CHECK([table editedRow] == -1); // nothing to edit
}

static void test_a_click_in_the_column_is_unchanged(void)
{
    Source *source = setup();
    click(NSMakePoint(50, NSMidY([table rectOfRow:1])), 1);
    CHECK([table selectedRow] == 1);
    CHECK(source->actions == 1 && source->actionColumn == 0 && source->actionRow == 1);
}

// QUIRK pinned: clickedRow and clickedColumn are meaningful inside the action and double action messages
// (the documentation of -[NSTableView clickedRow]) and are -1 once the click returned, and on a table that has not
// been clicked; observed on macOS 26.7.3 by running this test there.
static void test_clicked_row_and_column_are_reset_after_the_click(void)
{
    Source *source = setup();
    CHECK([table clickedRow] == -1 && [table clickedColumn] == -1); // no click yet
    click(NSMakePoint(50, NSMidY([table rectOfRow:1])), 1);
    CHECK(source->actions == 1 && source->actionRow == 1 && source->actionColumn == 0); // valid inside the action
    CHECK([table clickedRow] == -1);
    CHECK([table clickedColumn] == -1);

    // Not editable, so that the double click is a double action and not the start of an edit
    [[[table tableColumns] objectAtIndex:0] setEditable:NO];
    click(NSMakePoint(50, NSMidY([table rectOfRow:2])), 1);
    click(NSMakePoint(50, NSMidY([table rectOfRow:2])), 2); // the second click of a double click
    CHECK(source->actions == 2 && source->doubleActions == 1);
    CHECK(source->actionRow == 2 && source->actionColumn == 0); // valid inside the double action
    CHECK([table clickedRow] == -1);
    CHECK([table clickedColumn] == -1);
}

static void test_a_click_below_the_rows_still_clears_the_selection(void)
{
    setup();
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    click(NSMakePoint(50, NSMaxY([table rectOfRow:4]) + 20), 1);
    CHECK([table selectedRow] == -1);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_the_table_is_as_wide_as_its_clip_view();
        test_click_beside_the_columns();
        test_the_delegate_is_not_asked_to_track_a_missing_cell();
        test_double_click_beside_the_columns();
        test_a_click_in_the_column_is_unchanged();
        test_clicked_row_and_column_are_reset_after_the_click();
        test_a_click_below_the_rows_still_clears_the_selection();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
