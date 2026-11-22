// Copyright (C) 2026 Lubos Dolezel
//
// Clicking table column headers builds the table's sortDescriptors from the columns' sort
// descriptor prototypes. The contract used here is NSMutableArray's: removeObject: removes every
// element that isEqual: the argument
// (https://developer.apple.com/documentation/foundation/nsmutablearray/remove(_:)), so a column
// whose descriptor is already in the table's list must be replaced by position, or clicking
// A, then B, then A again loses A. The ordering rule itself (the clicked column's descriptor goes
// first, and is reversed when it was already first) is not in the public documentation and is the
// behaviour the table already had; the test keeps it as it was (GUESS, test_click_order).
// Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-table-column-sort-clicks.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Source : NSObject <NSTableViewDataSource>
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 2; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row { return @"x"; }
@end

static NSWindow *window;
static NSTableView *table;
static NSInteger serial = 1;

static NSEvent *mouse(NSEventType type, NSPoint p)
{
    return [NSEvent mouseEventWithType:type location:p modifierFlags:0 timestamp:[[NSProcessInfo processInfo] systemUptime]
                          windowNumber:[window windowNumber] context:nil eventNumber:serial++ clickCount:1 pressure:1.0];
}

static void drain(void)
{
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                         inMode:NSDefaultRunLoopMode dequeue:YES]) != nil)
        [NSApp sendEvent:event];
}

// A click inside the header cell of a column, away from its dividers
static void clickHeader(NSInteger column)
{
    NSRect r = [(NSTableHeaderView *)[table headerView] headerRectOfColumn:column];
    NSPoint p = [[table headerView] convertPoint:NSMakePoint(NSMinX(r) + r.size.width * 0.8, NSMidY(r)) toView:nil];
    [NSApp postEvent:mouse(NSLeftMouseUp, p) atStart:NO];
    [window sendEvent:mouse(NSLeftMouseDown, p)];
    drain();
}

static NSString *state(void)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSSortDescriptor *d in [table sortDescriptors])
        [parts addObject:[NSString stringWithFormat:@"%@%@", [d key], [d ascending] ? @"+" : @"-"]];
    return [parts componentsJoinedByString:@" "];
}

static void setup(void)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    for (NSString *name in [NSArray arrayWithObjects:@"a", @"b", @"c", nil])
    {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:name] autorelease];
        [column setWidth:100];
        [column setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:name ascending:YES]];
        [table addTableColumn:column];
    }
    [table setDataSource:[[[Source alloc] init] autorelease]];
    [scroll setDocumentView:table];
    [window setContentView:scroll];
    [window makeKeyAndOrderFront:nil];
    [table reloadData];
    drain();
}

static void test_click_order(void)
{
    setup();
    clickHeader(0);
    CHECK([state() isEqualToString:@"a+"]);
    clickHeader(1);
    CHECK([state() isEqualToString:@"b+ a+"]);
    clickHeader(1);
    CHECK([state() isEqualToString:@"b- a+"]); // already first: reversed
}

static void test_a_b_a_keeps_both_descriptors(void)
{
    setup();
    clickHeader(0);
    clickHeader(1);
    clickHeader(0);
    CHECK([[table sortDescriptors] count] == 2);
    CHECK([state() isEqualToString:@"a+ b+"]);
}

static void test_a_b_c_a_b(void)
{
    setup();
    clickHeader(0);
    clickHeader(1);
    clickHeader(2);
    clickHeader(0);
    CHECK([state() isEqualToString:@"a+ c+ b+"]);
    clickHeader(1);
    CHECK([state() isEqualToString:@"b+ a+ c+"]);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_click_order();
        test_a_b_a_keeps_both_descriptors();
        test_a_b_c_a_b();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
