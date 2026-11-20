// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// NSCollectionView's selection model: the defaults, programmatic selection
// (which the documentation says does not consult the delegate), the items'
// selected state, select all, key-value observing, what a relayout and a
// shrinking reload keep, and the legacy selectionIndexes. Values the
// documentation does not pin were observed on macOS 26.7.3 and 10.14.4
// (darling's tests/collection-view.md); the program passes unchanged on both.
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

@interface Item : NSCollectionViewItem
@end
@implementation Item
- (void) loadView {
    self.view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
}
@end

// The data source, and a delegate that counts the selection calls it gets
@interface Source : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate> {
@public
    NSInteger count;
    NSUInteger delegateCalls;
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
    delegateCalls++;
    return paths;
}
- (void) collectionView: (NSCollectionView *) view didSelectItemsAtIndexPaths: (NSSet *) paths {
    delegateCalls++;
}
- (NSSet *) collectionView: (NSCollectionView *) view shouldDeselectItemsAtIndexPaths: (NSSet *) paths {
    delegateCalls++;
    return paths;
}
- (void) collectionView: (NSCollectionView *) view didDeselectItemsAtIndexPaths: (NSSet *) paths {
    delegateCalls++;
}
@end

@interface Observer : NSObject {
@public
    NSUInteger changes;
}
@end
@implementation Observer
- (void) observeValueForKeyPath: (NSString *) keyPath ofObject: (id) object change: (NSDictionary *) change
                        context: (void *) context
{
    changes++;
}
@end

static NSMutableArray *keep;

static NSCollectionView *makeView(NSInteger count, Source **sourceOut)
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
    source->count = count;
    view.collectionViewLayout = layout;
    [view registerClass: [Item class] forItemWithIdentifier: @"item"];
    view.dataSource = source;
    view.delegate = source;
    scroll.documentView = view;
    [window.contentView addSubview: scroll];
    [keep addObject: window];
    [keep addObject: source];
    [window release];
    [view reloadData];
    [view layoutSubtreeIfNeeded];
    if (sourceOut)
        *sourceOut = source;
    return view;
}

static NSIndexPath *path(NSInteger item)
{
    return [NSIndexPath indexPathForItem: item inSection: 0];
}

// The items, ended by -1
static NSSet *paths(int first, ...)
{
    NSMutableSet *set = [NSMutableSet set];
    va_list ap;
    va_start(ap, first);
    for (int item = first; item >= 0; item = va_arg(ap, int))
        [set addObject: path(item)];
    va_end(ap);
    return set;
}

static NSString *describe(NSSet *set)
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSIndexPath *p in set)
        [items addObject: [NSString stringWithFormat: @"%ld/%ld", (long) p.section, (long) p.item]];
    [items sortUsingSelector: @selector(compare:)];
    return [items componentsJoinedByString: @" "];
}

static void test_selection_defaults(void)
{
    NSCollectionView *view = [[[NSCollectionView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    expect(!view.selectable, "not selectable by default");
    expect(!view.allowsMultipleSelection, "no multiple selection by default");
    expect(view.allowsEmptySelection, "empty selection allowed by default");
    expect(view.selectionIndexPaths != nil && [view.selectionIndexPaths count] == 0, "no selection (%s)",
           view.selectionIndexPaths == nil ? "nil" : "empty set");
    expect(view.selectionIndexes != nil && [view.selectionIndexes count] == 0, "no selection indexes (%s)",
           view.selectionIndexes == nil ? "nil" : "empty");
}

static void test_programmatic_selection_skips_delegate(void)
{
    Source *source;
    NSCollectionView *view = makeView(10, &source);
    view.selectable = YES;
    view.allowsMultipleSelection = YES;
    [view selectItemsAtIndexPaths: paths(1, 3, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    expect([view.selectionIndexPaths isEqual: paths(1, 3, -1)], "selectItemsAtIndexPaths: selects them (%s)",
           [describe(view.selectionIndexPaths) UTF8String]);
    [view deselectItemsAtIndexPaths: paths(1, -1)];
    expect([view.selectionIndexPaths isEqual: paths(3, -1)], "deselectItemsAtIndexPaths: deselects (%s)",
           [describe(view.selectionIndexPaths) UTF8String]);
    expect(source->delegateCalls == 0, "the delegate is not asked or told (%lu)", (unsigned long) source->delegateCalls);

    // Programmatic selection works whether or not the view is selectable, and keeps several paths without multiple
    // selection
    NSCollectionView *plain = makeView(10, NULL);
    [plain selectItemsAtIndexPaths: paths(2, 4, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    expect([plain.selectionIndexPaths isEqual: paths(2, 4, -1)], "a view that isn't selectable is selected too (%s)",
           [describe(plain.selectionIndexPaths) UTF8String]);
}

static void test_items_reflect_selection(void)
{
    NSCollectionView *view = makeView(5000, NULL);
    [view selectItemsAtIndexPaths: paths(1, 4000, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    NSCollectionViewItem *one = [view itemAtIndexPath: path(1)], *two = [view itemAtIndexPath: path(2)];
    expect(one.selected && !two.selected, "a visible item is selected, its neighbour is not (%d, %d)", one.selected,
           two.selected);
    expect(one.highlightState == NSCollectionViewItemHighlightNone, "programmatic selection leaves no highlight (%ld)",
           (long) one.highlightState);
    [view scrollToItemsAtIndexPaths: paths(4000, -1) scrollPosition: NSCollectionViewScrollPositionTop];
    [view layoutSubtreeIfNeeded];
    NSCollectionViewItem *later = [view itemAtIndexPath: path(4000)], *next = [view itemAtIndexPath: path(4001)];
    expect(later != nil && later.selected, "an item made later for a selected path is selected");
    expect(next != nil && !next.selected, "one reused for a path that isn't selected is not");
    [view deselectItemsAtIndexPaths: paths(4000, -1)];
    expect(!later.selected, "deselecting updates the visible item");
}

static void test_select_all_respects_multiple(void)
{
    NSCollectionView *view = makeView(10, NULL);
    view.selectable = YES;
    [view selectAll: nil];
    expect([view.selectionIndexPaths count] == 0, "selectAll: without multiple selection selects nothing (%lu)",
           (unsigned long) [view.selectionIndexPaths count]);
    view.allowsMultipleSelection = YES;
    [view selectAll: nil];
    expect([view.selectionIndexPaths count] == 10, "with multiple selection it selects every item (%lu)",
           (unsigned long) [view.selectionIndexPaths count]);
    [view deselectAll: nil];
    expect([view.selectionIndexPaths count] == 0, "deselectAll: empties the selection (%lu)",
           (unsigned long) [view.selectionIndexPaths count]);
}

static void test_kvo_notifies_selection(void)
{
    NSCollectionView *view = makeView(10, NULL);
    Observer *observer = [[[Observer alloc] init] autorelease];
    [view addObserver: observer forKeyPath: @"selectionIndexPaths" options: 0 context: NULL];
    view.selectionIndexPaths = paths(5, -1);
    expect(observer->changes == 1, "setting selectionIndexPaths notifies its observers (%lu)", (unsigned long) observer->changes);
    // Not documented: the selecting and deselecting methods change the selection without a notification
    [view selectItemsAtIndexPaths: paths(2, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    [view deselectItemsAtIndexPaths: paths(5, -1)];
    expect(observer->changes == 1, "selectItemsAtIndexPaths: and deselectItemsAtIndexPaths: don't (%lu)",
           (unsigned long) observer->changes);
    expect([view.selectionIndexPaths isEqual: paths(2, -1)], "though the selection changed (%s)",
           [describe(view.selectionIndexPaths) UTF8String]);
    [view removeObserver: observer forKeyPath: @"selectionIndexPaths"];
}

static void test_selection_survives_relayout(void)
{
    NSCollectionView *view = makeView(10, NULL);
    [view selectItemsAtIndexPaths: paths(3, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    [view.collectionViewLayout invalidateLayout];
    [view layoutSubtreeIfNeeded];
    expect([view.selectionIndexPaths isEqual: paths(3, -1)], "a relayout keeps the selection");
    expect([view itemAtIndexPath: path(3)].selected, "and the item stays selected");
}

static void test_reload_drops_selection(void)
{
    Source *source;
    NSCollectionView *view = makeView(10, &source);
    [view selectItemsAtIndexPaths: paths(1, 8, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    source->count = 3;
    [view reloadData];
    [view layoutSubtreeIfNeeded];
    expect([view.selectionIndexPaths count] == 0, "a reload with fewer items empties the selection (%s)",
           [describe(view.selectionIndexPaths) UTF8String]);
    expect(![view itemAtIndexPath: path(1)].selected, "and no item is selected");

    [view selectItemsAtIndexPaths: paths(2, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    [view reloadData];
    [view layoutSubtreeIfNeeded];
    expect([view.selectionIndexPaths count] == 0, "so does a reload with the same items (%s)",
           [describe(view.selectionIndexPaths) UTF8String]);
}

static void test_legacy_selection_indexes(void)
{
    NSCollectionView *view = makeView(10, NULL);
    view.selectionIndexes = [NSIndexSet indexSetWithIndex: 2];
    expect([view.selectionIndexPaths isEqual: paths(2, -1)], "selectionIndexes are section 0's paths (%s)",
           [describe(view.selectionIndexPaths) UTF8String]);
    [view selectItemsAtIndexPaths: paths(4, -1) scrollPosition: NSCollectionViewScrollPositionNone];
    NSIndexSet *indexes = view.selectionIndexes;
    expect([indexes containsIndex: 2] && [indexes containsIndex: 4] && [indexes count] == 2,
           "and follow selectionIndexPaths (%lu indexes)", (unsigned long) [indexes count]);
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    keep = [[NSMutableArray alloc] init];
    test_selection_defaults();
    test_programmatic_selection_skips_delegate();
    test_items_reflect_selection();
    test_select_all_respects_multiple();
    test_kvo_notifies_selection();
    test_selection_survives_relayout();
    test_reload_drops_selection();
    test_legacy_selection_indexes();
    [keep release];
    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
