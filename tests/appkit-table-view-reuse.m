// Copyright (C) 2026 Lubos Dolezel
//
// View-based NSTableView: the delegate is asked for a cell's view when it becomes visible
// (not on every draw), viewAtColumn:row:makeIfNecessary: returns the view in place or makes it,
// the views in the table stay bounded however often it is reloaded and redrawn, and views that
// left the table wait for makeViewWithIdentifier:owner:, including views the delegate made
// itself and gave an identifier. Observed on macOS 26 and Mojave; the program passes on both.
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
    NSInteger created, requested, rows;
    BOOL useQueue;
    NSMutableArray *made;
}
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return rows; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    requested++;
    NSTextField *field = useQueue ? [t makeViewWithIdentifier:@"cell" owner:self] : nil;
    if (field == nil)
    {
        field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)] autorelease];
        [field setIdentifier:@"cell"];
        created++;
        [made addObject:field];
    }
    [field setStringValue:[NSString stringWithFormat:@"row %ld", (long)row]];
    return field;
}
@end

static void drain(void)
{
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                         inMode:NSDefaultRunLoopMode dequeue:YES]) != nil)
        [NSApp sendEvent:event];
}

static NSWindow *window;
static NSTableView *table;

static Source *setup(BOOL useQueue)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 200) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"a"] autorelease];
    [column setWidth:300];
    [table addTableColumn:column];
    [table setRowHeight:20];
    Source *source = [[[Source alloc] init] autorelease];
    source->rows = 100;
    source->useQueue = useQueue;
    source->made = [[NSMutableArray array] retain];
    [table setDataSource:source];
    [table setDelegate:source];
    [scroll setHasVerticalScroller:YES];
    [scroll setDocumentView:table];
    [window setContentView:scroll];
    [window makeKeyAndOrderFront:nil];
    [table reloadData];
    drain();
    [window display];
    return source;
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];

        Source *source = setup(NO);
        expect(source->created > 0 && source->created < 40, @"only the visible cells have views");

        // The view of a visible cell is in place; an invisible one is made on request
        NSView *visible = [table viewAtColumn:0 row:0 makeIfNecessary:NO];
        expect(visible != nil, @"a visible cell has its view");
        NSInteger before = source->requested;
        expect([table viewAtColumn:0 row:0 makeIfNecessary:YES] == visible, @"asking again returns the same view");
        expect(source->requested == before, @"a view in place is not requested again");
        expect([table viewAtColumn:0 row:50 makeIfNecessary:NO] == nil, @"a cell far below has no view yet");
        expect(source->requested == before, @"asking without making does not call the delegate");
        NSView *made = [table viewAtColumn:0 row:50 makeIfNecessary:YES];
        expect(made != nil && source->requested == before + 1, @"making calls the delegate once");
        expect([table rowForView:made] == 50, @"and the view is at its row");
        expect([table viewAtColumn:0 row:50 makeIfNecessary:NO] == made, @"it stays in place");

        // Bad indexes raise, as on macOS
        BOOL rowRaised = NO, columnRaised = NO;
        @try { [table viewAtColumn:0 row:100 makeIfNecessary:NO]; } @catch (NSException *e) { rowRaised = [[e name] isEqualToString:@"NSTableViewException"]; }
        @try { [table viewAtColumn:0 row:-1 makeIfNecessary:YES]; } @catch (NSException *e) { rowRaised = rowRaised && [[e name] isEqualToString:@"NSTableViewException"]; }
        @try { [table viewAtColumn:1 row:0 makeIfNecessary:NO]; } @catch (NSException *e) { columnRaised = [[e name] isEqualToString:NSInternalInconsistencyException]; }
        expect(rowRaised, @"a row outside the table raises NSTableViewException");
        expect(columnRaised, @"a column beyond the columns raises NSInternalInconsistencyException");

        // Redrawing does not stack views up, nor does reloading
        for (int i = 0; i < 5; i++)
        {
            [table setNeedsDisplay:YES];
            [window display];
        }
        NSUInteger settled = [[table subviews] count];
        for (int i = 0; i < 20; i++)
        {
            [table reloadData];
            drain();
            [window display];
        }
        expect([[table subviews] count] <= 100, @"the views in the table stay bounded across reloads");
        expect([[table subviews] count] <= settled + 12, @"the subview count does not grow with every reload");
        expect([table makeViewWithIdentifier:@"unknown" owner:nil] == nil, @"an identifier with no queue and no nib gives nil");

        // Views scrolled out wait in the queue, delegate-made ones included
        source = setup(NO);
        [table scrollRowToVisible:60];
        drain();
        [window display];
        NSView *queued = [table makeViewWithIdentifier:@"cell" owner:nil];
        expect(queued != nil, @"a view that scrolled out can be made again");
        expect([queued superview] == nil, @"it is not in the table any more");
        expect([source->made containsObject:queued], @"it is one the delegate created");
        NSView *second = [table makeViewWithIdentifier:@"cell" owner:nil];
        expect(second != queued, @"a view is handed out once");

        // Reuse through makeViewWithIdentifier:owner: while scrolling through the table
        source = setup(YES);
        for (int row = 0; row < 100; row += 10)
        {
            [table scrollRowToVisible:row];
            drain();
            [window display];
        }
        [table scrollRowToVisible:99];
        drain();
        [window display];
        expect(source->created <= 100, @"the views made stay below the number of rows");

        // A delegate that reuses views through makeViewWithIdentifier:owner: keeps the table bounded
        // while it is redrawn and reloaded repeatedly (two columns, a few rows)
        source = setup(YES);
        source->rows = 6;
        NSTableColumn *extraColumn = [[[NSTableColumn alloc] initWithIdentifier:@"b"] autorelease];
        [extraColumn setWidth:50];
        [table addTableColumn:extraColumn];
        [table reloadData];
        drain();
        [window display];
        for (int round = 0; round < 5; round++)
        {
            for (int draw = 0; draw < 4; draw++)
            {
                [table setNeedsDisplay:YES];
                [window display];
            }
            [table reloadData];
            drain();
        }
        [window display];
        NSUInteger cellViews = 0;
        for (NSView *subview in [table subviews])
            if ([subview isKindOfClass:[NSTextField class]])
                cellViews++;
        expect(cellViews <= 12, @"at most one view per cell stays in the table");

        [window close];
    }
    printf("PASS\n");
    return 0;
}
