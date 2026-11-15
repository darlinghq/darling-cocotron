// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView type select: typing selects a row whose text begins with the typed string.
// The delegate can veto an event (tableView:shouldTypeSelectForEvent:withCurrentSearchString:),
// supply the row text (tableView:typeSelectStringForTableColumn:row:) or do the search itself
// (tableView:nextTypeSelectMatchFromRow:toRow:forString:, the range including the start row
// and excluding the end row). Modifier shortcuts and allowsTypeSelect NO do not type select.
// Observed on macOS 26 and Mojave; the program passes on both. The pause that ends a search is
// not tested.
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
    NSArray *names;
    NSMutableArray *log;
    BOOL hideString, hideShould, hideNext;
    BOOL vetoEvents;
    NSInteger nextRow;
}
@end

@implementation Source
- (BOOL)respondsToSelector:(SEL)selector
{
    if (hideString && selector == @selector(tableView:typeSelectStringForTableColumn:row:))
        return NO;
    if (hideShould && selector == @selector(tableView:shouldTypeSelectForEvent:withCurrentSearchString:))
        return NO;
    if (hideNext && selector == @selector(tableView:nextTypeSelectMatchFromRow:toRow:forString:))
        return NO;
    return [super respondsToSelector:selector];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return [names count]; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return [names objectAtIndex:row];
}
- (NSString *)tableView:(NSTableView *)t typeSelectStringForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return [@"z" stringByAppendingString:[names objectAtIndex:row]];
}
- (BOOL)tableView:(NSTableView *)t shouldTypeSelectForEvent:(NSEvent *)event withCurrentSearchString:(NSString *)s
{
    [log addObject:[NSString stringWithFormat:@"should %@ %@", [event characters], s ? s : @"(nil)"]];
    return !vetoEvents;
}
- (NSInteger)tableView:(NSTableView *)t nextTypeSelectMatchFromRow:(NSInteger)start toRow:(NSInteger)end forString:(NSString *)s
{
    [log addObject:[NSString stringWithFormat:@"next %ld %ld %@", (long)start, (long)end, s]];
    return nextRow;
}
@end

static NSWindow *window;
static NSTableView *table;

static void drain(void)
{
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                         inMode:NSDefaultRunLoopMode dequeue:YES]) != nil)
        [NSApp sendEvent:event];
}

static void key(NSString *characters, unsigned short code, NSUInteger flags)
{
    [window sendEvent:[NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags timestamp:[[NSProcessInfo processInfo] systemUptime]
                                   windowNumber:[window windowNumber] context:nil characters:characters charactersIgnoringModifiers:characters
                                      isARepeat:NO keyCode:code]];
    drain();
}

static Source *setup(BOOL hideString, BOOL hideShould, BOOL hideNext)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 250)] autorelease];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 250)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [column setWidth:250];
    [table addTableColumn:column];
    Source *source = [[[Source alloc] init] autorelease];
    source->names = [[NSArray arrayWithObjects:@"Alpha", @"Bravo", @"Charlie", @"Delta", @"Echo", @"Foxtrot", @"Golf", @"Hotel", @"India", @"Juliet", nil] retain];
    source->log = [[NSMutableArray array] retain];
    source->hideString = hideString;
    source->hideShould = hideShould;
    source->hideNext = hideNext;
    source->nextRow = -1;
    [table setDataSource:source];
    [table setDelegate:source];
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

        // The text of the cells decides without any delegate help
        Source *source = setup(YES, YES, YES);
        expect([table allowsTypeSelect], @"type select is on by default");
        key(@"d", 2, 0);
        expect([table selectedRow] == 3, @"typing d selects Delta");
        key(@"e", 14, 0);
        expect([table selectedRow] == 3, @"the typed string continues: de still matches Delta");
        key(@"c", 8, 0);
        expect([table selectedRow] == 3, @"a string that matches nothing keeps the selection");

        // Case is ignored; the search starts after the selected row and wraps
        setup(YES, YES, YES);
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:6] byExtendingSelection:NO];
        key(@"C", 8, NSShiftKeyMask);
        expect([table selectedRow] == 2, @"c after row 6 wraps around to Charlie");

        // Shortcuts and the property switch it off
        setup(YES, YES, YES);
        key(@"c", 8, NSCommandKeyMask);
        expect([table selectedRow] == -1, @"command+c does not type select");
        [table setAllowsTypeSelect:NO];
        key(@"c", 8, 0);
        expect([table selectedRow] == -1, @"allowsTypeSelect NO does not type select");

        // The delegate supplies the text
        source = setup(NO, YES, YES);
        key(@"z", 6, 0);
        expect([table selectedRow] == 0, @"the delegate's strings (z-prefixed) are searched");

        // The delegate vetoes an event, and sees the current search string
        source = setup(YES, NO, YES);
        source->vetoEvents = YES;
        key(@"c", 8, 0);
        expect([table selectedRow] == -1, @"a vetoed event does not select");
        expect([source->log containsObject:@"should c (nil)"], @"the search string is nil before a search began");
        source->vetoEvents = NO;
        key(@"c", 8, 0);
        key(@"h", 4, 0);
        expect([source->log containsObject:@"should h c"], @"the search string so far is passed on");

        // The delegate searches itself: the range starts at the row after the selection and ends at the selection
        source = setup(YES, YES, NO);
        source->nextRow = 4;
        key(@"c", 8, 0);
        expect([source->log containsObject:@"next 0 0 c"], @"without a selection the range is 0 to 0");
        expect([table selectedRow] == 4, @"the row the delegate names is selected");
        setup(YES, YES, NO);
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:6] byExtendingSelection:NO];
        key(@"c", 8, 0);
        // (a new Source is in use here; its log is reached through the table's delegate)
        Source *current = [table delegate];
        expect([current->log containsObject:@"next 7 6 c"], @"with row 6 selected a new search runs from 7 to 6");

        [window close];
    }
    printf("PASS\n");
    return 0;
}
