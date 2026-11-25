// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// NSCollectionView as a dragging source and a drop target, without a real
// drag: mouse events sent to the window start the drag, which a subclass
// records in -beginDraggingSessionWithItems:event:source: instead of starting
// it, and the destination is driven through its NSDraggingDestination methods
// with a stand-in NSDraggingInfo. The delegate's NSCollectionViewDelegate
// methods are documented; what the documentation leaves open (the default
// operation masks, when a drag starts, what an unselected item does, the
// proposed drop locations and the drop-target highlight) was observed on
// macOS 26.7.3 and 10.14.4 (darling's tests/collection-view.md), and the
// program passes unchanged on both.
//
// The collection view is 300x300 in a scroll view, with 10 items of 80x30 in
// three columns; item frames come from the layout, as the scroller's width
// differs between systems.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void expect(BOOL ok, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    printf(ok ? "PASS: " : "FAIL: ");
    vprintf(format, args);
    printf("\n");
    va_end(args);
    if (!ok)
        failures++;
}

static NSMutableArray *calls; // what the delegate and the view were asked, in order

static NSString *describe(NSSet *set)
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSIndexPath *p in set)
        [items addObject: [NSNumber numberWithInteger: p.item]];
    [items sortUsingSelector: @selector(compare:)];
    return [items componentsJoinedByString: @","];
}

static NSString *log_(void)
{
    NSString *result = [calls componentsJoinedByString: @"; "];
    [calls removeAllObjects];
    return result;
}

@interface Item : NSCollectionViewItem
@end
@implementation Item
- (void) loadView {
    self.view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
}
@end

// Records the drag it is asked to start; the dragging items, their frames and the event go into the calls
@interface RecordingView : NSCollectionView {
@public
    NSArray *draggingItems;
}
@end
@implementation RecordingView
- (NSDraggingSession *) beginDraggingSessionWithItems: (NSArray *) items event: (NSEvent *) event source: (id) source {
    [draggingItems release];
    draggingItems = [items copy];
    [calls addObject: [NSString stringWithFormat: @"begin %lu from %s by %s", (unsigned long) [items count],
                                                  [event type] == NSEventTypeLeftMouseDown ? "down" : "other",
                                                  source == self ? "self" : "other"]];
    return nil;
}
- (void) dealloc {
    [draggingItems release];
    [super dealloc];
}
@end

enum { ALLOW, REFUSE_DRAG, NIL_WRITER_FOR_4, RETARGET, RETARGET_TO_VIEW, REFUSE_DROP, EMPTY };

@interface Delegate : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate> {
@public
    int mode;
}
@end
@implementation Delegate
- (NSInteger) collectionView: (NSCollectionView *) view numberOfItemsInSection: (NSInteger) section {
    return mode == EMPTY ? 0 : 10;
}
- (NSCollectionViewItem *) collectionView: (NSCollectionView *) view itemForRepresentedObjectAtIndexPath: (NSIndexPath *) path {
    return [view makeItemWithIdentifier: @"item" forIndexPath: path];
}
- (NSSet *) collectionView: (NSCollectionView *) view shouldSelectItemsAtIndexPaths: (NSSet *) paths {
    [calls addObject: [NSString stringWithFormat: @"shouldSelect %@", describe(paths)]];
    return paths;
}
- (NSSet *) collectionView: (NSCollectionView *) view shouldDeselectItemsAtIndexPaths: (NSSet *) paths {
    [calls addObject: [NSString stringWithFormat: @"shouldDeselect %@", describe(paths)]];
    return paths;
}
- (BOOL) collectionView: (NSCollectionView *) view canDragItemsAtIndexPaths: (NSSet *) paths withEvent: (NSEvent *) event {
    [calls addObject: [NSString stringWithFormat: @"canDrag %@ on %s", describe(paths),
                                                  [event type] == NSEventTypeLeftMouseDown ? "down" : "other"]];
    return mode != REFUSE_DRAG;
}
- (id<NSPasteboardWriting>) collectionView: (NSCollectionView *) view pasteboardWriterForItemAtIndexPath: (NSIndexPath *) path {
    [calls addObject: [NSString stringWithFormat: @"writer %ld", (long) path.item]];
    if (mode == NIL_WRITER_FOR_4 && path.item == 4)
        return nil;
    return [NSURL fileURLWithPath: [NSString stringWithFormat: @"/private/var/tmp/item-%ld", (long) path.item]];
}
- (NSDragOperation) collectionView: (NSCollectionView *) view validateDrop: (id<NSDraggingInfo>) info
                 proposedIndexPath: (NSIndexPath **) path dropOperation: (NSCollectionViewDropOperation *) operation
{
    [calls addObject: [NSString stringWithFormat: @"validate %ld %s", (long) (*path).item,
                                                  *operation == NSCollectionViewDropOn ? "on" : "before"]];
    if (mode == RETARGET) {
        *path = [NSIndexPath indexPathForItem: 9 inSection: 0];
        *operation = NSCollectionViewDropBefore;
    } else if (mode == RETARGET_TO_VIEW) {
        *path = nil;
        *operation = NSCollectionViewDropOn;
    }
    return mode == REFUSE_DROP ? NSDragOperationNone : NSDragOperationCopy;
}
- (BOOL) collectionView: (NSCollectionView *) view acceptDrop: (id<NSDraggingInfo>) info indexPath: (NSIndexPath *) path
          dropOperation: (NSCollectionViewDropOperation) operation
{
    [calls addObject: [NSString stringWithFormat: @"accept %@ %s", path == nil ? @"view" : [NSString stringWithFormat: @"%ld", (long) path.item],
                                                  operation == NSCollectionViewDropOn ? "on" : "before"]];
    return YES;
}
@end

// A drag at a point of the collection view, from no source, offering every operation
@interface Info : NSObject <NSDraggingInfo> {
@public
    NSPoint location; // in the window
    NSWindow *window;
    NSPasteboard *pasteboard;
}
@end
@implementation Info
@synthesize draggingFormation, animatesToDestination, numberOfValidItemsForDrop;
- (NSWindow *) draggingDestinationWindow { return window; }
- (NSDragOperation) draggingSourceOperationMask { return NSDragOperationEvery; }
- (NSPoint) draggingLocation { return location; }
- (NSPoint) draggedImageLocation { return location; }
- (NSImage *) draggedImage { return nil; }
- (NSPasteboard *) draggingPasteboard { return pasteboard; }
- (id) draggingSource { return nil; }
- (NSInteger) draggingSequenceNumber { return 1; }
- (void) slideDraggedImageTo: (NSPoint) point {}
- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination { return nil; }
- (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) options forView: (NSView *) view
                                   classes: (NSArray *) classes searchOptions: (NSDictionary *) searchOptions
                                usingBlock: (void (^)(NSDraggingItem *, NSInteger, BOOL *)) block {}
- (NSSpringLoadingHighlight) springLoadingHighlight { return NSSpringLoadingHighlightNone; }
- (void) resetSpringLoading {}
@end

static NSMutableArray *keep;
static Delegate *delegate;

// A new view each time: a drag that was recorded and never started leaves a view expecting it
static RecordingView *makeView(void)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 300)
                                                   styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)] autorelease];
    // Overlay scrollers take no width: the items are placed once, for the width the view keeps
    scroll.scrollerStyle = NSScrollerStyleOverlay;
    RecordingView *view = [[[RecordingView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)] autorelease];
    NSCollectionViewFlowLayout *layout = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
    layout.itemSize = NSMakeSize(80, 30);
    view.collectionViewLayout = layout;
    [view registerClass: [Item class] forItemWithIdentifier: @"item"];
    view.dataSource = delegate;
    view.delegate = delegate;
    view.selectable = YES;
    view.allowsMultipleSelection = YES;
    scroll.documentView = view;
    [window.contentView addSubview: scroll];
    [keep addObject: window];
    [window release];
    [view reloadData];
    [view layoutSubtreeIfNeeded];
    [window makeKeyAndOrderFront: nil];
    [window makeFirstResponder: view];
    // Item views move to where the layout puts them in the window's next layout pass
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    [window layoutIfNeeded];
    [window displayIfNeeded];
    delegate->mode = ALLOW;
    return view;
}

static NSIndexPath *path(NSInteger item)
{
    return [NSIndexPath indexPathForItem: item inSection: 0];
}

static NSRect frameOf(NSCollectionView *view, NSInteger item)
{
    return [view layoutAttributesForItemAtIndexPath: path(item)].frame;
}

static NSPoint centerOf(NSCollectionView *view, NSInteger item)
{
    NSRect frame = frameOf(view, item);
    return NSMakePoint(NSMidX(frame), NSMidY(frame));
}

static void select_(NSCollectionView *view, NSArray *items)
{
    NSMutableSet *paths = [NSMutableSet set];
    for (NSNumber *item in items)
        [paths addObject: path([item integerValue])];
    view.selectionIndexPaths = paths;
    [calls removeAllObjects];
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

// Presses at a point, moves by (dx, dy) in four steps (none for a click) and releases. The moves and the release are queued first, so
// whatever handles the press finds them; what it leaves goes through the window.
static void drag(NSView *view, NSPoint from, CGFloat dx, CGFloat dy)
{
    for (int step = 1; step <= 4 && (dx != 0 || dy != 0); step++)
        [NSApp postEvent: mouseEvent(view, NSEventTypeLeftMouseDragged,
                                     NSMakePoint(from.x + dx * step / 4, from.y + dy * step / 4))
                 atStart: NO];
    [NSApp postEvent: mouseEvent(view, NSEventTypeLeftMouseUp, NSMakePoint(from.x + dx, from.y + dy)) atStart: NO];
    [[view window] sendEvent: mouseEvent(view, NSEventTypeLeftMouseDown, from)];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: nil inMode: NSDefaultRunLoopMode dequeue: YES]))
        [NSApp sendEvent: event];
}

static void test_default_source_masks(void)
{
    NSCollectionView *view = makeView();
    expect([view draggingSession: nil sourceOperationMaskForDraggingContext: NSDraggingContextWithinApplication]
               == NSDragOperationEvery,
           "a new view offers every operation within the application");
    expect([view draggingSession: nil sourceOperationMaskForDraggingContext: NSDraggingContextOutsideApplication]
               == NSDragOperationNone,
           "a new view offers nothing outside the application");
    [view setDraggingSourceOperationMask: NSDragOperationMove forLocal: NO];
    expect([view draggingSession: nil sourceOperationMaskForDraggingContext: NSDraggingContextOutsideApplication]
               == NSDragOperationMove,
           "setDraggingSourceOperationMask:forLocal:NO sets the mask outside the application");
    expect([view draggingSession: nil sourceOperationMaskForDraggingContext: NSDraggingContextWithinApplication]
               == NSDragOperationEvery,
           "and leaves the one within it");
    [view setDraggingSourceOperationMask: NSDragOperationCopy forLocal: YES];
    expect([view draggingSession: nil sourceOperationMaskForDraggingContext: NSDraggingContextWithinApplication]
               == NSDragOperationCopy,
           "setDraggingSourceOperationMask:forLocal:YES sets the mask within the application");
}

static void test_click_does_not_drag(void)
{
    RecordingView *view = makeView();
    select_(view, @[@1, @4]);
    drag(view, centerOf(view, 1), 0, 0);
    NSString *got = log_();
    expect([got rangeOfString: @"canDrag"].location == NSNotFound && [got rangeOfString: @"begin"].location == NSNotFound,
           "a click on a selected item starts no drag ([%s])", [got UTF8String]);
}

static void test_multi_item_drag_pasteboard(void)
{
    RecordingView *view = makeView();
    select_(view, @[@1, @4]);
    drag(view, centerOf(view, 1), 6, 0);
    NSString *got = log_();
    NSString *want = @"canDrag 1,4 on down; writer 1; writer 4; begin 2 from down by self";
    expect([got isEqual: want], "a drag from a selected item drags the selection: [%s] (want [%s])", [got UTF8String],
           [want UTF8String]);
    NSArray *items = view->draggingItems;
    expect([items count] == 2, "two dragging items (%lu)", (unsigned long) [items count]);
    if ([items count] != 2)
        return;
    for (NSUInteger i = 0; i < 2; i++) {
        NSInteger item = i == 0 ? 1 : 4;
        NSDraggingItem *dragging = [items objectAtIndex: i];
        NSString *wantPath = [NSString stringWithFormat: @"/private/var/tmp/item-%ld", (long) item];
        expect([dragging.item isKindOfClass: [NSURL class]] && [[(NSURL *) dragging.item path] isEqual: wantPath],
               "dragging item %lu writes item %ld's file URL (%s)", (unsigned long) i, (long) item,
               [[dragging.item description] UTF8String]);
        expect(NSEqualRects(dragging.draggingFrame, frameOf(view, item)), "dragging item %lu is framed at item %ld: %s",
               (unsigned long) i, (long) item, [NSStringFromRect(dragging.draggingFrame) UTF8String]);
        expect([dragging.imageComponents count] == 1, "dragging item %lu has one image component (%lu)",
               (unsigned long) i, (unsigned long) [dragging.imageComponents count]);
    }
    expect([describe(view.selectionIndexPaths) isEqual: @"1,4"], "the selection stays {%s}",
           [describe(view.selectionIndexPaths) UTF8String]);
}

static void test_drag_unselected_item_selects_it(void)
{
    RecordingView *view = makeView();
    select_(view, @[@1, @4]);
    drag(view, centerOf(view, 2), 20, 20);
    NSString *got = log_();
    NSString *want = @"shouldDeselect 1,4; shouldSelect 2; canDrag 2 on down; writer 2; begin 1 from down by self";
    expect([got isEqual: want], "a drag from an unselected item selects only it and drags it: [%s] (want [%s])",
           [got UTF8String], [want UTF8String]);
    expect([describe(view.selectionIndexPaths) isEqual: @"2"], "selection {%s}",
           [describe(view.selectionIndexPaths) UTF8String]);
}

static void test_can_drag_refusal_cancels(void)
{
    RecordingView *view = makeView();
    select_(view, @[@1, @4]);
    delegate->mode = REFUSE_DRAG;
    drag(view, centerOf(view, 1), 20, 20);
    NSString *got = log_();
    expect([got hasPrefix: @"canDrag 1,4 on down"] && [got rangeOfString: @"writer"].location == NSNotFound &&
               [got rangeOfString: @"begin"].location == NSNotFound,
           "a refused drag asks for no writer and starts nothing ([%s])", [got UTF8String]);
    expect([describe(view.selectionIndexPaths) isEqual: @"1,4"], "and keeps the selection {%s}",
           [describe(view.selectionIndexPaths) UTF8String]);
}

static void test_nil_writer_leaves_item_out(void)
{
    RecordingView *view = makeView();
    select_(view, @[@1, @4, @7]);
    delegate->mode = NIL_WRITER_FOR_4;
    drag(view, centerOf(view, 1), 20, 20);
    NSString *got = log_();
    NSString *want = @"canDrag 1,4,7 on down; writer 1; writer 4; writer 7; begin 2 from down by self";
    expect([got isEqual: want], "an item without a writer is left out: [%s] (want [%s])", [got UTF8String],
           [want UTF8String]);
    NSArray *items = view->draggingItems;
    expect([items count] == 2 && NSEqualRects([[items objectAtIndex: 1] draggingFrame], frameOf(view, 7)),
           "the second dragging item is item 7's");
}

static Info *infoFor(NSCollectionView *view)
{
    Info *info = [[[Info alloc] init] autorelease];
    info->window = [view window];
    info->pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [info->pasteboard clearContents];
    [info->pasteboard writeObjects: @[@"dropped"]];
    [view registerForDraggedTypes: @[NSPasteboardTypeString]];
    [calls removeAllObjects];
    return info;
}

static void at(Info *info, NSCollectionView *view, NSPoint point)
{
    info->location = [view convertPoint: point toView: nil];
}

// Enters at a point and drops there; returns what the destination methods answered and the delegate was asked
static NSString *dropAt(NSCollectionView *view, Info *info, NSPoint point)
{
    at(info, view, point);
    NSDragOperation entered = [view draggingEntered: info];
    NSDragOperation updated = [view draggingUpdated: info];
    BOOL performed = [view prepareForDragOperation: info] && [view performDragOperation: info];
    [view concludeDragOperation: info];
    [view draggingEnded: info];
    NSMutableArray *asked = [NSMutableArray array];
    for (NSString *call in calls)
        if (![asked containsObject: call])
            [asked addObject: call];
    [calls removeAllObjects];
    return [NSString stringWithFormat: @"%lu %lu %d: %@", (unsigned long) entered, (unsigned long) updated, performed,
                                       [asked componentsJoinedByString: @"; "]];
}

static void test_drop_on_item(void)
{
    NSCollectionView *view = makeView();
    Info *info = infoFor(view);
    NSRect frame = frameOf(view, 4);
    NSString *got = dropAt(view, info, centerOf(view, 4));
    expect([got isEqual: @"1 1 1: validate 4 on; accept 4 on"], "a drop on an item's middle: [%s]", [got UTF8String]);
    got = dropAt(view, info, NSMakePoint(NSMinX(frame) + 2, NSMinY(frame) + 2));
    expect([got isEqual: @"1 1 1: validate 4 on; accept 4 on"], "a drop just inside its corner: [%s]", [got UTF8String]);
}

static void test_background_drop_proposes_gap(void)
{
    NSCollectionView *view = makeView();
    Info *info = infoFor(view);
    NSRect three = frameOf(view, 3), four = frameOf(view, 4), five = frameOf(view, 5), nine = frameOf(view, 9);
    struct {
        const char *where;
        NSPoint point;
        NSInteger item;
    } cases[] = {
        {"between items 3 and 4", NSMakePoint(NSMaxX(three) + 2, NSMidY(four)), 4},
        {"between items 4 and 5, nearer 4", NSMakePoint(NSMaxX(four) + 2, NSMidY(four)), 5},
        {"right of a row's last item", NSMakePoint(NSMaxX(five) + 1, NSMidY(five)), 6},
        {"between two rows", NSMakePoint(NSMidX(four), NSMinY(four) - 5), 3},
        {"right of the last item", NSMakePoint(NSMaxX(nine) + 30, NSMidY(nine)), 10},
        {"below every item", NSMakePoint(NSMidX(four), NSMaxY(nine) + 60), 10},
    };
    for (unsigned i = 0; i < sizeof cases / sizeof *cases; i++) {
        NSString *got = dropAt(view, info, cases[i].point);
        NSString *want = [NSString stringWithFormat: @"1 1 1: validate %ld before; accept %ld before", (long) cases[i].item,
                                                     (long) cases[i].item];
        expect([got isEqual: want], "a drop %s: [%s] (want [%s])", cases[i].where, [got UTF8String], [want UTF8String]);
    }
}

static void test_validate_can_retarget(void)
{
    NSCollectionView *view = makeView();
    Info *info = infoFor(view);
    delegate->mode = RETARGET;
    NSString *got = dropAt(view, info, centerOf(view, 4));
    expect([got isEqual: @"1 1 1: validate 4 on; accept 9 before"], "the delegate's index path and operation reach "
                                                                     "acceptDrop: [%s]",
           [got UTF8String]);
}

// A delegate that sets the index path to nil (with the On operation) leaves nothing to drop on: the drop is
// validated but not performed, and acceptDrop isn't asked
static void test_validate_nil_path_is_not_accepted(void)
{
    NSCollectionView *view = makeView();
    Info *info = infoFor(view);
    delegate->mode = RETARGET_TO_VIEW;
    NSString *got = dropAt(view, info, centerOf(view, 4));
    expect([got isEqual: @"1 1 0: validate 4 on"], "a drop retargeted to no index path is not performed: [%s]",
           [got UTF8String]);
    delegate->mode = ALLOW;
}

static void test_validate_none_refuses(void)
{
    NSCollectionView *view = makeView();
    Info *info = infoFor(view);
    delegate->mode = REFUSE_DROP;
    NSString *got = dropAt(view, info, centerOf(view, 4));
    expect([got isEqual: @"0 0 0: validate 4 on"], "a refused drop is not accepted: [%s]", [got UTF8String]);
}

// The subviews in the gap before an item, other than items
// A view with no items still takes a drop: before the first item of its first section
static void test_drop_on_empty_view(void)
{
    NSCollectionView *view = makeView();
    delegate->mode = EMPTY;
    [view reloadData];
    [view layoutSubtreeIfNeeded];
    Info *info = infoFor(view);
    NSString *got = dropAt(view, info, NSMakePoint(150, 150));
    expect([got isEqual: @"1 1 1: validate 0 before; accept 0 before"], "a drop on an empty view: [%s]", [got UTF8String]);
    delegate->mode = ALLOW;
}

static NSUInteger gapViews(NSCollectionView *view, NSInteger before)
{
    NSRect gap = [view.collectionViewLayout layoutAttributesForInterItemGapBeforeIndexPath: path(before)].frame;
    NSMutableSet *items = [NSMutableSet set];
    for (NSCollectionViewItem *item in [view visibleItems])
        [items addObject: [NSValue valueWithNonretainedObject: item.view]];
    NSUInteger count = 0;
    for (NSView *subview in [view subviews]) {
        NSRect frame = [subview frame];
        if (![items containsObject: [NSValue valueWithNonretainedObject: subview]] && ![subview isHidden] &&
            fabs(NSMinX(frame) - NSMinX(gap)) <= 1 && fabs(NSMinY(frame) - NSMinY(gap)) <= 1 &&
            fabs(NSWidth(frame) - NSWidth(gap)) <= 1 && fabs(NSHeight(frame) - NSHeight(gap)) <= 1)
            count++;
    }
    return count;
}

static void test_drop_target_highlight(void)
{
    NSCollectionView *view = makeView();
    Info *info = infoFor(view);
    NSCollectionViewItem *four = [view itemAtIndexPath: path(4)];
    at(info, view, centerOf(view, 4));
    [view draggingEntered: info];
    expect(four.highlightState == NSCollectionViewItemHighlightAsDropTarget, "over an item it is the drop target (%ld)",
           (long) four.highlightState);
    expect(gapViews(view, 4) == 0, "with no gap indicator");
    at(info, view, NSMakePoint(NSMaxX(frameOf(view, 3)) + 2, NSMidY(frameOf(view, 4))));
    [view draggingUpdated: info];
    [view layoutSubtreeIfNeeded];
    expect(four.highlightState == NSCollectionViewItemHighlightNone, "over the gap before it, it is not (%ld)",
           (long) four.highlightState);
    expect(gapViews(view, 4) == 1, "and a view shows the gap (%lu)", (unsigned long) gapViews(view, 4));
    [view draggingExited: info];
    [view layoutSubtreeIfNeeded];
    expect(gapViews(view, 4) == 0, "the gap indicator goes when the drag leaves (%lu)", (unsigned long) gapViews(view, 4));

    at(info, view, centerOf(view, 4));
    [view draggingEntered: info];
    [view prepareForDragOperation: info];
    [view performDragOperation: info];
    [view concludeDragOperation: info];
    expect(four.highlightState == NSCollectionViewItemHighlightAsDropTarget,
           "the drop target stays highlighted until the drag ends (%ld)", (long) four.highlightState);
    [view draggingEnded: info];
    expect(four.highlightState == NSCollectionViewItemHighlightNone, "and not after (%ld)", (long) four.highlightState);
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    keep = [[NSMutableArray alloc] init];
    calls = [[NSMutableArray alloc] init];
    delegate = [[Delegate alloc] init];
    // The first click of the process activates the application and its mouse up comes late; it isn't part of any case
    NSCollectionView *view = makeView();
    drag(view, centerOf(view, 0), 0, 0);
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: nil inMode: NSDefaultRunLoopMode dequeue: YES]))
        [NSApp sendEvent: event];
    [calls removeAllObjects];

    test_default_source_masks();
    test_click_does_not_drag();
    test_multi_item_drag_pasteboard();
    test_drag_unselected_item_selects_it();
    test_can_drag_refusal_cancels();
    test_nil_writer_leaves_item_out();
    test_drop_on_item();
    test_background_drop_proposes_gap();
    test_validate_can_retarget();
    test_validate_nil_path_is_not_accepted();
    test_validate_none_refuses();
    test_drop_on_empty_view();
    test_drop_target_highlight();

    [delegate release];
    [calls release];
    [keep release];
    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
