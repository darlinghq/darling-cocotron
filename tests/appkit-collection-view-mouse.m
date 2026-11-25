// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// Selecting collection view items with the mouse and the keyboard, through
// events sent to the window: clicks with and without modifiers, clicks on the
// background, rubber bands, arrow keys, and the delegate calls each makes, in
// order. The delegate's answers decide what is selected. Values the
// documentation does not pin were observed on macOS 26.7.3 and 10.14.4
// (darling's tests/collection-view.md); the program passes unchanged on both.
//
// The collection view is 300 wide with 10 items of 80x30: three columns at
// x 0, 110 and 220, rows at y 0, 40, 80 and 120. Item i is in column i % 3
// and row i / 3.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void expect(BOOL ok, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    printf("%s ", ok ? "PASS" : "FAIL");
    vprintf(format, ap);
    printf("\n");
    va_end(ap);
    if (!ok)
        failures++;
}

static NSMutableArray *calls; // the delegate calls, in order

static NSString *describe(NSSet *set)
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSIndexPath *p in set)
        [items addObject: [NSNumber numberWithInteger: p.item]];
    [items sortUsingSelector: @selector(compare:)];
    return [items componentsJoinedByString: @","];
}

// Records the clicks it gets and whether its item was selected by then
@interface ItemView : NSView {
@public
    NSCollectionViewItem *item;
    NSInteger lastClickCount;
    BOOL selectedAtClick;
}
@end
@implementation ItemView
- (void) mouseDown: (NSEvent *) event {
    lastClickCount = [event clickCount];
    selectedAtClick = item.selected;
    [super mouseDown: event];
}
@end

@interface Item : NSCollectionViewItem
@end
@implementation Item
- (void) loadView {
    ItemView *view = [[[ItemView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    view->item = self;
    self.view = view;
}
@end

@interface Source : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate> {
@public
    NSInteger count;
    NSSet *refused; // never selected
}
@end
@implementation Source
- (NSInteger) collectionView: (NSCollectionView *) view numberOfItemsInSection: (NSInteger) section {
    return count;
}
- (NSCollectionViewItem *) collectionView: (NSCollectionView *) view itemForRepresentedObjectAtIndexPath: (NSIndexPath *) path {
    return [view makeItemWithIdentifier: @"item" forIndexPath: path];
}
- (NSSet *) collectionView: (NSCollectionView *) view shouldSelectItemsAtIndexPaths: (NSSet *) paths {
    [calls addObject: [NSString stringWithFormat: @"shouldSelect %@", describe(paths)]];
    if (refused == nil)
        return paths;
    NSMutableSet *allowed = [[paths mutableCopy] autorelease];
    [allowed minusSet: refused];
    return allowed;
}
- (void) collectionView: (NSCollectionView *) view didSelectItemsAtIndexPaths: (NSSet *) paths {
    [calls addObject: [NSString stringWithFormat: @"didSelect %@", describe(paths)]];
}
- (NSSet *) collectionView: (NSCollectionView *) view shouldDeselectItemsAtIndexPaths: (NSSet *) paths {
    [calls addObject: [NSString stringWithFormat: @"shouldDeselect %@", describe(paths)]];
    return paths;
}
- (void) collectionView: (NSCollectionView *) view didDeselectItemsAtIndexPaths: (NSSet *) paths {
    [calls addObject: [NSString stringWithFormat: @"didDeselect %@", describe(paths)]];
}
- (NSSet *) collectionView: (NSCollectionView *) view shouldChangeItemsAtIndexPaths: (NSSet *) paths
          toHighlightState: (NSCollectionViewItemHighlightState) state
{
    [calls addObject: [NSString stringWithFormat: @"shouldHighlight %@ %ld", describe(paths), (long) state]];
    return paths;
}
- (void) collectionView: (NSCollectionView *) view didChangeItemsAtIndexPaths: (NSSet *) paths
       toHighlightState: (NSCollectionViewItemHighlightState) state
{
    [calls addObject: [NSString stringWithFormat: @"didHighlight %@ %ld", describe(paths), (long) state]];
}
@end

static NSMutableArray *keep;

static NSCollectionView *makeView(Source **sourceOut)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 300)
                                                   styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)] autorelease];
    NSCollectionView *view = [[[NSCollectionView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)] autorelease];
    NSCollectionViewFlowLayout *layout = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
    layout.itemSize = NSMakeSize(80, 30);
    Source *source = [[[Source alloc] init] autorelease];
    source->count = 10;
    view.collectionViewLayout = layout;
    [view registerClass: [Item class] forItemWithIdentifier: @"item"];
    view.dataSource = source;
    view.delegate = source;
    view.selectable = YES;
    view.allowsMultipleSelection = YES;
    scroll.documentView = view;
    [window.contentView addSubview: scroll];
    [keep addObject: window];
    [keep addObject: source];
    [window release];
    [view reloadData];
    [view layoutSubtreeIfNeeded];
    [window makeKeyAndOrderFront: nil];
    [window makeFirstResponder: view];
    if (sourceOut)
        *sourceOut = source;
    [calls removeAllObjects];
    return view;
}

static NSPoint centerOf(NSInteger item)
{
    return NSMakePoint((item % 3) * 110 + 40, (item / 3) * 40 + 15);
}

static NSEvent *mouseEvent(NSCollectionView *view, NSEventType type, NSPoint point, NSEventModifierFlags flags,
                           NSInteger clicks)
{
    NSPoint inWindow = [view convertPoint: point toView: nil];
    return [NSEvent mouseEventWithType: type
                              location: inWindow
                         modifierFlags: flags
                             timestamp: [[NSProcessInfo processInfo] systemUptime]
                          windowNumber: [[view window] windowNumber]
                               context: nil
                           eventNumber: 0
                            clickCount: clicks
                              pressure: type == NSEventTypeLeftMouseUp ? 0 : 1];
}

// The drag and up events are queued first, so a tracking loop started by the down event finds them
static void drag(NSCollectionView *view, NSPoint from, NSPoint to, NSEventModifierFlags flags, NSInteger clicks)
{
    if (!NSEqualPoints(from, to)) {
        for (int step = 1; step <= 4; step++) {
            NSPoint p = NSMakePoint(from.x + (to.x - from.x) * step / 4, from.y + (to.y - from.y) * step / 4);
            [NSApp postEvent: mouseEvent(view, NSEventTypeLeftMouseDragged, p, flags, clicks) atStart: NO];
        }
    }
    [NSApp postEvent: mouseEvent(view, NSEventTypeLeftMouseUp, to, flags, clicks) atStart: NO];
    [[view window] sendEvent: mouseEvent(view, NSEventTypeLeftMouseDown, from, flags, clicks)];
    // Whatever the tracking didn't take goes through the window too
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: nil inMode: NSDefaultRunLoopMode dequeue: YES]))
        [NSApp sendEvent: event];
    [view layoutSubtreeIfNeeded];
}

static void click(NSCollectionView *view, NSInteger item, NSEventModifierFlags flags)
{
    drag(view, centerOf(item), centerOf(item), flags, 1);
}

static void key(NSCollectionView *view, unichar character, NSEventModifierFlags flags)
{
    NSString *string = [NSString stringWithCharacters: &character length: 1];
    NSEvent *event = [NSEvent keyEventWithType: NSEventTypeKeyDown
                                      location: NSZeroPoint
                                 modifierFlags: flags | NSEventModifierFlagFunction | NSEventModifierFlagNumericPad
                                     timestamp: [[NSProcessInfo processInfo] systemUptime]
                                  windowNumber: [[view window] windowNumber]
                                       context: nil
                                    characters: string
                   charactersIgnoringModifiers: string
                                     isARepeat: NO
                                       keyCode: 0];
    [[view window] sendEvent: event];
    [view layoutSubtreeIfNeeded];
}

static NSString *calls_(void)
{
    return [calls componentsJoinedByString: @"; "];
}

static NSString *log_(void)
{
    NSString *result = [calls componentsJoinedByString: @"; "];
    [calls removeAllObjects];
    return result;
}

// Checks the delegate calls since the last check, and the selection that results
static void checkCalls(const char *name, NSCollectionView *view, NSString *wantCalls, NSString *wantSelection)
{
    NSString *got = log_();
    expect([got isEqual: wantCalls], "%s: calls [%s] (want [%s])", name, [got UTF8String], [wantCalls UTF8String]);
    NSString *selection = describe(view.selectionIndexPaths);
    expect([selection isEqual: wantSelection], "%s: selection {%s} (want {%s})", name, [selection UTF8String],
           [wantSelection UTF8String]);
}

// The calls a rubber band makes while it moves aren't checked, only the ones that end it
static void checkCallsEnd(const char *name, NSCollectionView *view, NSString *wantEnd, NSString *wantSelection)
{
    NSString *got = log_();
    expect([got hasSuffix: wantEnd], "%s: calls end [%s] (got [%s])", name, [wantEnd UTF8String], [got UTF8String]);
    NSString *selection = describe(view.selectionIndexPaths);
    expect([selection isEqual: wantSelection], "%s: selection {%s} (want {%s})", name, [selection UTF8String],
           [wantSelection UTF8String]);
}

static void test_click_selects_only_that_item(void)
{
    NSCollectionView *view = makeView(NULL);
    click(view, 4, 0);
    checkCalls("click 4", view, @"shouldHighlight 4 1; didHighlight 4 1; shouldSelect 4; didSelect 4; shouldHighlight 4 0; "
          "didHighlight 4 0", @"4");
    click(view, 7, 0);
    checkCalls("then click 7", view, @"shouldHighlight 7 1; didHighlight 7 1; shouldHighlight 4 2; didHighlight 4 2; "
          "shouldDeselect 4; didDeselect 4; shouldHighlight 4 0; didHighlight 4 0; shouldSelect 7; didSelect 7; "
          "shouldHighlight 7 0; didHighlight 7 0", @"7");
    NSCollectionViewItem *item = [view itemAtIndexPath: [NSIndexPath indexPathForItem: 7 inSection: 0]];
    expect(item.selected && item.highlightState == NSCollectionViewItemHighlightNone,
           "the clicked item is selected and no longer highlighted (%ld)", (long) item.highlightState);
}

static void test_click_selected_item_changes_nothing(void)
{
    NSCollectionView *view = makeView(NULL);
    view.selectionIndexPaths = [NSSet setWithObjects: [NSIndexPath indexPathForItem: 1 inSection: 0],
                                                      [NSIndexPath indexPathForItem: 4 inSection: 0], nil];
    [calls removeAllObjects];
    click(view, 1, 0);
    checkCalls("click selected 1 of 1,4", view, @"", @"1,4");
}

static void test_command_click_toggles(void)
{
    NSCollectionView *view = makeView(NULL);
    click(view, 7, 0);
    log_();
    click(view, 2, NSEventModifierFlagCommand);
    checkCalls("then cmd-click 2", view, @"shouldHighlight 2 1; didHighlight 2 1; shouldSelect 2; didSelect 2; "
          "shouldHighlight 2 0; didHighlight 2 0", @"2,7");
    click(view, 7, NSEventModifierFlagCommand);
    checkCalls("then cmd-click 7", view, @"shouldHighlight 7 2; didHighlight 7 2; shouldDeselect 7; didDeselect 7; "
          "shouldHighlight 7 0; didHighlight 7 0", @"2");
}

static void test_shift_click_extends(void)
{
    // Shift adds the clicked item only, not the items between
    NSCollectionView *view = makeView(NULL);
    click(view, 1, 0);
    log_();
    click(view, 5, NSEventModifierFlagShift);
    checkCalls("click 1, shift-click 5", view, @"shouldHighlight 5 1; didHighlight 5 1; shouldSelect 5; didSelect 5; "
          "shouldHighlight 5 0; didHighlight 5 0", @"1,5");
    click(view, 3, NSEventModifierFlagShift);
    checkCalls("then shift-click 3", view, @"shouldHighlight 3 1; didHighlight 3 1; shouldSelect 3; didSelect 3; "
          "shouldHighlight 3 0; didHighlight 3 0", @"1,3,5");
}

static void test_click_background_deselects(void)
{
    NSCollectionView *view = makeView(NULL);
    click(view, 4, 0);
    log_();
    drag(view, NSMakePoint(95, 15), NSMakePoint(95, 15), 0, 1);
    checkCalls("click 4, click the background", view, @"shouldDeselect 4; didDeselect 4; shouldHighlight 4 0; didHighlight 4 0",
          @"");
    view = makeView(NULL);
    view.allowsEmptySelection = NO;
    click(view, 4, 0);
    log_();
    drag(view, NSMakePoint(95, 15), NSMakePoint(95, 15), 0, 1);
    checkCalls("without empty selection: click 4, click the background", view, @"", @"4");
}

static void test_delegate_filters_selection(void)
{
    Source *source;
    NSCollectionView *view = makeView(&source);
    source->refused = [[NSSet setWithObject: [NSIndexPath indexPathForItem: 3 inSection: 0]] retain];
    click(view, 3, 0);
    checkCalls("3 refused: click 3", view, @"shouldHighlight 3 1; didHighlight 3 1; shouldSelect 3; shouldHighlight 3 0; "
          "didHighlight 3 0", @"");
    click(view, 0, 0);
    log_();
    drag(view, NSMakePoint(200, 35), NSMakePoint(5, 60), NSEventModifierFlagShift, 1);
    checkCallsEnd("3 refused: click 0, shift-rubber band over 3 and 4", view, @"shouldSelect 3,4; didSelect 4; "
             "shouldHighlight 3,4 0; didHighlight 3,4 0", @"0,4");
}

static void test_rubber_band_selects_intersecting(void)
{
    NSCollectionView *view = makeView(NULL);
    drag(view, NSMakePoint(95, 5), NSMakePoint(200, 60), 0, 1);
    NSString *during = calls_();
    expect([during rangeOfString: @"shouldHighlight 1 1"].location != NSNotFound &&
           [during rangeOfString: @"shouldHighlight 4 1"].location != NSNotFound,
           "the band highlights the items it reaches: [%s]", [during UTF8String]);
    checkCallsEnd("rubber band from {95, 5} to {200, 60}", view, @"shouldSelect 1,4; didSelect 1,4; "
             "shouldHighlight 1,4 0; didHighlight 1,4 0", @"1,4");
    // With command, a band that starts over a selected item deselects the items it covers
    click(view, 1, 0);
    log_();
    drag(view, NSMakePoint(95, 5), NSMakePoint(200, 60), NSEventModifierFlagCommand, 1);
    checkCallsEnd("click 1, cmd-rubber band", view, @"shouldDeselect 1,4; didDeselect 1,4; shouldHighlight 1,4 0; "
             "didHighlight 1,4 0", @"");
}

static void test_arrow_keys_move_by_geometry(void)
{
    NSCollectionView *view = makeView(NULL);
    click(view, 4, 0);
    log_();
    struct {
        unichar key;
        const char *name;
        NSInteger from, to; // -1: the selection stays
    } moves[] = {
        {NSRightArrowFunctionKey, "right", 4, 5}, {NSLeftArrowFunctionKey, "left", 5, 4},
        {NSUpArrowFunctionKey, "up", 4, 1}, {NSDownArrowFunctionKey, "down", 1, 4}, {NSDownArrowFunctionKey, "down", 4, 7},
        {NSRightArrowFunctionKey, "right", 7, 8}, {NSRightArrowFunctionKey, "right at the end of a row", 8, -1},
    };
    for (size_t i = 0; i < sizeof(moves) / sizeof(moves[0]); i++) {
        key(view, moves[i].key, 0);
        char name[64];
        snprintf(name, sizeof(name), "%s from %ld", moves[i].name, (long) moves[i].from);
        if (moves[i].to < 0)
            checkCalls(name, view, @"", [NSString stringWithFormat: @"%ld", (long) moves[i].from]);
        else
            checkCalls(name, view, [NSString stringWithFormat: @"shouldDeselect %ld; didDeselect %ld; shouldSelect %ld; "
                               "didSelect %ld", (long) moves[i].from, (long) moves[i].from, (long) moves[i].to,
                               (long) moves[i].to], [NSString stringWithFormat: @"%ld", (long) moves[i].to]);
    }
    view = makeView(NULL);
    key(view, NSRightArrowFunctionKey, 0);
    checkCalls("nothing selected, right", view, @"", @"");
    key(view, NSDownArrowFunctionKey, 0);
    checkCalls("nothing selected, down", view, @"", @"");
}

static void test_shift_arrow_extends(void)
{
    NSCollectionView *view = makeView(NULL);
    click(view, 4, 0);
    log_();
    key(view, NSRightArrowFunctionKey, NSEventModifierFlagShift);
    checkCalls("click 4, shift-right", view, @"shouldSelect 5; didSelect 5", @"4,5");
    key(view, NSDownArrowFunctionKey, NSEventModifierFlagShift);
    checkCalls("then shift-down", view, @"shouldSelect 6,7,8; didSelect 6,7,8", @"4,5,6,7,8");
    key(view, NSUpArrowFunctionKey, NSEventModifierFlagShift);
    checkCalls("then shift-up", view, @"shouldDeselect 6,7,8; didDeselect 6,7,8", @"4,5");
}

static void test_not_selectable_ignores_clicks(void)
{
    NSCollectionView *view = makeView(NULL);
    view.selectable = NO;
    click(view, 4, 0);
    checkCalls("not selectable: click 4", view, @"", @"");
}

static void test_single_selection(void)
{
    NSCollectionView *view = makeView(NULL);
    view.allowsMultipleSelection = NO;
    click(view, 4, 0);
    log_();
    click(view, 5, NSEventModifierFlagCommand);
    checkCalls("single selection: click 4, cmd-click 5", view, @"shouldHighlight 5 1; didHighlight 5 1; shouldSelect 5; "
          "didSelect 5; shouldHighlight 5 0; didHighlight 5 0; shouldDeselect 4; didDeselect 4; shouldHighlight 4 0; "
          "didHighlight 4 0", @"5");
    drag(view, NSMakePoint(95, 5), NSMakePoint(200, 60), 0, 1);
    checkCalls("single selection: a rubber band selects nothing", view, @"shouldDeselect 5; didDeselect 5; "
          "shouldHighlight 5 0; didHighlight 5 0", @"");
}

static void test_double_click_reaches_item_view(void)
{
    NSCollectionView *view = makeView(NULL);
    click(view, 6, 0);
    log_();
    drag(view, centerOf(6), centerOf(6), 0, 2);
    ItemView *itemView = (ItemView *) [[view itemAtIndexPath: [NSIndexPath indexPathForItem: 6 inSection: 0]] view];
    expect(itemView->lastClickCount == 2 && itemView->selectedAtClick,
           "the item view gets the double click, its item already selected (clicks %ld, selected %d)",
           (long) itemView->lastClickCount, itemView->selectedAtClick);
    checkCalls("double click on the selected item 6", view, @"", @"6");
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    keep = [[NSMutableArray alloc] init];
    calls = [[NSMutableArray alloc] init];
    // The first click of the process activates the application and its mouse up comes late; it isn't part of any case
    NSCollectionView *view = makeView(NULL);
    click(view, 0, 0);
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: nil inMode: NSDefaultRunLoopMode dequeue: YES]))
        [NSApp sendEvent: event];

    test_click_selects_only_that_item();
    test_click_selected_item_changes_nothing();
    test_command_click_toggles();
    test_shift_click_extends();
    test_click_background_deselects();
    test_delegate_filters_selection();
    test_rubber_band_selects_intersecting();
    test_arrow_keys_move_by_geometry();
    test_shift_arrow_extends();
    test_not_selectable_ignores_clicks();
    test_single_selection();
    test_double_click_reaches_item_view();

    [calls release];
    [keep release];
    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
