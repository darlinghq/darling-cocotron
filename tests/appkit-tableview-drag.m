// CFLAGS: -framework Foundation -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// A view-based NSTableView as a drop target and a dragging source, with the data source's pasteboard-writer API,
// without a real drag. The destination is driven through its NSDraggingDestination methods with a stand-in
// NSDraggingInfo; the source through mouse events sent to the window, a subclass recording
// -beginDraggingSessionWithItems:event:source: instead of starting the session.
// - A row's top quarter proposes a drop above it, its middle a drop on it and its bottom quarter a drop above the next
//   row; below the rows, a drop above the row count; in an empty table, above row 0.
// - setDropRow:dropOperation: in validateDrop changes what acceptDrop gets; validateDrop answering None is the
//   destination's answer.
// - tableView:pasteboardWriterForRow: is used over tableView:writeRowsWithIndexes:toPasteboard:; the dragged rows'
//   writers become the session's items; the session's end goes to tableView:draggingSession:endedAtPoint:operation:.
// The rows are 20 points high with the default 2-point spacing, so 22 apart. Observed on macOS 26.7.3 and 10.14.4,
// where it passes unchanged (the mouse-driven cases need a window server session, which 10.14.4 over ssh lacks).
// Needs a display. Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

static NSMutableArray<NSString *> *calls;

enum { ALLOW, RETARGET, REFUSE };

@interface Info : NSObject <NSDraggingInfo>
@property NSPoint location;
@property NSWindow *window;
@property NSPasteboard *pasteboard;
@end

@implementation Info
@synthesize draggingFormation, animatesToDestination, numberOfValidItemsForDrop;
- (NSWindow *)draggingDestinationWindow { return _window; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationEvery; }
- (NSPoint)draggingLocation { return _location; }
- (NSPoint)draggedImageLocation { return _location; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (id)draggingSource { return nil; }
- (NSInteger)draggingSequenceNumber { return 1; }
- (void)slideDraggedImageTo:(NSPoint)point {}
- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)destination { return nil; }
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)options forView:(NSView *)view classes:(NSArray *)classes
                            searchOptions:(NSDictionary *)searchOptions usingBlock:(void (^)(NSDraggingItem *, NSInteger, BOOL *))block {}
- (NSSpringLoadingHighlight)springLoadingHighlight { return NSSpringLoadingHighlightNone; }
- (void)resetSpringLoading {}
@end

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property NSInteger rows;
@property int mode;
@property BOOL oldAPI;
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return _rows; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return [NSTextField labelWithString: [NSString stringWithFormat: @"row %ld", (long) row]];
}
- (NSDragOperation)tableView:(NSTableView *)table validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    [calls addObject: [NSString stringWithFormat: @"validate %ld %s", (long) row, operation == NSTableViewDropOn ? "on" : "above"]];
    if (_mode == RETARGET)
        [table setDropRow: 4 dropOperation: NSTableViewDropAbove];
    return _mode == REFUSE ? NSDragOperationNone : NSDragOperationCopy;
}
- (BOOL)tableView:(NSTableView *)table acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    [calls addObject: [NSString stringWithFormat: @"accept %ld %s", (long) row, operation == NSTableViewDropOn ? "on" : "above"]];
    return YES;
}
- (id<NSPasteboardWriting>)tableView:(NSTableView *)table pasteboardWriterForRow:(NSInteger)row
{
    [calls addObject: [NSString stringWithFormat: @"writer %ld", (long) row]];
    return [NSURL fileURLWithPath: [NSString stringWithFormat: @"/private/var/tmp/row-%ld", (long) row]];
}
- (BOOL)tableView:(NSTableView *)table writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard
{
    [calls addObject: @"writeRows"];
    return YES;
}
- (void)tableView:(NSTableView *)table draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation
{
    [calls addObject: [NSString stringWithFormat: @"ended %lu", (unsigned long) operation]];
}
@end

@interface RecordingTable : NSTableView {
@public
    NSArray<NSDraggingItem *> *draggingItems;
}
@end

@implementation RecordingTable
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray<NSDraggingItem *> *)items event:(NSEvent *)event source:(id<NSDraggingSource>)source
{
    draggingItems = items;
    [calls addObject: [NSString stringWithFormat: @"begin %lu by %s", (unsigned long) [items count], source == (id) self ? "self" : "other"]];
    return nil;
}
@end

static NSMutableArray *keep;

static RecordingTable *makeTable(Source *source)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 300) styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered defer: NO];
    window.releasedWhenClosed = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)];
    RecordingTable *table = [[RecordingTable alloc] initWithFrame: scroll.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"c"];
    column.width = 250;
    [table addTableColumn: column];
    table.rowHeight = 20;
    table.intercellSpacing = NSMakeSize(3, 2);
    table.allowsMultipleSelection = YES;
    table.dataSource = source;
    table.delegate = source;
    [table registerForDraggedTypes: @[ NSPasteboardTypeString ]];
    scroll.documentView = table;
    [window.contentView addSubview: scroll];
    [window makeKeyAndOrderFront: nil];
    [table reloadData];
    [window layoutIfNeeded];
    [window displayIfNeeded];
    [window makeFirstResponder: table];
    [keep addObject: window];
    [calls removeAllObjects];
    return table;
}

static Info *infoFor(NSTableView *table)
{
    Info *info = [[Info alloc] init];
    info.window = table.window;
    info.pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [info.pasteboard clearContents];
    [info.pasteboard writeObjects: @[ @"dropped" ]];
    return info;
}

// Enters at a point and drops there: the destination methods' answers, then what the data source was asked
static NSString *dropAt(NSTableView *table, NSPoint point)
{
    Info *info = infoFor(table);
    info.location = [table convertPoint: point toView: nil];
    [calls removeAllObjects];
    NSDragOperation entered = [table draggingEntered: info];
    NSDragOperation updated = [table draggingUpdated: info];
    BOOL performed = [table prepareForDragOperation: info] && [table performDragOperation: info];
    [table concludeDragOperation: info];
    if ([table respondsToSelector: @selector(draggingEnded:)])
        [table draggingEnded: info];
    NSMutableArray *asked = [NSMutableArray array];
    for (NSString *call in calls)
        if (![asked containsObject: call])
            [asked addObject: call];
    [calls removeAllObjects];
    return [NSString stringWithFormat: @"%lu %lu %d: %@", (unsigned long) entered, (unsigned long) updated, performed,
                                       [asked componentsJoinedByString: @"; "]];
}

static NSEvent *mouseEvent(NSView *view, NSEventType type, NSPoint point)
{
    return [NSEvent mouseEventWithType: type
                              location: [view convertPoint: point toView: nil]
                         modifierFlags: 0
                             timestamp: [[NSProcessInfo processInfo] systemUptime]
                          windowNumber: [[view window] windowNumber]
                               context: nil
                           eventNumber: 0
                            clickCount: 1
                              pressure: type == NSEventTypeLeftMouseUp ? 0 : 1];
}

// Presses at a point, moves by (dx, dy) in four steps and releases; the moves and the release are queued first
static void drag(NSView *view, NSPoint from, CGFloat dx, CGFloat dy)
{
    for (int step = 1; step <= 4; step++)
        [NSApp postEvent: mouseEvent(view, NSEventTypeLeftMouseDragged, NSMakePoint(from.x + dx * step / 4, from.y + dy * step / 4))
                 atStart: NO];
    [NSApp postEvent: mouseEvent(view, NSEventTypeLeftMouseUp, NSMakePoint(from.x + dx, from.y + dy)) atStart: NO];
    [[view window] sendEvent: mouseEvent(view, NSEventTypeLeftMouseDown, from)];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: nil inMode: NSDefaultRunLoopMode dequeue: YES]))
        [NSApp sendEvent: event];
}

static NSPoint inRow(NSTableView *table, NSInteger row, CGFloat dy)
{
    NSRect rect = [table rectOfRow: row];
    return NSMakePoint(50, NSMinY(rect) + dy);
}

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        calls = [NSMutableArray array];
        keep = [NSMutableArray array];
        Source *source = [Source new];
        source.rows = 5;

        // Where a drop is proposed
        RecordingTable *table = makeTable(source);
        NSString *got = dropAt(table, inRow(table, 2, 11));
        expect([got isEqual: @"1 1 1: validate 2 on; accept 2 on"], [NSString stringWithFormat: @"a row's middle: on it [%@]", got]);
        got = dropAt(table, inRow(table, 2, 1));
        expect([got isEqual: @"1 1 1: validate 2 above; accept 2 above"], [NSString stringWithFormat: @"a row's top edge: above it [%@]", got]);
        got = dropAt(table, inRow(table, 2, 4));
        expect([got isEqual: @"1 1 1: validate 2 above; accept 2 above"], [NSString stringWithFormat: @"its top quarter: above it [%@]", got]);
        got = dropAt(table, inRow(table, 2, 7));
        expect([got isEqual: @"1 1 1: validate 2 on; accept 2 on"], [NSString stringWithFormat: @"past its top quarter: on it [%@]", got]);
        got = dropAt(table, inRow(table, 2, 20));
        expect([got isEqual: @"1 1 1: validate 3 above; accept 3 above"], [NSString stringWithFormat: @"its bottom edge: above the next row [%@]", got]);
        got = dropAt(table, NSMakePoint(50, NSMaxY([table rectOfRow: 4]) + 3));
        expect([got isEqual: @"1 1 1: validate 5 above; accept 5 above"], [NSString stringWithFormat: @"below the rows: above the row count [%@]", got]);

        source.rows = 0;
        RecordingTable *empty = makeTable(source);
        got = dropAt(empty, NSMakePoint(50, 50));
        expect([got isEqual: @"1 1 1: validate 0 above; accept 0 above"], [NSString stringWithFormat: @"an empty table: above row 0 [%@]", got]);
        source.rows = 5;

        // What the data source makes of it
        source.mode = RETARGET;
        got = dropAt(table, inRow(table, 2, 11));
        expect([got isEqual: @"1 1 1: validate 2 on; accept 4 above"], [NSString stringWithFormat: @"setDropRow:dropOperation: retargets [%@]", got]);
        // The dragging system performs no drop answered None, so only the answers are checked
        source.mode = REFUSE;
        got = dropAt(table, inRow(table, 2, 11));
        expect([got hasPrefix: @"0 0 "] && [got rangeOfString: @": validate 2 on"].location != NSNotFound,
               [NSString stringWithFormat: @"a refused drop is answered None [%@]", got]);
        source.mode = ALLOW;

        // Dragging rows
        table = makeTable(source);
        [table selectRowIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(1, 1)] byExtendingSelection: NO];
        [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 3] byExtendingSelection: YES];
        [calls removeAllObjects];
        drag(table, inRow(table, 1, 11), 30, 0);
        got = [calls componentsJoinedByString: @"; "];
        expect([got isEqual: @"writer 1; writer 3; begin 2 by self"],
               [NSString stringWithFormat: @"a drag from a selected row drags the selection's writers, not writeRows [%@]", got]);
        NSArray<NSDraggingItem *> *items = table->draggingItems;
        expect([items count] == 2 && [[(NSURL *) items[0].item path] isEqual: @"/private/var/tmp/row-1"] &&
                   [[(NSURL *) items[1].item path] isEqual: @"/private/var/tmp/row-3"],
               @"the dragging items are the rows' file URLs");
        [calls removeAllObjects];
        [table draggingSession: (NSDraggingSession *) nil endedAtPoint: NSZeroPoint operation: NSDragOperationCopy];
        got = [calls componentsJoinedByString: @"; "];
        expect([got isEqual: @"ended 1"], [NSString stringWithFormat: @"the session's end goes to the data source [%@]", got]);

        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
