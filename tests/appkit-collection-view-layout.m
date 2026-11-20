// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// NSCollectionView places its items where its layout says, makes items only
// for the visible part of its content, and reuses the items that scroll out of
// view. Values the documentation does not pin were observed on macOS 26.7.3
// and 10.14.4 (darling's tests/collection-view.md); the program passes
// unchanged on both.
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

static NSUInteger itemsMade, itemsReused;

@interface Item : NSCollectionViewItem
@end
@implementation Item
- (instancetype) initWithNibName: (NSString *) name bundle: (NSBundle *) bundle {
    if ((self = [super initWithNibName: name bundle: bundle]) != nil)
        itemsMade++;
    return self;
}
- (void) loadView {
    self.view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
}
- (void) prepareForReuse {
    itemsReused++;
    [super prepareForReuse];
}
@end

@interface Source : NSObject <NSCollectionViewDataSource> {
@public
    NSInteger count;
    NSUInteger asked; // items the collection view asked for
}
@end
@implementation Source
- (NSInteger) collectionView: (NSCollectionView *) view numberOfItemsInSection: (NSInteger) section {
    return count;
}
- (NSCollectionViewItem *) collectionView: (NSCollectionView *) view itemForRepresentedObjectAtIndexPath: (NSIndexPath *) path {
    asked++;
    return [view makeItemWithIdentifier: @"item" forIndexPath: path];
}
@end

// Puts item i at {10 + 100 i, 20} in a 50x40 frame with alpha 0.5, in a 400x300 content
@interface FixedLayout : NSCollectionViewLayout {
@public
    NSUInteger prepared;
}
@end
@implementation FixedLayout
- (void) prepareLayout {
    [super prepareLayout];
    prepared++;
}
- (NSSize) collectionViewContentSize {
    return NSMakeSize(400, 300);
}
- (NSCollectionViewLayoutAttributes *) layoutAttributesForItemAtIndexPath: (NSIndexPath *) path {
    NSCollectionViewLayoutAttributes *a = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath: path];
    a.frame = NSMakeRect(10 + 100 * path.item, 20, 50, 40);
    a.alpha = 0.5;
    return a;
}
- (NSArray *) layoutAttributesForElementsInRect: (NSRect) rect {
    NSMutableArray *result = [NSMutableArray array];
    NSInteger count = [self.collectionView numberOfItemsInSection: 0];
    for (NSInteger i = 0; i < count; i++) {
        NSCollectionViewLayoutAttributes *a = [self layoutAttributesForItemAtIndexPath: [NSIndexPath indexPathForItem: i
                                                                                                           inSection: 0]];
        if (NSIntersectsRect(a.frame, rect))
            [result addObject: a];
    }
    return result;
}
@end

// Records the contexts it is invalidated with
@interface RecordingFlow : NSCollectionViewFlowLayout {
@public
    NSMutableArray *contexts;
}
@end
@implementation RecordingFlow
- (void) invalidateLayoutWithContext: (NSCollectionViewLayoutInvalidationContext *) context {
    if (contexts == nil)
        contexts = [[NSMutableArray alloc] init];
    [contexts addObject: context];
    [super invalidateLayoutWithContext: context];
}
- (void) dealloc {
    [contexts release];
    [super dealloc];
}
@end

static NSMutableArray *keep;

static NSCollectionView *makeView(NSSize size, NSCollectionViewLayout *layout, NSInteger count, Source **sourceOut)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, size.width, size.height)
                                                   styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, size.width, size.height)] autorelease];
    NSCollectionView *view = [[[NSCollectionView alloc] initWithFrame: NSMakeRect(0, 0, size.width, size.height)] autorelease];
    Source *source = [[[Source alloc] init] autorelease];
    source->count = count;
    view.collectionViewLayout = layout;
    [view registerClass: [Item class] forItemWithIdentifier: @"item"];
    view.dataSource = source;
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

static NSCollectionViewFlowLayout *flow(void)
{
    NSCollectionViewFlowLayout *layout = [[[NSCollectionViewFlowLayout alloc] init] autorelease];
    layout.itemSize = NSMakeSize(80, 30);
    return layout;
}

static void test_items_follow_custom_layout(void)
{
    FixedLayout *layout = [[[FixedLayout alloc] init] autorelease];
    NSCollectionView *view = makeView(NSMakeSize(300, 200), layout, 3, NULL);
    for (NSInteger i = 0; i < 2; i++) {
        NSCollectionViewItem *item = [view itemAtIndexPath: [NSIndexPath indexPathForItem: i inSection: 0]];
        NSRect want = NSMakeRect(10 + 100 * i, 20, 50, 40);
        expect(item != nil && [item.view superview] == view && NSEqualRects(item.view.frame, want),
               "item %ld is placed at its layout frame %s (%s)", (long) i, [NSStringFromRect(want) UTF8String],
               [NSStringFromRect(item.view.frame) UTF8String]);
        expect(item.view.alphaValue == 0.5, "item %ld has its layout alpha (%g)", (long) i, (double) item.view.alphaValue);
    }
    // A layout that isn't a horizontal flow scrolls vertically: the view keeps the clip view's width, 300, and grows
    // to the content's height, 300
    expect(NSEqualSizes(view.frame.size, NSMakeSize(300, 300)), "the view is as high as the content and as wide as the "
           "clip view (%s)", [NSStringFromSize(view.frame.size) UTF8String]);
    // Item 2 at x 210 is visible in the 300 wide clip view too
    expect([[view visibleItems] count] == 3, "visible items: %lu", (unsigned long) [[view visibleItems] count]);
}

static void test_prepare_layout_once_per_invalidation(void)
{
    FixedLayout *layout = [[[FixedLayout alloc] init] autorelease];
    NSCollectionView *view = makeView(NSMakeSize(300, 200), layout, 3, NULL);
    NSUInteger before = layout->prepared;
    expect(before >= 1, "the layout was prepared (%lu)", (unsigned long) before);
    [view layoutSubtreeIfNeeded];
    [view layoutSubtreeIfNeeded];
    expect(layout->prepared == before, "layout passes without an invalidation don't prepare it again (%lu)",
           (unsigned long) layout->prepared);
    [layout invalidateLayout];
    [view layoutSubtreeIfNeeded];
    expect(layout->prepared == before + 1, "an invalidation prepares it once more (%lu)", (unsigned long) layout->prepared);
}

static void test_only_visible_items_are_made(void)
{
    Source *source;
    itemsMade = 0;
    NSCollectionView *view = makeView(NSMakeSize(300, 300), flow(), 5000, &source);
    expect(source->asked > 0 && source->asked < 100, "the data source is asked for the visible items only (%lu)",
           (unsigned long) source->asked);
    expect(itemsMade == source->asked, "an item is made for each (%lu)", (unsigned long) itemsMade);
    NSUInteger visible = [[view visibleItems] count];
    expect(visible == [[view indexPathsForVisibleItems] count], "visibleItems and indexPathsForVisibleItems agree (%lu)",
           (unsigned long) visible);
    // 80x30 items, 3 per row, rows 40 apart: 1667 rows, the last one ends at 66 670
    expect(NSHeight(view.frame) == 66670, "the view is as high as the content (%g)", (double) NSHeight(view.frame));
}

static void test_scroll_reuses_items(void)
{
    Source *source;
    itemsMade = 0;
    itemsReused = 0;
    NSCollectionView *view = makeView(NSMakeSize(300, 300), flow(), 5000, &source);
    NSUInteger visible = [[view visibleItems] count];
    NSClipView *clip = (NSClipView *) [view superview];
    [clip scrollToPoint: NSMakePoint(0, NSHeight(view.frame) - 300)];
    [[clip enclosingScrollView] reflectScrolledClipView: clip];
    [view layoutSubtreeIfNeeded];
    NSIndexPath *last = [NSIndexPath indexPathForItem: 4999 inSection: 0];
    expect([view itemAtIndexPath: last] != nil, "after scrolling to the end the last item is there");
    expect([view itemAtIndexPath: [NSIndexPath indexPathForItem: 0 inSection: 0]] == nil, "the first one is gone");
    expect(itemsMade <= visible + 3, "items are reused: %lu made for %lu visible", (unsigned long) itemsMade,
           (unsigned long) visible);
    expect(itemsReused > 0, "prepareForReuse is called on reused items (%lu)", (unsigned long) itemsReused);
}

static void test_index_path_queries(void)
{
    NSCollectionView *view = makeView(NSMakeSize(300, 300), flow(), 10, NULL);
    NSIndexPath *path = [NSIndexPath indexPathForItem: 4 inSection: 0];
    NSCollectionViewItem *item = [view itemAtIndexPath: path];
    expect([[view indexPathForItem: item] isEqual: path], "indexPathForItem: of item 4");
    // 300 wide: columns at 0, 110, 220; item 4 is row 1, column 1
    NSRect frame = NSMakeRect(110, 40, 80, 30);
    expect(NSEqualRects(item.view.frame, frame), "item 4 at %s (%s)", [NSStringFromRect(frame) UTF8String],
           [NSStringFromRect(item.view.frame) UTF8String]);
    expect([[view indexPathForItemAtPoint: NSMakePoint(150, 55)] isEqual: path], "indexPathForItemAtPoint: inside item 4");
    expect([view indexPathForItemAtPoint: NSMakePoint(95, 55)] == nil, "no index path between items");
    expect(NSEqualRects([view layoutAttributesForItemAtIndexPath: path].frame, frame),
           "layoutAttributesForItemAtIndexPath: is the layout's");
    expect(NSEqualRects([view frameForItemAtIndex: 4], frame), "frameForItemAtIndex: 4 is its frame (%s)",
           [NSStringFromRect([view frameForItemAtIndex: 4]) UTF8String]);
    expect([[view indexPathsForVisibleItems] containsObject: path], "item 4 is among the visible index paths");
}

static void test_document_view_size(void)
{
    // Ten items fill four rows (150 high) of a 300 high clip view
    NSCollectionView *view = makeView(NSMakeSize(300, 300), flow(), 10, NULL);
    NSSize clip = [[view superview] bounds].size;
    expect(NSWidth(view.frame) == clip.width, "a short content: the view is as wide as the clip view (%g)",
           (double) NSWidth(view.frame));
    expect(NSHeight(view.frame) == clip.height, "a short content: the view is as high as the clip view (%g)",
           (double) NSHeight(view.frame));

    // A horizontal flow grows in width instead: five items in columns of two, 260 wide, in a 200x100 clip view
    NSCollectionViewFlowLayout *horizontal = flow();
    horizontal.scrollDirection = NSCollectionViewScrollDirectionHorizontal;
    view = makeView(NSMakeSize(200, 100), horizontal, 5, NULL);
    expect(NSEqualSizes(view.frame.size, NSMakeSize(260, 100)), "a horizontal flow: as wide as the content, as high as "
           "the clip view (%s)", [NSStringFromSize(view.frame.size) UTF8String]);
}

static void test_reload_after_count_change(void)
{
    Source *source;
    NSCollectionView *view = makeView(NSMakeSize(300, 300), flow(), 10, &source);
    NSCollectionViewItem *old = [view itemAtIndexPath: [NSIndexPath indexPathForItem: 9 inSection: 0]];
    source->count = 3;
    source->asked = 0;
    [view reloadData];
    expect(source->asked == 0, "reloadData asks for no item before the next layout pass (%lu)", (unsigned long) source->asked);
    [view layoutSubtreeIfNeeded];
    expect([view numberOfItemsInSection: 0] == 3, "the count is the new one");
    expect([[view visibleItems] count] == 3, "three visible items (%lu)", (unsigned long) [[view visibleItems] count]);
    expect([view itemAtIndexPath: [NSIndexPath indexPathForItem: 9 inSection: 0]] == nil, "no item 9");
    expect(old.view.superview == nil || old.view.isHidden, "a stale item's view isn't shown");
}

static void test_reload_invalidates_everything(void)
{
    RecordingFlow *layout = [[[RecordingFlow alloc] init] autorelease];
    layout.itemSize = NSMakeSize(80, 30);
    NSCollectionView *view = makeView(NSMakeSize(300, 300), layout, 10, NULL);
    [layout->contexts removeAllObjects];
    [view reloadData];
    NSCollectionViewLayoutInvalidationContext *context = [layout->contexts lastObject];
    expect([layout->contexts count] == 1, "reloadData invalidates the layout once (%lu)", (unsigned long) [layout->contexts count]);
    expect(context.invalidateEverything && context.invalidateDataSourceCounts,
           "with a context that invalidates everything and the counts (%d, %d)", context.invalidateEverything,
           context.invalidateDataSourceCounts);
}

static void test_default_background(void)
{
    NSCollectionView *view = [[[NSCollectionView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSArray *colors = view.backgroundColors;
    expect([colors count] == 1 && [[colors objectAtIndex: 0] isEqual: [NSColor controlBackgroundColor]],
           "the background colors are the control background color (%s)", [[colors description] UTF8String]);
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    keep = [[NSMutableArray alloc] init];
    test_items_follow_custom_layout();
    test_prepare_layout_once_per_invalidation();
    test_only_visible_items_are_made();
    test_scroll_reuses_items();
    test_index_path_queries();
    test_document_view_size();
    test_reload_after_count_change();
    test_reload_invalidates_everything();
    test_default_background();
    [keep release];
    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
