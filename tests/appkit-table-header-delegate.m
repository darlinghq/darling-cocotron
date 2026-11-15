// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView header interaction and the delegate methods around it: a click reports
// mouseDownInHeaderOfTableColumn: then didClickTableColumn:, dragging a header cell reorders
// the column with tableView:shouldReorderColumn:toColumn: asked first with -1 and again for the
// new position (a refusal stops the move), moveColumn:toColumn: posts the move notification and
// rejects out-of-range indexes, and double-clicking the divider after a column fits it, taking
// the width from tableView:sizeToFitWidthOfColumn: when the delegate has it. Observed on macOS 26
// and Mojave; the program passes on both.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public
    NSMutableArray *log;
    BOOL refuseReorder;
    CGFloat fitWidth;
    NSDictionary *moveInfo, *resizeInfo;
    NSInteger actions;
}
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 5; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return [NSString stringWithFormat:@"%@ %ld", [c identifier], (long)row];
}
- (void)tableView:(NSTableView *)t mouseDownInHeaderOfTableColumn:(NSTableColumn *)c
{
    [log addObject:[NSString stringWithFormat:@"mouseDown %@", [c identifier]]];
}
- (void)tableView:(NSTableView *)t didClickTableColumn:(NSTableColumn *)c
{
    [log addObject:[NSString stringWithFormat:@"click %@", [c identifier]]];
}
- (BOOL)tableView:(NSTableView *)t shouldReorderColumn:(NSInteger)column toColumn:(NSInteger)newColumn
{
    [log addObject:[NSString stringWithFormat:@"reorder %ld %ld", (long)column, (long)newColumn]];
    return !refuseReorder;
}
- (CGFloat)tableView:(NSTableView *)t sizeToFitWidthOfColumn:(NSInteger)column
{
    [log addObject:[NSString stringWithFormat:@"fit %ld", (long)column]];
    return fitWidth;
}
- (void)tableViewColumnDidMove:(NSNotification *)n { moveInfo = [[n userInfo] retain]; }
- (void)tableViewColumnDidResize:(NSNotification *)n { resizeInfo = [[n userInfo] retain]; }
- (void)clicked:(id)sender { actions++; }
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

static NSPoint inWindow(NSPoint inHeader)
{
    return [[table headerView] convertPoint:inHeader toView:nil];
}

// A point inside a header cell, away from its dividers
static NSPoint cellPoint(NSInteger column)
{
    NSRect r = [(NSTableHeaderView *)[table headerView] headerRectOfColumn:column];
    return NSMakePoint(NSMinX(r) + r.size.width * 0.8, NSMidY(r));
}

static void clickHeader(NSPoint p, NSInteger clicks)
{
    [NSApp postEvent:mouse(NSLeftMouseUp, inWindow(p), clicks) atStart:NO];
    [window sendEvent:mouse(NSLeftMouseDown, inWindow(p), clicks)];
    drain();
}

static void dragHeader(NSPoint from, NSPoint to)
{
    for (int i = 1; i <= 8; i++)
        [NSApp postEvent:mouse(NSLeftMouseDragged, inWindow(NSMakePoint(from.x + (to.x - from.x) * i / 8.0, from.y)), 1) atStart:NO];
    [NSApp postEvent:mouse(NSLeftMouseUp, inWindow(to), 1) atStart:NO];
    [window sendEvent:mouse(NSLeftMouseDown, inWindow(from), 1)];
    drain();
    drain();
}

static NSString *order(void)
{
    NSMutableArray *ids = [NSMutableArray array];
    for (NSTableColumn *c in [table tableColumns])
        [ids addObject:[c identifier]];
    return [ids componentsJoinedByString:@","];
}

static Source *setup(void)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 500, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 500, 250)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 500, 250)] autorelease];
    for (NSString *name in [NSArray arrayWithObjects:@"a", @"b", @"c", nil])
    {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:name] autorelease];
        [column setWidth:100];
        [[column headerCell] setStringValue:name];
        [table addTableColumn:column];
    }
    Source *source = [[[Source alloc] init] autorelease];
    source->log = [[NSMutableArray array] retain];
    source->fitWidth = 150;
    [table setDataSource:source];
    [table setDelegate:source];
    [table setTarget:source];
    [table setAction:@selector(clicked:)];
    [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
    [scroll setDocumentView:table];
    [window setContentView:scroll];
    [window makeKeyAndOrderFront:nil];
    [table reloadData];
    drain();
    [source->log removeAllObjects];
    return source;
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];

        // A header click
        Source *source = setup();
        clickHeader(cellPoint(1), 1);
        expect([source->log containsObject:@"mouseDown b"], @"mouseDownInHeaderOfTableColumn: for the clicked column");
        expect([source->log containsObject:@"click b"], @"didClickTableColumn: for the clicked column");
        expect([source->log indexOfObject:@"mouseDown b"] < [source->log indexOfObject:@"click b"],
               @"the mouse-down is reported before the click");

        // Reordering by dragging
        source = setup();
        dragHeader(cellPoint(0), cellPoint(2));
        expect([order() isEqualToString:@"b,c,a"], @"dragging the first header cell to the last column moves it");
        expect([source->log containsObject:@"reorder 0 -1"], @"the delegate is first asked about the column with -1");
        expect([source->log containsObject:@"reorder 0 2"], @"and again for the position the column reaches");
        expect([[source->moveInfo objectForKey:@"NSOldColumn"] intValue] == 0 &&
                   [[source->moveInfo objectForKey:@"NSNewColumn"] intValue] == 2,
               @"the move notification reports the old and new index");
        expect(![source->log containsObject:@"click a"], @"a drag is not a click");

        source = setup();
        [table setAllowsColumnReordering:NO];
        dragHeader(cellPoint(0), cellPoint(2));
        expect([order() isEqualToString:@"a,b,c"], @"allowsColumnReordering NO keeps the order");

        // Double-click on the divider after the first column
        source = setup();
        NSRect first = [(NSTableHeaderView *)[table headerView] headerRectOfColumn:0];
        clickHeader(NSMakePoint(NSMaxX(first) - 1, NSMidY(first)), 2);
        expect([source->log containsObject:@"fit 0"], @"sizeToFitWidthOfColumn: is asked for the column left of the divider");
        expect([[[table tableColumns] objectAtIndex:0] width] == 150, [NSString stringWithFormat:@"the column takes the delegate's width (is %g)", [[[table tableColumns] objectAtIndex:0] width]]);
        expect([[[source->resizeInfo objectForKey:@"NSTableColumn"] identifier] isEqualToString:@"a"],
               @"the resize notification names the column");
        expect([[source->resizeInfo objectForKey:@"NSOldWidth"] floatValue] == 100, @"and the old width");

        // Programmatic move
        source = setup();
        [table moveColumn:0 toColumn:2];
        expect([order() isEqualToString:@"b,c,a"], @"moveColumn:toColumn: moves the column");
        expect([[source->moveInfo objectForKey:@"NSNewColumn"] intValue] == 2, @"and posts the move notification");
        expect([source->log count] == 0, @"the delegate is not asked about a programmatic move");
        BOOL raised = NO;
        @try { [table moveColumn:0 toColumn:7]; } @catch (NSException *e) { raised = [[e name] isEqualToString:NSRangeException]; }
        expect(raised, @"an out-of-range target raises NSRangeException");

        // Last: on Mojave (i386) a refused drag affects later header clicks in the same process
        source = setup();
        source->refuseReorder = YES;
        dragHeader(cellPoint(0), cellPoint(2));
        expect([order() isEqualToString:@"a,b,c"], @"a delegate that refuses keeps the order");
        expect([source->log containsObject:@"reorder 0 -1"] && ![source->log containsObject:@"reorder 0 2"],
               @"a refusal for -1 ends the question");

        [window close];
    }
    printf("PASS\n");
    return 0;
}
