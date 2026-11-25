// CFLAGS: -framework Foundation -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// A view-based NSOutlineView as a drop target and a dragging source, with the data source's item API, without a real
// drag (as appkit-tableview-drag.m does it for a table). The items are A, B (expanded: B1, B2) and C, in rows 0 to 4.
// - A drop on a row's middle is on its item (child index -1, NSOutlineViewDropOnItemIndex).
// - Above a row, it is before that row's item among its siblings; where the row above is deeper, the point's distance
//   from the outline column's edge picks the level, so at the left edge it is after the shallower ancestor.
// - In the last row's bottom quarter, it is after the last top-level item; below every row, it is on the root item.
// - setDropItem:dropChildIndex: in validateDrop changes what acceptDrop gets; the table's row methods aren't sent to
//   an outline view's data source.
// - outlineView:pasteboardWriterForItem: gives the dragged items' writers; the session's end goes to
//   outlineView:draggingSession:endedAtPoint:operation:.
// The rows are 20 points high with the default 2-point spacing. Observed on macOS 26.7.3 and 10.14.4, where it passes
// unchanged. Needs a display. Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

static NSMutableArray<NSString *> *calls;

enum { ALLOW, RETARGET_ROOT, RETARGET_C };

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

@interface Source : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource>
@property int mode;
@end

@implementation Source
- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item
{
    return item == nil ? 3 : [item isEqual: @"B"] ? 2 : 0;
}
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item
{
    return item == nil ? @[ @"A", @"B", @"C" ][index] : @[ @"B1", @"B2" ][index];
}
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item { return [item isEqual: @"B"]; }
- (NSView *)outlineView:(NSOutlineView *)outline viewForTableColumn:(NSTableColumn *)column item:(id)item
{
    return [NSTextField labelWithString: item];
}
- (NSDragOperation)outlineView:(NSOutlineView *)outline validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    [calls addObject: [NSString stringWithFormat: @"validate %@/%ld", item ?: @"root", (long) index]];
    if (_mode == RETARGET_ROOT)
        [outline setDropItem: nil dropChildIndex: NSOutlineViewDropOnItemIndex];
    else if (_mode == RETARGET_C)
        [outline setDropItem: @"C" dropChildIndex: NSOutlineViewDropOnItemIndex];
    return NSDragOperationCopy;
}
- (BOOL)outlineView:(NSOutlineView *)outline acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    [calls addObject: [NSString stringWithFormat: @"accept %@/%ld", item ?: @"root", (long) index]];
    return YES;
}
- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outline pasteboardWriterForItem:(id)item
{
    [calls addObject: [NSString stringWithFormat: @"writer %@", item]];
    return [NSURL fileURLWithPath: [@"/private/var/tmp" stringByAppendingPathComponent: item]];
}
- (void)outlineView:(NSOutlineView *)outline draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation
{
    [calls addObject: [NSString stringWithFormat: @"ended %lu", (unsigned long) operation]];
}
// The table's methods, which an outline view doesn't send
- (NSDragOperation)tableView:(NSTableView *)table validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    [calls addObject: @"table validate"];
    return NSDragOperationCopy;
}
- (BOOL)tableView:(NSTableView *)table acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    [calls addObject: @"table accept"];
    return YES;
}
- (id<NSPasteboardWriting>)tableView:(NSTableView *)table pasteboardWriterForRow:(NSInteger)row
{
    [calls addObject: @"table writer"];
    return nil;
}
@end

@interface RecordingOutline : NSOutlineView {
@public
    NSArray<NSDraggingItem *> *draggingItems;
}
@end

@implementation RecordingOutline
- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray<NSDraggingItem *> *)items event:(NSEvent *)event source:(id<NSDraggingSource>)source
{
    draggingItems = items;
    [calls addObject: [NSString stringWithFormat: @"begin %lu by %s", (unsigned long) [items count], source == (id) self ? "self" : "other"]];
    return nil;
}
@end

static NSMutableArray *keep;

static RecordingOutline *makeOutline(Source *source)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 300) styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered defer: NO];
    window.releasedWhenClosed = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)];
    RecordingOutline *outline = [[RecordingOutline alloc] initWithFrame: scroll.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"c"];
    column.width = 250;
    [outline addTableColumn: column];
    outline.outlineTableColumn = column;
    outline.rowHeight = 20;
    outline.intercellSpacing = NSMakeSize(3, 2);
    outline.allowsMultipleSelection = YES;
    outline.dataSource = source;
    outline.delegate = source;
    [outline registerForDraggedTypes: @[ NSPasteboardTypeString ]];
    scroll.documentView = outline;
    [window.contentView addSubview: scroll];
    [window makeKeyAndOrderFront: nil];
    [outline reloadData];
    [outline expandItem: @"B"];
    [window layoutIfNeeded];
    [window displayIfNeeded];
    [window makeFirstResponder: outline];
    [keep addObject: window];
    [calls removeAllObjects];
    return outline;
}

// Enters at a point and drops there: the destination methods' answers, then what the data source was asked
static NSString *dropAt(NSOutlineView *outline, NSPoint point)
{
    Info *info = [[Info alloc] init];
    info.window = outline.window;
    info.pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [info.pasteboard clearContents];
    [info.pasteboard writeObjects: @[ @"dropped" ]];
    info.location = [outline convertPoint: point toView: nil];
    [calls removeAllObjects];
    NSDragOperation entered = [outline draggingEntered: info];
    NSDragOperation updated = [outline draggingUpdated: info];
    BOOL performed = [outline prepareForDragOperation: info] && [outline performDragOperation: info];
    [outline concludeDragOperation: info];
    if ([outline respondsToSelector: @selector(draggingEnded:)])
        [outline draggingEnded: info];
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

static NSPoint inRow(NSOutlineView *outline, NSInteger row, CGFloat x, CGFloat dy)
{
    return NSMakePoint(x, NSMinY([outline rectOfRow: row]) + dy);
}

static void expectDrop(NSOutlineView *outline, NSPoint point, NSString *want, NSString *what)
{
    NSString *got = dropAt(outline, point);
    expect([got isEqual: want], [NSString stringWithFormat: @"%@ [%@] (want [%@])", what, got, want]);
}

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        calls = [NSMutableArray array];
        keep = [NSMutableArray array];
        Source *source = [Source new];
        RecordingOutline *outline = makeOutline(source);
        expect(outline.numberOfRows == 5, @"five rows");

        // Where a drop is proposed
        expectDrop(outline, inRow(outline, 2, 150, 11), @"1 1 1: validate B1/-1; accept B1/-1", @"a row's middle: on its item");
        expectDrop(outline, inRow(outline, 0, 150, 1), @"1 1 1: validate root/0; accept root/0", @"the first row's top: before A");
        expectDrop(outline, inRow(outline, 0, 150, 20), @"1 1 1: validate root/1; accept root/1", @"A's bottom: before B");
        expectDrop(outline, inRow(outline, 1, 150, 20), @"1 1 1: validate B/0; accept B/0", @"expanded B's bottom: before its first child");
        expectDrop(outline, inRow(outline, 2, 150, 1), @"1 1 1: validate B/0; accept B/0", @"B1's top: before it");
        expectDrop(outline, inRow(outline, 3, 150, 20), @"1 1 1: validate B/2; accept B/2", @"B2's bottom, well right: after it in B");
        expectDrop(outline, inRow(outline, 3, 5, 20), @"1 1 1: validate root/2; accept root/2", @"B2's bottom at the left edge: after B");
        expectDrop(outline, inRow(outline, 4, 150, 20), @"1 1 1: validate root/3; accept root/3", @"the last row's bottom: after C");
        expectDrop(outline, NSMakePoint(150, NSMaxY([outline rectOfRow: 4]) + 3), @"1 1 1: validate root/-1; accept root/-1",
                   @"below every row: on the root");

        // What the data source makes of it
        source.mode = RETARGET_ROOT;
        expectDrop(outline, inRow(outline, 2, 150, 11), @"1 1 1: validate B1/-1; accept root/-1", @"setDropItem: nil retargets to the root");
        source.mode = RETARGET_C;
        expectDrop(outline, inRow(outline, 0, 150, 1), @"1 1 1: validate root/0; accept C/-1", @"setDropItem: C retargets on C");
        source.mode = ALLOW;

        // Dragging items
        outline = makeOutline(source);
        [outline selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
        [outline selectRowIndexes: [NSIndexSet indexSetWithIndex: 2] byExtendingSelection: YES];
        [calls removeAllObjects];
        drag(outline, inRow(outline, 0, 150, 11), 30, 0);
        NSString *got = [calls componentsJoinedByString: @"; "];
        expect([got isEqual: @"writer A; writer B1; begin 2 by self"],
               [NSString stringWithFormat: @"a drag from a selected row drags the selected items' writers [%@]", got]);
        NSArray<NSDraggingItem *> *items = outline->draggingItems;
        expect([items count] == 2 && [[(NSURL *) items[0].item path] isEqual: @"/private/var/tmp/A"] &&
                   [[(NSURL *) items[1].item path] isEqual: @"/private/var/tmp/B1"],
               @"the dragging items are the items' file URLs");
        [calls removeAllObjects];
        [outline draggingSession: (NSDraggingSession *) nil endedAtPoint: NSZeroPoint operation: NSDragOperationMove];
        got = [calls componentsJoinedByString: @"; "];
        expect([got isEqual: @"ended 16"], [NSString stringWithFormat: @"the session's end goes to the data source [%@]", got]);

        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
