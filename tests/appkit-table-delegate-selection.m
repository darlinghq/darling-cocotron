// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView consults its delegate for selection the user makes (mouse and arrow keys) but
// not for selection made by the program: tableView:selectionIndexesForProposedSelection:
// takes precedence over tableView:shouldSelectRow:, a refused click keeps the selection but
// still sends the action, arrow keys step over refused rows, and
// tableView:shouldTrackCell:forTableColumn:row: is asked for the clicked cell. Observed on
// macOS 26 and Mojave; the program passes on both.
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
    NSIndexSet *denied;
    BOOL useProposal;
    BOOL filterFive;
    NSInteger actions, actionRow;
    BOOL trackNo;
    BOOL hideProposal, hideShould;
}
@end

@implementation Source
// The delegate offers either selection method, as set before it is assigned
- (BOOL)respondsToSelector:(SEL)selector
{
    if (hideProposal && selector == @selector(tableView:selectionIndexesForProposedSelection:))
        return NO;
    if (hideShould && selector == @selector(tableView:shouldSelectRow:))
        return NO;
    return [super respondsToSelector:selector];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 10; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return [NSString stringWithFormat:@"row %ld", (long)row];
}
- (BOOL)tableView:(NSTableView *)t shouldSelectRow:(NSInteger)row
{
    [log addObject:[NSString stringWithFormat:@"should %ld", (long)row]];
    return ![denied containsIndex:row];
}
- (NSIndexSet *)tableView:(NSTableView *)t selectionIndexesForProposedSelection:(NSIndexSet *)proposed
{
    [log addObject:[NSString stringWithFormat:@"proposed %lu first %lu", (unsigned long)[proposed count], (unsigned long)[proposed firstIndex]]];
    NSMutableIndexSet *result = [[proposed mutableCopy] autorelease];
    if (filterFive)
        [result removeIndex:5];
    return result;
}
- (BOOL)tableView:(NSTableView *)t shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    [log addObject:[NSString stringWithFormat:@"track %@ %@ %ld", NSStringFromClass([cell class]), [c identifier], (long)row]];
    return !trackNo;
}
- (void)clicked:(id)sender { actions++; actionRow = [sender clickedRow]; }
@end

static NSWindow *window;
static NSTableView *table;
static NSInteger serial = 1;

static NSEvent *mouse(NSEventType type, NSPoint p, NSUInteger flags)
{
    return [NSEvent mouseEventWithType:type location:p modifierFlags:flags timestamp:[[NSProcessInfo processInfo] systemUptime]
                          windowNumber:[window windowNumber] context:nil eventNumber:serial++ clickCount:1 pressure:1.0];
}

static void drain(void)
{
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                         inMode:NSDefaultRunLoopMode dequeue:YES]) != nil)
        [NSApp sendEvent:event];
}

// The mouse-up goes in first so that a tracking loop in mouseDown finds it
static void click(NSInteger row, NSUInteger flags)
{
    NSRect cell = [table frameOfCellAtColumn:0 row:row];
    NSPoint p = [table convertPoint:NSMakePoint(NSMidX(cell), NSMidY(cell)) toView:nil];
    [NSApp postEvent:mouse(NSLeftMouseUp, p, flags) atStart:NO];
    [window sendEvent:mouse(NSLeftMouseDown, p, flags)];
    drain();
}

static void arrow(unichar key, unsigned short code)
{
    NSString *s = [NSString stringWithCharacters:&key length:1];
    [window sendEvent:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0 timestamp:[[NSProcessInfo processInfo] systemUptime]
                                   windowNumber:[window windowNumber] context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:code]];
    drain();
}

static Source *setup(BOOL multiple, BOOL proposal, BOOL should)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [column setWidth:300];
    [table addTableColumn:column];
    Source *source = [[[Source alloc] init] autorelease];
    source->log = [NSMutableArray array];
    [source->log retain];
    source->hideProposal = !proposal;
    source->hideShould = !should;
    [table setDataSource:source];
    [table setDelegate:source];
    [table setTarget:source];
    [table setAction:@selector(clicked:)];
    [table setAllowsMultipleSelection:multiple];
    [scroll setDocumentView:table];
    [window setContentView:scroll];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:table];
    [table reloadData];
    [table deselectAll:nil];
    drain();
    [source->log removeAllObjects];
    return source;
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];

        // A program's own selection is not subject to the delegate
        Source *source = setup(NO, NO, YES);
        source->denied = [NSIndexSet indexSetWithIndex:3];
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];
        expect([table selectedRow] == 3, @"programmatic selection ignores the delegate");
        expect([source->log count] == 0, @"no selection delegate method is called for programmatic selection");

        // A click: the delegate is asked about the proposal, rows it refuses are not selected
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
        [source->log removeAllObjects];
        source->actions = 0;
        click(4, 0);
        expect([table selectedRow] == 4, @"click selects an allowed row");
        expect(source->actions == 1, @"the action is sent");
        click(3, 0);
        expect([table selectedRow] == 4, @"a click on a refused row keeps the selection");
        expect(source->actionRow == 3, @"the refused click is still the clicked row");
        expect(source->actions == 2, @"the action is sent for a refused click");

        // The delegate is asked for the clicked cell
        [source->log removeAllObjects];
        click(6, 0);
        expect([source->log containsObject:@"track NSTextFieldCell name 6"], @"shouldTrackCell is asked with the clicked cell");
        expect([table selectedRow] == 6, @"a cell that is not tracked selects its row");

        // Arrow keys step over refused rows
        source->denied = [NSIndexSet indexSetWithIndex:7];
        arrow(NSDownArrowFunctionKey, 125);
        expect([table selectedRow] == 8, @"down arrow skips the refused row 7");
        arrow(NSUpArrowFunctionKey, 126);
        expect([table selectedRow] == 6, @"up arrow skips the refused row 7");

        // selectionIndexesForProposedSelection: replaces shouldSelectRow: when both exist. Both
        // are offered by the same delegate here, so the proposal method must win.
        source = setup(YES, YES, YES);
        source->filterFive = YES;
        source->denied = [NSIndexSet indexSetWithIndex:2];
        click(2, 0);
        expect([table selectedRow] == 2, @"the proposal is accepted whatever shouldSelectRow: would say");
        BOOL askedShould = NO;
        for (NSString *entry in source->log)
            if ([entry hasPrefix:@"should "])
                askedShould = YES;
        expect(!askedShould, @"shouldSelectRow: is not called when the proposal method exists");
        expect([source->log containsObject:@"proposed 1 first 2"], @"the proposal holds the clicked row");

        // Rows removed from a proposal are not selected; moving past one lands on the next row
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
        arrow(NSDownArrowFunctionKey, 125);
        expect([table selectedRow] == 6, @"a keyboard move goes past the removed row 5");

        // Shift extends: the delegate sees the whole proposed range and may trim it
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
        [source->log removeAllObjects];
        click(7, NSShiftKeyMask);
        expect([table isRowSelected:7] && [table isRowSelected:6] && ![table isRowSelected:5],
               @"the extended selection lacks the removed row");
        expect([source->log containsObject:@"proposed 4 first 4"], @"the proposal covers the shift-click range");

        [window close];
    }
    printf("PASS\n");
    return 0;
}
