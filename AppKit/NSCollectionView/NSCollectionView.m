/* Copyright (c) 2009 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSCollectionView.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSCollectionViewFlowLayout.h>
#import <AppKit/NSCollectionViewLayoutAttributes.h>
#import <AppKit/NSCollectionViewLayoutInvalidationContext.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSDraggingItem.h>
#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <Foundation/NSNotification.h>
#include <math.h>

// Exported by AppKit but not declared in the public headers.
APPKIT_EXPORT NSString *const NSCollectionElementKindSelectionRectIndicator;
NSString *const NSCollectionElementKindSelectionRectIndicator =
        @"NSCollectionElementKindSelectionRectIndicator";

// The private interface to UIFoundation's collection view layouts (UIFoundation's NSCollectionViewLayoutPrivate.h)
@interface NSCollectionViewLayout (NSCollectionViewPrivate)
- (void) _setCollectionView: (NSCollectionView *) collectionView;
@end

@interface NSCollectionViewLayoutInvalidationContext (NSCollectionViewPrivate)
- (void) _setInvalidateEverything: (BOOL) invalidate;
- (void) _setInvalidateDataSourceCounts: (BOOL) invalidate;
@end

@interface NSCollectionViewItem (NSCollectionViewPrivate)
- (void) _setCollectionView: (NSCollectionView *) collectionView;
@end

// QUIRK: a collection view in a clip view grows along one axis only. A horizontal flow layout makes it as wide as its
// content and as high as the clip view; every other layout makes it as wide as the clip view, even when the content is
// wider, and as high as its content. Either way it is at least as large as the clip view.
// Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's
// tests/collection-view.md). Test: test_document_view_size and test_items_follow_custom_layout in
// tests/appkit-collection-view-layout.m.
static NSSize sizeInClipView(NSCollectionViewLayout *layout, NSSize content, NSSize clip)
{
    BOOL horizontal = [layout isKindOfClass: [NSCollectionViewFlowLayout class]] &&
                      [(NSCollectionViewFlowLayout *) layout scrollDirection] == NSCollectionViewScrollDirectionHorizontal;
    if (horizontal)
        return NSMakeSize(MAX(content.width, clip.width), clip.height);
    return NSMakeSize(clip.width, MAX(content.height, clip.height));
}

// The translucent rectangle a rubber band selection draws over the items
@interface _NSCollectionViewRubberBand : NSView
@end

@implementation _NSCollectionViewRubberBand
- (NSView *) hitTest: (NSPoint) point {
    return nil;
}
- (void) drawRect: (NSRect) dirtyRect {
    NSRect bounds = NSInsetRect([self bounds], 0.5, 0.5);
    [[[NSColor selectedControlColor] colorWithAlphaComponent: 0.3] setFill];
    NSRectFillUsingOperation([self bounds], NSCompositingOperationSourceOver);
    [[NSColor selectedControlColor] setStroke];
    [NSBezierPath strokeRect: bounds];
}
@end

// The bar a drop between items shows in the gap it goes to
@interface _NSCollectionViewDropGapIndicator : NSView
@end

@implementation _NSCollectionViewDropGapIndicator
- (NSView *) hitTest: (NSPoint) point {
    return nil;
}
- (void) drawRect: (NSRect) dirtyRect {
    NSRect bounds = [self bounds];
    BOOL vertical = NSHeight(bounds) >= NSWidth(bounds);
    CGFloat thickness = 2;
    NSRect bar = vertical ? NSMakeRect(NSMidX(bounds) - thickness / 2, NSMinY(bounds), thickness, NSHeight(bounds))
                          : NSMakeRect(NSMinX(bounds), NSMidY(bounds) - thickness / 2, NSWidth(bounds), thickness);
    [[NSColor alternateSelectedControlColor] setFill];
    NSRectFill(bar);
}
@end

// How far the mouse moves from where it was pressed on an item before a drag starts
static const CGFloat dragThreshold = 3;

// Orders item views by their layout attributes' zIndex; views that aren't items (the background view) stay below
static NSInteger compareZIndex(id first, id second, void *context)
{
    NSDictionary *zIndexes = (NSDictionary *) context;
    NSNumber *a = [zIndexes objectForKey: [NSValue valueWithNonretainedObject: first]];
    NSNumber *b = [zIndexes objectForKey: [NSValue valueWithNonretainedObject: second]];
    NSInteger za = a ? [a integerValue] : NSIntegerMin, zb = b ? [b integerValue] : NSIntegerMin;
    return za < zb ? NSOrderedAscending : za > zb ? NSOrderedDescending : NSOrderedSame;
}

@implementation NSCollectionView

// Operated at once: the click that activates the window is delivered to it
// (see -[NSWindow sendEvent:]).
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}
@synthesize dataSource = _dataSource;
@synthesize delegate = _delegate;

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
    } else
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] is not implemented for coder %@",
                            [self class], sel_getName(_cmd), coder];

    return self;
}

- (NSArray *) content {
    return _content;
}

- (NSCollectionViewItem *) itemPrototype {
    return _itemPrototype;
}

- (BOOL) isSelectable {
    return _isSelectable;
}

- (NSSize) minItemSize {
    return _minItemSize;
}

- (NSSize) maxItemSize {
    return _maxItemSize;
}

- (NSUInteger) maxNumberOfRows {
    return _maxNumberOfRows;
}

- (NSUInteger) maxNumberOfColumns {
    return _maxNumberOfColumns;
}

// QUIRK: until colors are set, the background colors are the control background color alone; the documentation
// names the alternating row colors instead. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's tests/collection-view.md).
// Test: appkit-collection-view-layout.m test_default_background
- (NSArray *) backgroundColors {
    if (_backgroundColors == nil)
        return [NSArray arrayWithObject: [NSColor controlBackgroundColor]];
    return _backgroundColors;
}

- (BOOL) allowsMultipleSelection {
    return _allowsMultipleSelection;
}

// The legacy selection: the items of section 0 in selectionIndexPaths
- (NSIndexSet *) selectionIndexes {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSIndexPath *path in [self selectionIndexPaths])
        if (path.section == 0 && path.item >= 0)
            [indexes addIndex: path.item];
    return indexes;
}

+ (NSSet *) keyPathsForValuesAffectingSelectionIndexes {
    return [NSSet setWithObject: @"selectionIndexPaths"];
}

- (void) setContent: (NSArray *) value {
    value = [value retain];
    [_content release];
    _content = value;
}

- (void) setItemPrototype: (NSCollectionViewItem *) value {
    value = [value retain];
    [_itemPrototype release];
    _itemPrototype = value;
}

- (void) setSelectable: (BOOL) value {
    _isSelectable = value;
}

- (void) setMinItemSize: (NSSize) value {
    _minItemSize = value;
}

- (void) setMaxItemSize: (NSSize) value {
    _maxItemSize = value;
}

- (void) setMaxNumberOfRows: (NSUInteger) value {
    _maxNumberOfRows = value;
}

- (void) setMaxNumberOfColumns: (NSUInteger) value {
    _maxNumberOfColumns = value;
}

- (void) setBackgroundColors: (NSArray *) value {
    value = [value copy];
    [_backgroundColors release];
    _backgroundColors = value;
    [self setNeedsDisplay: YES];
}

- (void) setAllowsMultipleSelection: (BOOL) value {
    _allowsMultipleSelection = value;
}

- (void) setSelectionIndexes: (NSIndexSet *) value {
    NSMutableSet *paths = [NSMutableSet set];
    for (NSUInteger index = [value firstIndex]; index != NSNotFound; index = [value indexGreaterThanIndex: index])
        [paths addObject: [NSIndexPath indexPathForItem: index inSection: 0]];
    [self setSelectionIndexPaths: paths];
}

- (BOOL) allowsEmptySelection {
    return !_disallowsEmptySelection;
}

- (void) setAllowsEmptySelection: (BOOL) value {
    _disallowsEmptySelection = !value;
}

- (BOOL) isFirstResponder {
    return ([[self window] firstResponder] == self) ? YES : NO;
}

- (NSCollectionViewItem *) newItemForRepresentedObject: object {
    NSUnimplementedMethod();
    return nil;
}

- (void) dealloc {
    [_content release];
    [_itemPrototype release];
    [_backgroundColors release];
    [_selectionIndexes release];
    [_collectionViewLayout _setCollectionView: nil];
    [_collectionViewLayout release];
    [_selectionIndexPaths release];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    for (NSCollectionViewItem *item in [_loadedItems allValues])
        [item _setCollectionView: nil];
    for (NSArray *queue in [_reuseQueues allValues])
        for (NSCollectionViewItem *item in queue)
            [item _setCollectionView: nil];
    [_itemClasses release];
    [_loadedItems release];
    [_loadedPaths release];
    [_reuseQueues release];
    [_itemNibs release];
    [_itemIdentifiers release];
    [_backgroundView release];
    [_selectionAnchor release];
    [_selectionLead release];
    [_draggedIndexPaths release];
    [_dropIndexPath release];
    [_dropTargetItem release];
    [_dropGapIndicator release];
    [super dealloc];
}

- (NSCollectionViewLayout *) collectionViewLayout {
    return _collectionViewLayout;
}

// The layout learns which collection view it lays out; the one it replaces no longer has one
- (void) setCollectionViewLayout: (NSCollectionViewLayout *) layout {
    if (layout == _collectionViewLayout)
        return;
    [_collectionViewLayout _setCollectionView: nil];
    [layout retain];
    [_collectionViewLayout release];
    _collectionViewLayout = layout;
    [_collectionViewLayout _setCollectionView: self];
    [self _enqueueItems: [[_loadedItems copy] autorelease]];
    [_loadedItems removeAllObjects];
    _needsPrepareLayout = YES;
    [self setNeedsLayout: YES];
}

- (BOOL)isFlipped { return YES; }

- (NSInteger)numberOfSections {
    if (_dataSource == nil) return 0;
    NSInteger count = [_dataSource respondsToSelector:@selector(numberOfSectionsInCollectionView:)]
        ? [_dataSource numberOfSectionsInCollectionView:self] : 1;
    if (count < 0)
        [NSException raise:NSInvalidArgumentException format:@"negative collection section count"];
    return count;
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section {
    if (section < 0 || section >= [self numberOfSections])
        [NSException raise:NSInvalidArgumentException format:@"invalid collection section"];
    NSInteger count = [_dataSource collectionView:self numberOfItemsInSection:section];
    if (count < 0)
        [NSException raise:NSInvalidArgumentException format:@"negative collection item count"];
    return count;
}

- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)path {
    return [_loadedItems objectForKey:path];
}

// QUIRK: items no longer shown keep their views as hidden subviews, ready for reuse, and a reload hands the first
// of them to the first index paths. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's tests/collection-view.md).
// Test: appkit-collection-view-layout.m test_scroll_reuses_items, test_reload_after_count_change
// They are queued in index path order and handed out from the front.
- (void) _enqueueItems: (NSDictionary *) items {
    for (NSIndexPath *path in [[items allKeys] sortedArrayUsingSelector: @selector(compare:)]) {
        NSCollectionViewItem *item = [items objectForKey: path];
        NSString *identifier = [_itemIdentifiers objectForKey: [NSValue valueWithNonretainedObject: item]];
        if (identifier == nil) {
            // Not made by makeItemWithIdentifier:forIndexPath:, so nothing will ask for it again
            [[item view] removeFromSuperview];
            [item _setCollectionView: nil];
            continue;
        }
        [[item view] setHidden: YES];
        if (_reuseQueues == nil)
            _reuseQueues = [[NSMutableDictionary alloc] init];
        NSMutableArray *queue = [_reuseQueues objectForKey: identifier];
        if (queue == nil) {
            queue = [NSMutableArray array];
            [_reuseQueues setObject: queue forKey: identifier];
        }
        [queue addObject: item];
    }
}

- (void) _collectionViewLayout: (NSCollectionViewLayout *) layout
      didInvalidateWithContext: (NSCollectionViewLayoutInvalidationContext *) context
{
    if (layout != _collectionViewLayout)
        return;
    _needsPrepareLayout = YES;
    [self setNeedsLayout: YES];
}

- (void) _prepareLayoutIfNeeded {
    if (_needsPrepareLayout && _collectionViewLayout != nil) {
        _needsPrepareLayout = NO;
        [_collectionViewLayout prepareLayout];
    }
}

- (NSClipView *) _clipView {
    NSView *superview = [self superview];
    return [superview isKindOfClass: [NSClipView class]] ? (NSClipView *) superview : nil;
}

// A new size may invalidate the layout; the layout decides
- (void) _willChangeToSize: (NSSize) size {
    if (_collectionViewLayout == nil || NSEqualSizes(size, [self frame].size))
        return;
    NSRect bounds = [self bounds];
    bounds.size = size;
    if ([_collectionViewLayout shouldInvalidateLayoutForBoundsChange: bounds])
        [_collectionViewLayout
            invalidateLayoutWithContext: [_collectionViewLayout invalidationContextForBoundsChange: bounds]];
}

- (void) setFrame: (NSRect) frame {
    [self _willChangeToSize: frame.size];
    [super setFrame: frame];
}

- (void) setFrameSize: (NSSize) size {
    [self _willChangeToSize: size];
    [super setFrameSize: size];
}

// Sizes the view for its content, then shows an item for each element of the layout in the visible rect: the items
// already shown keep their views, the others come from the data source, and the rest go back for reuse.
- (void) _layoutItems {
    if (_collectionViewLayout == nil)
        return;
    for (int pass = 0; pass < 3; pass++) {
        [self _prepareLayoutIfNeeded];
        NSSize content = [_collectionViewLayout collectionViewContentSize];
        NSClipView *clip = [self _clipView];
        NSSize size = clip != nil ? sizeInClipView(_collectionViewLayout, content, [clip bounds].size) : content;
        if (NSEqualSizes(size, [self frame].size))
            break;
        [self setFrameSize: size];
    }
    [self _prepareLayoutIfNeeded];

    NSArray *elements = [_collectionViewLayout layoutAttributesForElementsInRect: [self visibleRect]];
    NSMutableDictionary *previous = [[_loadedItems mutableCopy] autorelease];
    // The items that leave go back for reuse first, so the data source gets them for the paths that come in
    NSMutableDictionary *leaving = [[previous mutableCopy] autorelease];
    for (NSCollectionViewLayoutAttributes *attributes in elements)
        if (attributes.representedElementCategory == NSCollectionElementCategoryItem && attributes.indexPath != nil)
            [leaving removeObjectForKey: attributes.indexPath];
    [previous removeObjectsForKeys: [leaving allKeys]];
    [self _enqueueItems: leaving];
    NSMutableDictionary *shown = [NSMutableDictionary dictionary];
    NSMutableDictionary *zIndexes = [NSMutableDictionary dictionary];
    BOOL ordered = NO;
    for (NSCollectionViewLayoutAttributes *attributes in elements) {
        if (attributes.representedElementCategory != NSCollectionElementCategoryItem)
            continue;
        NSIndexPath *path = attributes.indexPath;
        if (path == nil || [shown objectForKey: path] != nil)
            continue;
        NSCollectionViewItem *item = [previous objectForKey: path];
        if (item != nil)
            [previous removeObjectForKey: path];
        else {
            item = [_dataSource collectionView: self itemForRepresentedObjectAtIndexPath: path];
            if (![item isKindOfClass: [NSCollectionViewItem class]] || [item view] == nil)
                [NSException raise: NSInvalidArgumentException format: @"collection data source returned an invalid item"];
            [item _setCollectionView: self];
        }
        [shown setObject: item forKey: path];

        [item setSelected: [_selectionIndexPaths containsObject: path]];
        NSView *view = [item view];
        if ([view superview] != self)
            [self addSubview: view];
        [view setFrame: attributes.frame];
        [view setAlphaValue: attributes.alpha];
        [view setHidden: attributes.hidden];
        if ([item respondsToSelector: @selector(applyLayoutAttributes:)])
            [item applyLayoutAttributes: attributes];
        [zIndexes setObject: [NSNumber numberWithInteger: attributes.zIndex]
                     forKey: [NSValue valueWithNonretainedObject: view]];
        if (attributes.zIndex != 0)
            ordered = YES;
    }
    if (_loadedItems == nil)
        _loadedItems = [[NSMutableDictionary alloc] init];
    [_loadedItems setDictionary: shown];
    if (ordered)
        [self sortSubviewsUsingFunction: compareZIndex context: zIndexes];
    [self _placeBackgroundView];
}

- (void) layout {
    [super layout];
    [self _layoutItems];
}

// Scrolling shows other elements, and a new clip view size may change the view's own
- (void) _clipViewDidChange: (NSNotification *) notification {
    [self setNeedsLayout: YES];
}

- (void) viewWillMoveToSuperview: (NSView *) superview {
    NSClipView *clip = [self _clipView];
    if (clip != nil) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center removeObserver: self name: NSViewBoundsDidChangeNotification object: clip];
        [center removeObserver: self name: NSViewFrameDidChangeNotification object: clip];
    }
    [super viewWillMoveToSuperview: superview];
}

- (void) viewDidMoveToSuperview {
    [super viewDidMoveToSuperview];
    NSClipView *clip = [self _clipView];
    if (clip != nil) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [clip setPostsBoundsChangedNotifications: YES];
        [clip setPostsFrameChangedNotifications: YES];
        [center addObserver: self selector: @selector(_clipViewDidChange:) name: NSViewBoundsDidChangeNotification object: clip];
        [center addObserver: self selector: @selector(_clipViewDidChange:) name: NSViewFrameDidChangeNotification object: clip];
    }
    [self setNeedsLayout: YES];
}

// The items go back for reuse at once; the data source is asked again on the next layout pass
- (void)reloadData {
    if (_dataSource != nil && (![_dataSource respondsToSelector:@selector(collectionView:numberOfItemsInSection:)]
        || ![_dataSource respondsToSelector:@selector(collectionView:itemForRepresentedObjectAtIndexPath:)]))
        [NSException raise:NSInvalidArgumentException format:@"collection data source lacks required methods"];
    [self _enqueueItems: [[_loadedItems copy] autorelease]];
    [_loadedItems removeAllObjects];
    // QUIRK: any reload empties the selection. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's tests/collection-view.md).
    // Test: appkit-collection-view-selection.m test_reload_drops_selection
    [self _setSelection: [NSSet set]];
    [self _setAnchor: nil lead: nil];
    if (_collectionViewLayout != nil) {
        NSCollectionViewLayoutInvalidationContext *context =
            [[[[_collectionViewLayout class] invalidationContextClass] alloc] init];
        [context _setInvalidateEverything: YES];
        [context _setInvalidateDataSourceCounts: YES];
        [_collectionViewLayout invalidateLayoutWithContext: context];
        [context release];
    }
    _needsPrepareLayout = YES;
    [self setNeedsLayout: YES];
}

- (NSArray *) visibleItems {
    return [_loadedItems allValues];
}

- (NSSet *) indexPathsForVisibleItems {
    return [NSSet setWithArray: [_loadedItems allKeys]];
}

- (NSIndexPath *) indexPathForItem: (NSCollectionViewItem *) item {
    for (NSIndexPath *path in _loadedItems)
        if ([_loadedItems objectForKey: path] == item)
            return path;
    return nil;
}

- (NSIndexPath *) indexPathForItemAtPoint: (NSPoint) point {
    [self _prepareLayoutIfNeeded];
    NSArray *elements = [_collectionViewLayout layoutAttributesForElementsInRect: NSMakeRect(point.x, point.y, 1, 1)];
    for (NSCollectionViewLayoutAttributes *attributes in elements)
        if (attributes.representedElementCategory == NSCollectionElementCategoryItem &&
            NSPointInRect(point, attributes.frame))
            return attributes.indexPath;
    return nil;
}

- (NSCollectionViewLayoutAttributes *) layoutAttributesForItemAtIndexPath: (NSIndexPath *) indexPath {
    [self _prepareLayoutIfNeeded];
    return [_collectionViewLayout layoutAttributesForItemAtIndexPath: indexPath];
}

- (NSRect) frameForItemAtIndex: (NSUInteger) index {
    NSCollectionViewLayoutAttributes *attributes =
        [self layoutAttributesForItemAtIndexPath: [NSIndexPath indexPathForItem: index inSection: 0]];
    return attributes != nil ? attributes.frame : NSZeroRect;
}

// Scrolls the enclosing clip view so the items' frames are where the position asks; with no position, just visible
- (void) scrollToItemsAtIndexPaths: (NSSet *) indexPaths scrollPosition: (NSCollectionViewScrollPosition) position {
    NSRect target = NSZeroRect;
    for (NSIndexPath *path in indexPaths) {
        NSRect frame = [[self layoutAttributesForItemAtIndexPath: path] frame];
        target = NSIsEmptyRect(target) ? frame : NSUnionRect(target, frame);
    }
    if (NSIsEmptyRect(target))
        return;
    NSCollectionViewScrollPosition vertical = NSCollectionViewScrollPositionTop | NSCollectionViewScrollPositionBottom |
        NSCollectionViewScrollPositionCenteredVertically | NSCollectionViewScrollPositionNearestHorizontalEdge;
    NSCollectionViewScrollPosition horizontal = NSCollectionViewScrollPositionLeft | NSCollectionViewScrollPositionRight |
        NSCollectionViewScrollPositionCenteredHorizontally | NSCollectionViewScrollPositionLeadingEdge |
        NSCollectionViewScrollPositionTrailingEdge | NSCollectionViewScrollPositionNearestVerticalEdge;
    // NSCollectionViewScrollPositionNone names no edge to scroll to: nothing scrolls, even for an item out of view
    // (macOS 10.14.4 and 26.7.3; tests/appkit-collection-view-scroll-position-none.m)
    if ((position & (vertical | horizontal)) == 0)
        return;
    NSRect visible = [self visibleRect];
    NSPoint origin = visible.origin;
    if (position & NSCollectionViewScrollPositionTop)
        origin.y = NSMinY(target);
    else if (position & NSCollectionViewScrollPositionBottom)
        origin.y = NSMaxY(target) - NSHeight(visible);
    else if (position & NSCollectionViewScrollPositionCenteredVertically)
        origin.y = NSMidY(target) - NSHeight(visible) / 2;
    else if (position & NSCollectionViewScrollPositionNearestHorizontalEdge) {
        if (NSMinY(target) < NSMinY(visible))
            origin.y = NSMinY(target);
        else if (NSMaxY(target) > NSMaxY(visible))
            origin.y = NSMaxY(target) - NSHeight(visible);
    }
    if (position & (NSCollectionViewScrollPositionLeft | NSCollectionViewScrollPositionLeadingEdge))
        origin.x = NSMinX(target);
    else if (position & (NSCollectionViewScrollPositionRight | NSCollectionViewScrollPositionTrailingEdge))
        origin.x = NSMaxX(target) - NSWidth(visible);
    else if (position & NSCollectionViewScrollPositionCenteredHorizontally)
        origin.x = NSMidX(target) - NSWidth(visible) / 2;
    else if (position & NSCollectionViewScrollPositionNearestVerticalEdge) {
        if (NSMinX(target) < NSMinX(visible))
            origin.x = NSMinX(target);
        else if (NSMaxX(target) > NSMaxX(visible))
            origin.x = NSMaxX(target) - NSWidth(visible);
    }
    [self scrollPoint: origin];
}

- (NSView *) backgroundView {
    return _backgroundView;
}

- (void) setBackgroundView: (NSView *) view {
    if (view == _backgroundView)
        return;
    [_backgroundView removeFromSuperview];
    [view retain];
    [_backgroundView release];
    _backgroundView = view;
    [self _placeBackgroundView];
}

- (BOOL) backgroundViewScrollsWithContent {
    return _backgroundViewScrollsWithContent;
}

- (void) setBackgroundViewScrollsWithContent: (BOOL) flag {
    _backgroundViewScrollsWithContent = flag;
    [self _placeBackgroundView];
}

// Behind the items: over the whole content when it scrolls with it, otherwise over the visible part
- (void) _placeBackgroundView {
    if (_backgroundView == nil)
        return;
    if ([_backgroundView superview] != self)
        [self addSubview: _backgroundView positioned: NSWindowBelow relativeTo: nil];
    [_backgroundView setFrame: _backgroundViewScrollsWithContent ? [self bounds] : [self visibleRect]];
}

// The first background color fills the view when there is no background view
- (void) drawRect: (NSRect) dirtyRect {
    if (_backgroundView != nil)
        return;
    NSArray *colors = [self backgroundColors];
    if ([colors count] == 0)
        return;
    [[colors objectAtIndex: 0] setFill];
    NSRectFillUsingOperation(dirtyRect, NSCompositeSourceOver);
}

- (NSSet *) selectionIndexPaths {
    return _selectionIndexPaths ? [[_selectionIndexPaths retain] autorelease] : [NSSet set];
}

// Changes the selection and shows it on the visible items.
// QUIRK: the key-value notification for selectionIndexPaths comes from its setter only: selecting and deselecting
// by index path sends none. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's tests/collection-view.md).
// Test: appkit-collection-view-selection.m test_kvo_notifies_selection
- (void) _setSelection: (NSSet *) selection {
    selection = [selection copy];
    [_selectionIndexPaths release];
    _selectionIndexPaths = selection;
    for (NSIndexPath *path in _loadedItems)
        [[_loadedItems objectForKey: path] setSelected: [_selectionIndexPaths containsObject: path]];
}

- (void) setSelectionIndexPaths: (NSSet *) value {
    [self _setSelection: value != nil ? value : [NSSet set]];
}

// Documented not to consult the delegate; it works whether or not the view is selectable
- (void) selectItemsAtIndexPaths: (NSSet *) indexPaths scrollPosition: (NSCollectionViewScrollPosition) scrollPosition {
    [self _setSelection: [[self selectionIndexPaths] setByAddingObjectsFromSet: indexPaths]];
    if (scrollPosition != NSCollectionViewScrollPositionNone)
        [self scrollToItemsAtIndexPaths: indexPaths scrollPosition: scrollPosition];
}

- (void) deselectItemsAtIndexPaths: (NSSet *) indexPaths {
    NSMutableSet *selection = [[[self selectionIndexPaths] mutableCopy] autorelease];
    [selection minusSet: indexPaths];
    [self _setSelection: selection];
}

- (NSSet *) _allIndexPaths {
    NSMutableSet *paths = [NSMutableSet set];
    NSInteger sections = [self numberOfSections];
    for (NSInteger section = 0; section < sections; section++) {
        NSInteger count = [self numberOfItemsInSection: section];
        for (NSInteger item = 0; item < count; item++)
            [paths addObject: [NSIndexPath indexPathForItem: item inSection: section]];
    }
    return paths;
}

// A selection made by the user: the delegate may narrow it and is told what changed. Without `extend` the paths
// replace the selection; without multiple selection only one path is kept.
- (void) _userSelectIndexPaths: (NSSet *) paths byExtending: (BOOL) extend {
    if (!_isSelectable || [paths count] == 0)
        return;
    if (!_allowsMultipleSelection) {
        paths = [NSSet setWithObject: [paths anyObject]];
        extend = NO;
    }
    NSMutableSet *selecting = [[paths mutableCopy] autorelease];
    [selecting minusSet: [self selectionIndexPaths]];
    if ([selecting count] > 0 && [_delegate respondsToSelector: @selector(collectionView:shouldSelectItemsAtIndexPaths:)])
        selecting = [[[_delegate collectionView: self shouldSelectItemsAtIndexPaths: selecting] mutableCopy] autorelease];

    NSMutableSet *deselecting = [NSMutableSet set];
    if (!extend) {
        [deselecting unionSet: [self selectionIndexPaths]];
        [deselecting minusSet: paths];
        if ([deselecting count] > 0 &&
            [_delegate respondsToSelector: @selector(collectionView:shouldDeselectItemsAtIndexPaths:)])
            deselecting = [[[_delegate collectionView: self shouldDeselectItemsAtIndexPaths: deselecting] mutableCopy]
                autorelease];
    }
    if ([selecting count] == 0 && [deselecting count] == 0)
        return;

    NSMutableSet *selection = [[[self selectionIndexPaths] mutableCopy] autorelease];
    [selection minusSet: deselecting];
    [selection unionSet: selecting];
    if (!_allowsMultipleSelection && [selection count] > 1)
        return;
    if (!self.allowsEmptySelection && [selection count] == 0)
        return;
    [self setSelectionIndexPaths: selection];
    if ([deselecting count] > 0 && [_delegate respondsToSelector: @selector(collectionView:didDeselectItemsAtIndexPaths:)])
        [_delegate collectionView: self didDeselectItemsAtIndexPaths: deselecting];
    if ([selecting count] > 0 && [_delegate respondsToSelector: @selector(collectionView:didSelectItemsAtIndexPaths:)])
        [_delegate collectionView: self didSelectItemsAtIndexPaths: selecting];
}

- (void) _userDeselectIndexPaths: (NSSet *) paths {
    NSMutableSet *deselecting = [[paths mutableCopy] autorelease];
    [deselecting intersectSet: [self selectionIndexPaths]];
    if ([deselecting count] > 0 && [_delegate respondsToSelector: @selector(collectionView:shouldDeselectItemsAtIndexPaths:)])
        deselecting = [[[_delegate collectionView: self shouldDeselectItemsAtIndexPaths: deselecting] mutableCopy]
            autorelease];
    if ([deselecting count] == 0)
        return;
    NSMutableSet *selection = [[[self selectionIndexPaths] mutableCopy] autorelease];
    [selection minusSet: deselecting];
    if (!self.allowsEmptySelection && [selection count] == 0)
        return;
    [self setSelectionIndexPaths: selection];
    if ([_delegate respondsToSelector: @selector(collectionView:didDeselectItemsAtIndexPaths:)])
        [_delegate collectionView: self didDeselectItemsAtIndexPaths: deselecting];
}

- (void) _setAnchor: (NSIndexPath *) anchor lead: (NSIndexPath *) lead {
    [anchor retain];
    [_selectionAnchor release];
    _selectionAnchor = anchor;
    [lead retain];
    [_selectionLead release];
    _selectionLead = lead;
}

// The delegate's part in a selection the user makes. These return what the delegate allows.
- (NSSet *) _askSelect: (NSSet *) paths {
    if ([paths count] > 0 && [_delegate respondsToSelector: @selector(collectionView:shouldSelectItemsAtIndexPaths:)])
        return [_delegate collectionView: self shouldSelectItemsAtIndexPaths: paths];
    return paths;
}

- (void) _tellSelected: (NSSet *) paths {
    if ([paths count] > 0 && [_delegate respondsToSelector: @selector(collectionView:didSelectItemsAtIndexPaths:)])
        [_delegate collectionView: self didSelectItemsAtIndexPaths: paths];
}

- (NSSet *) _askDeselect: (NSSet *) paths {
    if ([paths count] > 0 && [_delegate respondsToSelector: @selector(collectionView:shouldDeselectItemsAtIndexPaths:)])
        return [_delegate collectionView: self shouldDeselectItemsAtIndexPaths: paths];
    return paths;
}

- (void) _tellDeselected: (NSSet *) paths {
    if ([paths count] > 0 && [_delegate respondsToSelector: @selector(collectionView:didDeselectItemsAtIndexPaths:)])
        [_delegate collectionView: self didDeselectItemsAtIndexPaths: paths];
}

// Asks, changes the selection and tells. Returns what was selected or deselected.
- (NSSet *) _userAdd: (NSSet *) paths {
    NSMutableSet *adding = [[paths mutableCopy] autorelease];
    [adding minusSet: [self selectionIndexPaths]];
    NSSet *allowed = [self _askSelect: adding];
    if ([allowed count] > 0) {
        [self setSelectionIndexPaths: [[self selectionIndexPaths] setByAddingObjectsFromSet: allowed]];
        [self _tellSelected: allowed];
    }
    return allowed;
}

- (NSSet *) _userRemove: (NSSet *) paths {
    NSSet *allowed = [self _askDeselect: paths];
    if ([allowed count] > 0) {
        NSMutableSet *selection = [[[self selectionIndexPaths] mutableCopy] autorelease];
        [selection minusSet: allowed];
        [self setSelectionIndexPaths: selection];
        [self _tellDeselected: allowed];
    }
    return allowed;
}

// The delegate may narrow the paths; the visible items among the rest take the state
- (NSSet *) _highlightIndexPaths: (NSSet *) paths state: (NSCollectionViewItemHighlightState) state {
    if ([paths count] == 0)
        return paths;
    if ([_delegate respondsToSelector: @selector(collectionView:shouldChangeItemsAtIndexPaths:toHighlightState:)])
        paths = [_delegate collectionView: self shouldChangeItemsAtIndexPaths: paths toHighlightState: state];
    for (NSIndexPath *path in paths)
        [[_loadedItems objectForKey: path] setHighlightState: state];
    if ([paths count] > 0 &&
        [_delegate respondsToSelector: @selector(collectionView:didChangeItemsAtIndexPaths:toHighlightState:)])
        [_delegate collectionView: self didChangeItemsAtIndexPaths: paths toHighlightState: state];
    return paths;
}

- (NSEvent *) _nextTrackingEvent {
    return [NSApp nextEventMatchingMask: NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged
                              untilDate: [NSDate distantFuture]
                                 inMode: NSEventTrackingRunLoopMode
                                dequeue: YES];
}

- (NSSet *) _itemIndexPathsInRect: (NSRect) rect {
    NSMutableSet *paths = [NSMutableSet set];
    for (NSCollectionViewLayoutAttributes *attributes in [_collectionViewLayout layoutAttributesForElementsInRect: rect])
        if (attributes.representedElementCategory == NSCollectionElementCategoryItem && attributes.indexPath != nil &&
            NSIntersectsRect(attributes.frame, rect))
            [paths addObject: attributes.indexPath];
    return paths;
}

- (BOOL) acceptsFirstResponder {
    return _isSelectable;
}

// A click on an item highlights it until the mouse goes up, then changes the selection in the order (and with the
// delegate calls) both Macs use (darling's tests/collection-view.md): ⌘ toggles the item, shift adds it, a plain click
// selects only it. When the delegate can provide the items' data, moving the mouse far enough drags the selection,
// after making the change the click would.
// QUIRK: a plain click on an item that is already selected changes nothing and calls no delegate method, even when
// other items are selected too. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's tests/collection-view.md).
// Test: appkit-collection-view-mouse.m test_click_selected_item_changes_nothing
- (void) _clickItemAtIndexPath: (NSIndexPath *) path
                        toggle: (BOOL) toggle
                        extend: (BOOL) extend
                         event: (NSEvent *) down
{
    BOOL wasSelected = [[self selectionIndexPaths] containsObject: path];
    BOOL changes = toggle || extend || !wasSelected;
    BOOL deselect = toggle && wasSelected;
    if (changes)
        [self _highlightIndexPaths: [NSSet setWithObject: path]
                             state: deselect ? NSCollectionViewItemHighlightForDeselection
                                             : NSCollectionViewItemHighlightForSelection];

    BOOL draggable = !deselect && [self _delegateProvidesDragData];
    NSPoint start = [down locationInWindow];
    for (;;) {
        NSEvent *event = [self _nextTrackingEvent];
        if ([event type] == NSEventTypeLeftMouseUp)
            break;
        NSPoint point = [event locationInWindow];
        if (!draggable || MAX(fabs(point.x - start.x), fabs(point.y - start.y)) < dragThreshold)
            continue;
        if (changes) {
            [self _changeSelectionForClickAtIndexPath: path toggle: toggle extend: extend wasSelected: wasSelected];
            changes = NO;
        }
        if ([self _dragSelectionWithEvent: down])
            return;
    }
    if (changes)
        [self _changeSelectionForClickAtIndexPath: path toggle: toggle extend: extend wasSelected: wasSelected];
}

- (void) _changeSelectionForClickAtIndexPath: (NSIndexPath *) path
                                      toggle: (BOOL) toggle
                                      extend: (BOOL) extend
                                 wasSelected: (BOOL) wasSelected
{
    NSSet *clicked = [NSSet setWithObject: path];
    BOOL unhighlighted = NO;
    if (toggle && wasSelected) {
        if (self.allowsEmptySelection || [[self selectionIndexPaths] count] > 1)
            [self _userRemove: clicked];
    } else if (_allowsMultipleSelection && (toggle || extend))
        [self _userAdd: clicked];
    else if (_allowsMultipleSelection) {
        NSMutableSet *others = [[[self selectionIndexPaths] mutableCopy] autorelease];
        [others removeObject: path];
        if ([others count] > 0) {
            [self _highlightIndexPaths: others state: NSCollectionViewItemHighlightForDeselection];
            [self _userRemove: others];
            [self _highlightIndexPaths: others state: NSCollectionViewItemHighlightNone];
        }
        [self _userAdd: clicked];
    } else if (!wasSelected) {
        // One item at most: the new one is selected first, then the old one deselected
        NSMutableSet *others = [[[self selectionIndexPaths] mutableCopy] autorelease];
        [others removeObject: path];
        NSSet *allowed = [self _askSelect: clicked];
        if ([allowed count] > 0) {
            [self setSelectionIndexPaths: clicked];
            [self _tellSelected: clicked];
            [self _highlightIndexPaths: clicked state: NSCollectionViewItemHighlightNone];
            unhighlighted = YES;
            if ([others count] > 0) {
                [self _tellDeselected: [self _askDeselect: others]];
                [self _highlightIndexPaths: others state: NSCollectionViewItemHighlightNone];
            }
        }
    }
    if (!unhighlighted)
        [self _highlightIndexPaths: clicked state: NSCollectionViewItemHighlightNone];
    if ([[self selectionIndexPaths] containsObject: path])
        [self _setAnchor: path lead: path];
}

// A drag from the background selects the items a rectangle covers. Without modifiers the selection is emptied first,
// as a click on the background does. With ⌘, a band that first reaches a selected item deselects what it covers.
- (void) _rubberBandFrom: (NSPoint) start toggle: (BOOL) toggle extend: (BOOL) extend {
    if (!toggle && !extend && self.allowsEmptySelection) {
        NSSet *selected = [self selectionIndexPaths];
        if ([selected count] > 0) {
            [self _userRemove: selected];
            [self _highlightIndexPaths: selected state: NSCollectionViewItemHighlightNone];
        }
    }
    if (!_allowsMultipleSelection) {
        while ([[self _nextTrackingEvent] type] != NSEventTypeLeftMouseUp)
            ;
        return;
    }

    _NSCollectionViewRubberBand *band = [[[_NSCollectionViewRubberBand alloc] initWithFrame: NSZeroRect] autorelease];
    [self addSubview: band positioned: NSWindowAbove relativeTo: nil];
    NSMutableSet *covered = [NSMutableSet set];
    NSCollectionViewItemHighlightState state = NSCollectionViewItemHighlightNone;
    for (;;) {
        NSEvent *event = [self _nextTrackingEvent];
        NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
        NSRect rect = NSMakeRect(MIN(start.x, point.x), MIN(start.y, point.y), fabs(point.x - start.x),
                                 fabs(point.y - start.y));
        if ([event type] == NSEventTypeLeftMouseDragged)
            [self autoscroll: event];
        [band setFrame: rect];
        [self setNeedsDisplayInRect: NSInsetRect(NSUnionRect(rect, [band frame]), -2, -2)];

        NSSet *inside = [self _itemIndexPathsInRect: rect];
        if (state == NSCollectionViewItemHighlightNone && [inside count] > 0)
            state = toggle && [inside intersectsSet: [self selectionIndexPaths]]
                        ? NSCollectionViewItemHighlightForDeselection
                        : NSCollectionViewItemHighlightForSelection;
        NSMutableSet *added = [[inside mutableCopy] autorelease];
        [added minusSet: covered];
        NSMutableSet *removed = [[covered mutableCopy] autorelease];
        [removed minusSet: inside];
        if ([removed count] > 0) {
            [self _highlightIndexPaths: removed state: NSCollectionViewItemHighlightNone];
            [covered minusSet: removed];
        }
        if ([added count] > 0) {
            [self _highlightIndexPaths: added state: state];
            [covered unionSet: added];
        }
        if ([event type] == NSEventTypeLeftMouseUp)
            break;
    }
    [band removeFromSuperview];

    if ([covered count] == 0)
        return;
    if (state == NSCollectionViewItemHighlightForDeselection)
        [self _userRemove: covered];
    else {
        NSSet *allowed = [self _askSelect: covered];
        if ([allowed count] > 0) {
            [self setSelectionIndexPaths: [[self selectionIndexPaths] setByAddingObjectsFromSet: allowed]];
            [self _tellSelected: allowed];
        }
    }
    [self _highlightIndexPaths: covered state: NSCollectionViewItemHighlightNone];
}

- (void) mouseDown: (NSEvent *) event {
    if (!_isSelectable) {
        [super mouseDown: event];
        return;
    }
    if ([[self window] firstResponder] != self)
        [[self window] makeFirstResponder: self];
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    NSEventModifierFlags flags = [event modifierFlags];
    BOOL toggle = (flags & NSEventModifierFlagCommand) != 0, extend = (flags & NSEventModifierFlagShift) != 0;
    NSIndexPath *path = [self indexPathForItemAtPoint: point];
    if (path != nil) {
        // The first click selected the item; a double click is the item's (or its view's) to handle
        if ([event clickCount] > 1)
            return;
        [self _clickItemAtIndexPath: path toggle: toggle extend: extend event: event];
    } else
        [self _rubberBandFrom: point toggle: toggle extend: extend];
}

- (void) keyDown: (NSEvent *) event {
    if (_isSelectable)
        [self interpretKeyEvents: [NSArray arrayWithObject: event]];
    else
        [super keyDown: event];
}

typedef enum { MoveLeft, MoveRight, MoveUp, MoveDown } MoveDirection;

// The item next to the given one on screen: within its row for left and right, in the nearest row above or below
// (the item whose middle is closest) for up and down
- (NSIndexPath *) _indexPathFrom: (NSIndexPath *) from direction: (MoveDirection) direction {
    NSRect current = [[self layoutAttributesForItemAtIndexPath: from] frame];
    if (NSIsEmptyRect(current))
        return nil;
    NSRect bounds = [self bounds];
    NSRect search;
    switch (direction) {
    case MoveLeft:
        search = NSMakeRect(NSMinX(bounds), NSMinY(current), NSMinX(current) - NSMinX(bounds), NSHeight(current));
        break;
    case MoveRight:
        search = NSMakeRect(NSMaxX(current), NSMinY(current), NSMaxX(bounds) - NSMaxX(current), NSHeight(current));
        break;
    case MoveUp:
        search = NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), NSMinY(current) - NSMinY(bounds));
        break;
    default:
        search = NSMakeRect(NSMinX(bounds), NSMaxY(current), NSWidth(bounds), NSMaxY(bounds) - NSMaxY(current));
        break;
    }
    NSArray *elements = [_collectionViewLayout layoutAttributesForElementsInRect: search];
    NSCollectionViewLayoutAttributes *best = nil;
    for (NSCollectionViewLayoutAttributes *a in elements) {
        if (a.representedElementCategory != NSCollectionElementCategoryItem || [a.indexPath isEqual: from])
            continue;
        NSRect frame = a.frame;
        switch (direction) {
        case MoveLeft:
            if (NSMaxX(frame) <= NSMinX(current) && NSMaxY(frame) > NSMinY(current) && NSMinY(frame) < NSMaxY(current) &&
                (best == nil || NSMaxX(frame) > NSMaxX(best.frame)))
                best = a;
            break;
        case MoveRight:
            if (NSMinX(frame) >= NSMaxX(current) && NSMaxY(frame) > NSMinY(current) && NSMinY(frame) < NSMaxY(current) &&
                (best == nil || NSMinX(frame) < NSMinX(best.frame)))
                best = a;
            break;
        case MoveUp:
            if (NSMaxY(frame) <= NSMinY(current) &&
                (best == nil || NSMaxY(frame) > NSMaxY(best.frame) ||
                 (NSMaxY(frame) == NSMaxY(best.frame) &&
                  fabs(NSMidX(frame) - NSMidX(current)) < fabs(NSMidX(best.frame) - NSMidX(current)))))
                best = a;
            break;
        default:
            if (NSMinY(frame) >= NSMaxY(current) &&
                (best == nil || NSMinY(frame) < NSMinY(best.frame) ||
                 (NSMinY(frame) == NSMinY(best.frame) &&
                  fabs(NSMidX(frame) - NSMidX(current)) < fabs(NSMidX(best.frame) - NSMidX(current)))))
                best = a;
            break;
        }
    }
    return best.indexPath;
}

// Every index path from one to the other, both included, in index order
- (NSSet *) _indexPathsFrom: (NSIndexPath *) first to: (NSIndexPath *) last {
    if ([first compare: last] == NSOrderedDescending) {
        NSIndexPath *swap = first;
        first = last;
        last = swap;
    }
    NSMutableSet *paths = [NSMutableSet set];
    for (NSInteger section = first.section; section <= last.section; section++) {
        NSInteger count = [self numberOfItemsInSection: section];
        NSInteger start = section == first.section ? first.item : 0;
        NSInteger end = section == last.section ? last.item : count - 1;
        for (NSInteger item = start; item <= end && item < count; item++)
            [paths addObject: [NSIndexPath indexPathForItem: item inSection: section]];
    }
    return paths;
}

// An arrow key: the selection moves to the next item, deselecting first; with shift it becomes the range from where
// it started to the new item (both Macs, darling's tests/collection-view.md)
- (void) _moveSelection: (MoveDirection) direction extend: (BOOL) extend {
    NSSet *selection = [self selectionIndexPaths];
    if (!_isSelectable || [selection count] == 0)
        return;
    NSIndexPath *lead = _selectionLead;
    if (lead == nil || ![selection containsObject: lead])
        lead = [[[selection allObjects] sortedArrayUsingSelector: @selector(compare:)] lastObject];
    NSIndexPath *target = [self _indexPathFrom: lead direction: direction];
    if (target == nil)
        return;

    if (extend && _allowsMultipleSelection) {
        NSIndexPath *anchor = _selectionAnchor;
        if (anchor == nil || ![selection containsObject: anchor])
            anchor = lead;
        NSSet *range = [self _indexPathsFrom: anchor to: target];
        NSMutableSet *leaving = [[[self _indexPathsFrom: anchor to: lead] mutableCopy] autorelease];
        [leaving minusSet: range];
        [leaving intersectSet: selection];
        [self _userRemove: leaving];
        [self _userAdd: range];
        [self _setAnchor: anchor lead: target];
    } else {
        NSMutableSet *others = [[selection mutableCopy] autorelease];
        [others removeObject: target];
        [self _userRemove: others];
        [self _userAdd: [NSSet setWithObject: target]];
        [self _setAnchor: target lead: target];
    }
    [self scrollToItemsAtIndexPaths: [NSSet setWithObject: target]
                     scrollPosition: NSCollectionViewScrollPositionNearestHorizontalEdge];
}

- (void) moveLeft: (id) sender {
    [self _moveSelection: MoveLeft extend: NO];
}
- (void) moveRight: (id) sender {
    [self _moveSelection: MoveRight extend: NO];
}
- (void) moveUp: (id) sender {
    [self _moveSelection: MoveUp extend: NO];
}
- (void) moveDown: (id) sender {
    [self _moveSelection: MoveDown extend: NO];
}
- (void) moveLeftAndModifySelection: (id) sender {
    [self _moveSelection: MoveLeft extend: YES];
}
- (void) moveRightAndModifySelection: (id) sender {
    [self _moveSelection: MoveRight extend: YES];
}
- (void) moveUpAndModifySelection: (id) sender {
    [self _moveSelection: MoveUp extend: YES];
}
- (void) moveDownAndModifySelection: (id) sender {
    [self _moveSelection: MoveDown extend: YES];
}

// Only when the view is selectable and allows multiple selection (the documented contract; both Macs agree)
- (IBAction) selectAll: (id) sender {
    if (!_allowsMultipleSelection)
        return;
    [self _userSelectIndexPaths: [self _allIndexPaths] byExtending: YES];
}

- (IBAction) deselectAll: (id) sender {
    [self _userDeselectIndexPaths: [self selectionIndexPaths]];
}

#pragma mark - Dragging source

- (BOOL) _delegateProvidesDragData {
    return [_delegate respondsToSelector: @selector(collectionView:pasteboardWriterForItemAtIndexPath:)] ||
           [_delegate respondsToSelector: @selector(collectionView:writeItemsAtIndexPaths:toPasteboard:)];
}

static NSInteger compareIndexPaths(id first, id second, void *context)
{
    return [(NSIndexPath *) first compare: (NSIndexPath *) second];
}

// Where an item is dragged from: its view where it shows, or where the layout puts it
- (NSRect) _draggingFrameForItemAtIndexPath: (NSIndexPath *) path {
    NSCollectionViewItem *item = [_loadedItems objectForKey: path];
    if ([item view] != nil && [[item view] superview] == self)
        return [[item view] frame];
    return [self layoutAttributesForItemAtIndexPath: path].frame;
}

// A picture of an item's view, or nil when it isn't shown
- (NSImage *) _draggingImageForItemAtIndexPath: (NSIndexPath *) path {
    NSView *view = [[_loadedItems objectForKey: path] view];
    NSRect bounds = [view bounds];
    if (view == nil || NSIsEmptyRect(bounds))
        return nil;
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: bounds];
    if (rep == nil)
        return nil;
    [view cacheDisplayInRect: bounds toBitmapImageRep: rep];
    NSImage *image = [[[NSImage alloc] initWithSize: bounds.size] autorelease];
    [image addRepresentation: rep];
    return image;
}

// Starts dragging the selected items if the delegate lets them be dragged and provides their data: one dragging
// item per item with a pasteboard writer, in index path order, framed where the item is. Returns whether it did.
- (BOOL) _dragSelectionWithEvent: (NSEvent *) down {
    NSSet *selection = [self selectionIndexPaths];
    if ([selection count] == 0)
        return NO;
    if ([_delegate respondsToSelector: @selector(collectionView:canDragItemsAtIndexPaths:withEvent:)] &&
        ![_delegate collectionView: self canDragItemsAtIndexPaths: selection withEvent: down])
        return NO;
    NSArray *paths = [[selection allObjects] sortedArrayUsingFunction: compareIndexPaths context: NULL];

    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *dragged = [NSMutableSet set];
    BOOL writers = [_delegate respondsToSelector: @selector(collectionView:pasteboardWriterForItemAtIndexPath:)];
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName: NSPasteboardNameDrag];
    if (!writers && ![_delegate collectionView: self writeItemsAtIndexPaths: selection toPasteboard: pasteboard])
        return NO;
    for (NSIndexPath *path in paths) {
        id<NSPasteboardWriting> writer = nil;
        if (writers && (writer = [_delegate collectionView: self pasteboardWriterForItemAtIndexPath: path]) == nil)
            continue;
        NSRect frame = [self _draggingFrameForItemAtIndexPath: path];
        if (NSIsEmptyRect(frame))
            continue;
        NSDraggingItem *item = [[[NSDraggingItem alloc] initWithPasteboardWriter: writer] autorelease];
        [item setDraggingFrame: frame contents: [self _draggingImageForItemAtIndexPath: path]];
        [items addObject: item];
        [dragged addObject: path];
    }
    if ([items count] == 0)
        return NO;

    [_draggedIndexPaths release];
    _draggedIndexPaths = [dragged copy];
    if (writers)
        [self beginDraggingSessionWithItems: items event: down source: self];
    else {
        // The delegate wrote the data itself: the items only show what is dragged
        NSDraggingSession *session = [[[NSDraggingSession alloc] _initWithItems: items
                                                                           view: self
                                                                          event: down
                                                                         source: self
                                                                     pasteboard: pasteboard] autorelease];
        [session _scheduleStart];
    }
    return YES;
}

- (void) setDraggingSourceOperationMask: (NSDragOperation) mask forLocal: (BOOL) localDestination {
    if (localDestination)
        _localDragMaskInverted = ~mask;
    else
        _outsideDragMask = mask;
}

// Every operation within the application and none outside it until set (the documented default; both Macs agree)
- (NSDragOperation) draggingSession: (NSDraggingSession *) session
    sourceOperationMaskForDraggingContext: (NSDraggingContext) context
{
    return context == NSDraggingContextWithinApplication ? ~_localDragMaskInverted : _outsideDragMask;
}

- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) local {
    return local ? ~_localDragMaskInverted : _outsideDragMask;
}

- (void) draggingSession: (NSDraggingSession *) session willBeginAtPoint: (NSPoint) screenPoint {
    if ([_delegate respondsToSelector: @selector(collectionView:draggingSession:willBeginAtPoint:forItemsAtIndexPaths:)])
        [_delegate collectionView: self
                  draggingSession: session
                 willBeginAtPoint: screenPoint
             forItemsAtIndexPaths: _draggedIndexPaths];
}

- (void) draggingSession: (NSDraggingSession *) session
            endedAtPoint: (NSPoint) screenPoint
               operation: (NSDragOperation) operation
{
    if ([_delegate respondsToSelector: @selector(collectionView:draggingSession:endedAtPoint:dragOperation:)])
        [_delegate collectionView: self draggingSession: session endedAtPoint: screenPoint dragOperation: operation];
    [_draggedIndexPaths release];
    _draggedIndexPaths = nil;
}

#pragma mark - Drop target

// Shows where a drop would go: the item it would go on as the drop target, or a bar in the gap it would go to
- (void) _showDropAtIndexPath: (NSIndexPath *) path operation: (NSCollectionViewDropOperation) operation {
    NSCollectionViewItem *target =
        path != nil && operation == NSCollectionViewDropOn ? [_loadedItems objectForKey: path] : nil;
    if (target != _dropTargetItem) {
        if (_dropTargetItem.highlightState == NSCollectionViewItemHighlightAsDropTarget)
            _dropTargetItem.highlightState = NSCollectionViewItemHighlightNone;
        [_dropTargetItem release];
        _dropTargetItem = [target retain];
        _dropTargetItem.highlightState = NSCollectionViewItemHighlightAsDropTarget;
    }

    NSCollectionViewLayoutAttributes *gap = nil;
    if (path != nil && operation == NSCollectionViewDropBefore)
        gap = [_collectionViewLayout layoutAttributesForInterItemGapBeforeIndexPath: path];
    if (gap == nil || NSIsEmptyRect(gap.frame)) {
        [_dropGapIndicator removeFromSuperview];
        [_dropGapIndicator release];
        _dropGapIndicator = nil;
        return;
    }
    if (_dropGapIndicator == nil)
        _dropGapIndicator = [[_NSCollectionViewDropGapIndicator alloc] initWithFrame: gap.frame];
    else
        [_dropGapIndicator setFrame: gap.frame];
    if ([_dropGapIndicator superview] != self)
        [self addSubview: _dropGapIndicator positioned: NSWindowAbove relativeTo: nil];
    [_dropGapIndicator setNeedsDisplay: YES];
}

- (void) _setDropIndexPath: (NSIndexPath *) path
                 operation: (NSCollectionViewDropOperation) operation
             dragOperation: (NSDragOperation) dragOperation
{
    [path retain];
    [_dropIndexPath release];
    _dropIndexPath = path;
    _dropOperation = operation;
    _dropDragOperation = dragOperation;
    [self _showDropAtIndexPath: dragOperation != NSDragOperationNone ? path : nil operation: operation];
}

// Proposes the drop the layout finds at the drag's location (on an item, or before the item after a gap) and lets
// the delegate validate or change it
- (NSDragOperation) _validateDrop: (id<NSDraggingInfo>) info {
    NSIndexPath *path = nil;
    NSCollectionViewDropOperation operation = NSCollectionViewDropOn;
    NSDragOperation result = NSDragOperationNone;
    if ([_delegate respondsToSelector: @selector(collectionView:validateDrop:proposedIndexPath:dropOperation:)]) {
        [self _prepareLayoutIfNeeded];
        NSPoint point = [self convertPoint: [info draggingLocation] fromView: nil];
        NSCollectionViewLayoutAttributes *target = [_collectionViewLayout layoutAttributesForDropTargetAtPoint: point];
        if (target.indexPath != nil) {
            path = target.indexPath;
            operation = target.representedElementCategory == NSCollectionElementCategoryItem ? NSCollectionViewDropOn
                                                                                              : NSCollectionViewDropBefore;
            result = [_delegate collectionView: self
                                  validateDrop: info
                             proposedIndexPath: &path
                                 dropOperation: &operation];
        }
    }
    [self _setDropIndexPath: path operation: operation dragOperation: result];
    return result;
}

- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) info {
    return [self _validateDrop: info];
}

- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) info {
    return [self _validateDrop: info];
}

- (void) draggingExited: (id<NSDraggingInfo>) info {
    [self _setDropIndexPath: nil operation: NSCollectionViewDropOn dragOperation: NSDragOperationNone];
}

- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) info {
    return YES;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>) info {
    if (_dropDragOperation == NSDragOperationNone || _dropIndexPath == nil ||
        ![_delegate respondsToSelector: @selector(collectionView:acceptDrop:indexPath:dropOperation:)])
        return NO;
    return [_delegate collectionView: self
                          acceptDrop: info
                           indexPath: _dropIndexPath
                       dropOperation: (NSCollectionViewDropOperation) _dropOperation];
}

// QUIRK: the drop target stays shown through performDragOperation: and concludeDragOperation: and goes at
// draggingEnded:. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's tests/collection-view.md).
// Test: appkit-collection-view-drag.m test_drop_target_highlight
- (void) concludeDragOperation: (id<NSDraggingInfo>) info {
}

- (void) draggingEnded: (id<NSDraggingInfo>) info {
    [self _setDropIndexPath: nil operation: NSCollectionViewDropOn dragOperation: NSDragOperationNone];
}

- (void) registerClass: (Class) itemClass forItemWithIdentifier: (NSString *) identifier {
    if (_itemClasses == nil)
        _itemClasses = [[NSMutableDictionary alloc] init];
    if (itemClass != Nil) {
        [_itemClasses setObject: itemClass forKey: identifier];
        [_itemNibs removeObjectForKey: identifier];
    } else
        [_itemClasses removeObjectForKey: identifier];
}

- (void) registerNib: (NSNib *) nib forItemWithIdentifier: (NSString *) identifier {
    if (_itemNibs == nil)
        _itemNibs = [[NSMutableDictionary alloc] init];
    if (nib != nil) {
        [_itemNibs setObject: nib forKey: identifier];
        [_itemClasses removeObjectForKey: identifier];
    } else
        [_itemNibs removeObjectForKey: identifier];
}

// A hidden item made for the same identifier is reused (after -prepareForReuse); otherwise a new one comes from the
// class or nib registered for the identifier
- (NSCollectionViewItem *) makeItemWithIdentifier: (NSString *) identifier
                                     forIndexPath: (NSIndexPath *) indexPath
{
    NSMutableArray *queue = [_reuseQueues objectForKey: identifier];
    if ([queue count] > 0) {
        NSCollectionViewItem *item = [[[queue objectAtIndex: 0] retain] autorelease];
        [queue removeObjectAtIndex: 0];
        [item prepareForReuse];
        return item;
    }

    NSCollectionViewItem *item = nil;
    Class itemClass = [_itemClasses objectForKey: identifier];
    NSNib *nib = [_itemNibs objectForKey: identifier];
    if (itemClass != Nil)
        item = [[[itemClass alloc] init] autorelease];
    else if (nib != nil) {
        NSArray *objects = nil;
        if ([nib instantiateWithOwner: nil topLevelObjects: &objects])
            for (id object in objects)
                if ([object isKindOfClass: [NSCollectionViewItem class]]) {
                    item = object;
                    break;
                }
        if (item == nil)
            [NSException raise: NSInternalInconsistencyException
                        format: @"-[%@ %s]: the nib registered for identifier %@ has no collection view item",
                                [self class], sel_getName(_cmd), identifier];
    } else
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[%@ %s]: no item class or nib registered for identifier %@",
                            [self class], sel_getName(_cmd), identifier];

    if (_itemIdentifiers == nil)
        _itemIdentifiers = [[NSMutableDictionary alloc] init];
    [_itemIdentifiers setObject: identifier forKey: [NSValue valueWithNonretainedObject: item]];
    return item;
}

@end
