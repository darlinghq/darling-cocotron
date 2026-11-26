// Copyright (C) 2026 Lubos Dolezel
//
// A click on a column header of an NSTableView and the table's action. The documentation of -[NSTableView
// doubleAction] (https://developer.apple.com/documentation/appkit/nstableview/doubleaction) lists a double click on
// a column header among the clicks that send the double action, and says clickedRow and clickedColumn tell the
// header from a cell; so a double click on a header sends the double action, with clickedRow -1 and clickedColumn the
// column. That a single click on a header sends the action is not documented: it was observed on macOS 26.1 arm64
// (probe 659, black-box, synthetic events through -[NSApp sendEvent:]): over column 0 the calls were
// `mouseDownInHeaderOfTableColumn(c0) didClickTableColumn(c0) action(clickedRow=-1,clickedColumn=0,selectedRow=-1)`,
// and at click count 2 the same three calls ending in `doubleAction(clickedRow=-1,clickedColumn=0,selectedRow=-1)`.
// Right of the last column nothing is sent. On the divider at the end of column 0 only
// `mouseDownInHeaderOfTableColumn(c0)` is sent, once per click, and no action, also at click count 2.
// Build: clang -framework AppKit appkit-table-header-click-action.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public
    NSMutableArray *log;
    NSInteger actionRow, actionColumn;
}
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 5; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row { return @"x"; }
- (void)tableView:(NSTableView *)t mouseDownInHeaderOfTableColumn:(NSTableColumn *)c
{
    [log addObject:[NSString stringWithFormat:@"mouseDown %@", [c identifier]]];
}
- (void)tableView:(NSTableView *)t didClickTableColumn:(NSTableColumn *)c
{
    [log addObject:[NSString stringWithFormat:@"click %@", [c identifier]]];
}
- (void)clicked:(id)sender
{
    [log addObject:@"action"];
    actionRow = [sender clickedRow];
    actionColumn = [sender clickedColumn];
}
- (void)doubleClicked:(id)sender
{
    [log addObject:@"doubleAction"];
    actionRow = [sender clickedRow];
    actionColumn = [sender clickedColumn];
}
- (void)dealloc
{
    [log release];
    [super dealloc];
}
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

// The mouse-up goes in first so that a tracking loop in the header's mouseDown finds it
static void clickHeader(NSPoint inHeader, NSInteger clicks)
{
    NSPoint p = [[table headerView] convertPoint:inHeader toView:nil];
    [NSApp postEvent:mouse(NSLeftMouseUp, p, clicks) atStart:NO];
    [window sendEvent:mouse(NSLeftMouseDown, p, clicks)];
    drain();
}

static NSRect headerRect(NSInteger column)
{
    return [(NSTableHeaderView *)[table headerView] headerRectOfColumn:column];
}

// Over column 0, away from its dividers
static NSPoint overColumn0(void)
{
    NSRect r = headerRect(0);
    return NSMakePoint(NSMinX(r) + r.size.width * 0.5, NSMidY(r));
}

static Source *setup(void)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 500, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 500, 250)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 500, 250)] autorelease];
    for (NSString *name in [NSArray arrayWithObjects:@"c0", @"c1", nil])
    {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:name] autorelease];
        [column setWidth:100];
        [table addTableColumn:column];
    }
    [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
    Source *source = [[[Source alloc] init] autorelease];
    source->log = [[NSMutableArray array] retain];
    source->actionRow = source->actionColumn = 99; // anything but -1, so that a value read in the action shows
    [table setDataSource:source];
    [table setDelegate:source];
    [table setTarget:source];
    [table setAction:@selector(clicked:)];
    [table setDoubleAction:@selector(doubleClicked:)];
    [scroll setDocumentView:table];
    [window setContentView:scroll];
    [window makeKeyAndOrderFront:nil];
    [table reloadData];
    drain();
    [source->log removeAllObjects];
    return source;
}

static NSString *calls(Source *source)
{
    return [source->log componentsJoinedByString:@","];
}

static void test_a_header_click_sends_the_action(void)
{
    Source *source = setup();
    clickHeader(overColumn0(), 1);
    CHECK([calls(source) isEqualToString:@"mouseDown c0,click c0,action"]);
    CHECK(source->actionRow == -1 && source->actionColumn == 0); // read inside the action
    CHECK([table clickedRow] == -1 && [table clickedColumn] == -1);
    CHECK([table selectedRow] == -1);
}

static void test_a_double_click_on_a_header_sends_the_double_action(void)
{
    Source *source = setup();
    clickHeader(overColumn0(), 1);
    [source->log removeAllObjects];
    source->actionRow = source->actionColumn = 99;
    clickHeader(overColumn0(), 2);
    CHECK([calls(source) isEqualToString:@"mouseDown c0,click c0,doubleAction"]);
    CHECK(source->actionRow == -1 && source->actionColumn == 0);
    CHECK([table clickedRow] == -1 && [table clickedColumn] == -1);
}

static void test_the_second_column_reports_its_own_index(void)
{
    Source *source = setup();
    NSRect r = headerRect(1);
    clickHeader(NSMakePoint(NSMinX(r) + r.size.width * 0.5, NSMidY(r)), 1);
    CHECK([calls(source) isEqualToString:@"mouseDown c1,click c1,action"]);
    CHECK(source->actionRow == -1 && source->actionColumn == 1);
}

static void test_a_click_right_of_the_last_column_sends_nothing(void)
{
    Source *source = setup();
    NSRect last = headerRect(1);
    NSPoint beside = NSMakePoint(NSMaxX(last) + 20, NSMidY(last));
    clickHeader(beside, 1);
    clickHeader(beside, 2);
    CHECK([source->log count] == 0);
}

static void test_a_click_on_the_divider_sends_no_action(void)
{
    Source *source = setup();
    NSRect first = headerRect(0);
    NSPoint divider = NSMakePoint(NSMaxX(first) - 0.5, NSMidY(first));
    clickHeader(divider, 1);
    CHECK([calls(source) isEqualToString:@"mouseDown c0"]);
    [source->log removeAllObjects];
    // A click on the divider ends in the column being sized (to the pointer, or to its contents), which moves the
    // divider, so the second click goes to where it is now.
    first = headerRect(0);
    divider = NSMakePoint(NSMaxX(first) - 0.5, NSMidY(first));
    clickHeader(divider, 2);
    CHECK([calls(source) isEqualToString:@"mouseDown c0"]);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_a_header_click_sends_the_action();
        test_a_double_click_on_a_header_sends_the_double_action();
        test_the_second_column_reports_its_own_index();
        test_a_click_right_of_the_last_column_sends_nothing();
        test_a_click_on_the_divider_sends_no_action();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
