/*
 This file is part of Darling.

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// The NSCollectionLayout* classes of the compositional layout. On macOS they live in the private CollectionViewCore
// framework and AppKit re-exports them; this image is the stand-in for plain Darling and is left out of a dyld-cache
// stage, where the cache's CollectionViewCore provides them (see CollectionViewCore/CMakeLists.txt).
//
// This file imports nothing from AppKit but its public header: AppKit links and re-exports this framework.
// Instance variables are private to each @implementation, so no other image depends on them.

#import <AppKit/NSCollectionViewCompositionalLayout.h>

// The value classes below are immutable: a copy is the object itself.
enum {
    DimensionKindFractionalWidth,
    DimensionKindFractionalHeight,
    DimensionKindAbsolute,
    DimensionKindEstimated,
};

@implementation NSCollectionLayoutDimension {
    NSInteger _kind;
    CGFloat _dimension;
}

- (instancetype) _initWithKind: (NSInteger) kind
                     dimension: (CGFloat) dimension {
    self = [super init];
    if (self) {
        _kind = kind;
        _dimension = dimension;
    }
    return self;
}

+ (instancetype) fractionalWidthDimension: (CGFloat) fractionalWidth {
    return [[[self alloc]
            _initWithKind: DimensionKindFractionalWidth
                dimension: fractionalWidth] autorelease];
}

+ (instancetype) fractionalHeightDimension: (CGFloat) fractionalHeight {
    return [[[self alloc]
            _initWithKind: DimensionKindFractionalHeight
                dimension: fractionalHeight] autorelease];
}

+ (instancetype) absoluteDimension: (CGFloat) absoluteDimension {
    return [[[self alloc] _initWithKind: DimensionKindAbsolute
                              dimension: absoluteDimension] autorelease];
}

+ (instancetype) estimatedDimension: (CGFloat) estimatedDimension {
    return [[[self alloc] _initWithKind: DimensionKindEstimated
                              dimension: estimatedDimension] autorelease];
}

- (BOOL) isFractionalWidth {
    return _kind == DimensionKindFractionalWidth;
}

- (BOOL) isFractionalHeight {
    return _kind == DimensionKindFractionalHeight;
}

- (BOOL) isAbsolute {
    return _kind == DimensionKindAbsolute;
}

- (BOOL) isEstimated {
    return _kind == DimensionKindEstimated;
}

- (CGFloat) dimension {
    return _dimension;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutSize {
    NSCollectionLayoutDimension *_widthDimension;
    NSCollectionLayoutDimension *_heightDimension;
}

+ (instancetype) sizeWithWidthDimension: (NSCollectionLayoutDimension *) width
                        heightDimension: (NSCollectionLayoutDimension *) height {
    NSCollectionLayoutSize *size = [[[self alloc] init] autorelease];

    size->_widthDimension = [width retain];
    size->_heightDimension = [height retain];
    return size;
}

- (void) dealloc {
    [_widthDimension release];
    [_heightDimension release];
    [super dealloc];
}

- (NSCollectionLayoutDimension *) widthDimension {
    return _widthDimension;
}

- (NSCollectionLayoutDimension *) heightDimension {
    return _heightDimension;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutSpacing {
    CGFloat _spacing;
    BOOL _flexible;
}

+ (instancetype) flexibleSpacing: (CGFloat) flexibleSpacing {
    NSCollectionLayoutSpacing *spacing = [[[self alloc] init] autorelease];

    spacing->_spacing = flexibleSpacing;
    spacing->_flexible = YES;
    return spacing;
}

+ (instancetype) fixedSpacing: (CGFloat) fixedSpacing {
    NSCollectionLayoutSpacing *spacing = [[[self alloc] init] autorelease];

    spacing->_spacing = fixedSpacing;
    return spacing;
}

- (CGFloat) spacing {
    return _spacing;
}

- (BOOL) isFlexibleSpacing {
    return _flexible;
}

- (BOOL) isFixedSpacing {
    return !_flexible;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutEdgeSpacing {
    NSCollectionLayoutSpacing *_leading;
    NSCollectionLayoutSpacing *_top;
    NSCollectionLayoutSpacing *_trailing;
    NSCollectionLayoutSpacing *_bottom;
}

+ (instancetype) spacingForLeading: (NSCollectionLayoutSpacing *) leading
                               top: (NSCollectionLayoutSpacing *) top
                          trailing: (NSCollectionLayoutSpacing *) trailing
                            bottom: (NSCollectionLayoutSpacing *) bottom {
    NSCollectionLayoutEdgeSpacing *spacing = [[[self alloc] init] autorelease];

    spacing->_leading = [leading retain];
    spacing->_top = [top retain];
    spacing->_trailing = [trailing retain];
    spacing->_bottom = [bottom retain];
    return spacing;
}

- (void) dealloc {
    [_leading release];
    [_top release];
    [_trailing release];
    [_bottom release];
    [super dealloc];
}

- (NSCollectionLayoutSpacing *) leading {
    return _leading;
}

- (NSCollectionLayoutSpacing *) top {
    return _top;
}

- (NSCollectionLayoutSpacing *) trailing {
    return _trailing;
}

- (NSCollectionLayoutSpacing *) bottom {
    return _bottom;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutAnchor {
    NSDirectionalRectEdge _edges;
    NSPoint _offset;
    BOOL _fractional;
}

- (instancetype) _initWithEdges: (NSDirectionalRectEdge) edges
                         offset: (NSPoint) offset
                     fractional: (BOOL) fractional {
    self = [super init];
    if (self) {
        _edges = edges;
        _offset = offset;
        _fractional = fractional;
    }
    return self;
}

// GUESS: with no offset the anchor sits on its edges (offset zero) and the zero offset is an absolute one; the
// header does not say which kind it reports.
+ (instancetype) layoutAnchorWithEdges: (NSDirectionalRectEdge) edges {
    return [[[self alloc] _initWithEdges: edges
                                  offset: NSZeroPoint
                              fractional: NO] autorelease];
}

+ (instancetype) layoutAnchorWithEdges: (NSDirectionalRectEdge) edges
                        absoluteOffset: (NSPoint) absoluteOffset {
    return [[[self alloc] _initWithEdges: edges
                                  offset: absoluteOffset
                              fractional: NO] autorelease];
}

+ (instancetype) layoutAnchorWithEdges: (NSDirectionalRectEdge) edges
                      fractionalOffset: (NSPoint) fractionalOffset {
    return [[[self alloc] _initWithEdges: edges
                                  offset: fractionalOffset
                              fractional: YES] autorelease];
}

- (NSDirectionalRectEdge) edges {
    return _edges;
}

- (NSPoint) offset {
    return _offset;
}

- (BOOL) isAbsoluteOffset {
    return !_fractional;
}

- (BOOL) isFractionalOffset {
    return _fractional;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@interface NSCollectionLayoutItem ()
- (void) _setSupplementaryItems: (NSArray *) supplementaryItems;
@end

@implementation NSCollectionLayoutItem {
    NSDirectionalEdgeInsets _contentInsets;
    NSCollectionLayoutEdgeSpacing *_edgeSpacing;
    NSCollectionLayoutSize *_layoutSize;
    NSArray *_supplementaryItems;
}

+ (instancetype) itemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize {
    return [self itemWithLayoutSize: layoutSize supplementaryItems: nil];
}

+ (instancetype) itemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                 supplementaryItems:
                         (NSArray<NSCollectionLayoutSupplementaryItem *> *)
                                 supplementaryItems {
    NSCollectionLayoutItem *item = [[[self alloc] init] autorelease];

    item->_layoutSize = [layoutSize retain];
    item->_supplementaryItems =
            [(supplementaryItems ? supplementaryItems : @[]) copy];
    return item;
}

- (void) dealloc {
    [_edgeSpacing release];
    [_layoutSize release];
    [_supplementaryItems release];
    [super dealloc];
}

- (NSDirectionalEdgeInsets) contentInsets {
    return _contentInsets;
}

- (void) setContentInsets: (NSDirectionalEdgeInsets) contentInsets {
    _contentInsets = contentInsets;
}

- (NSCollectionLayoutEdgeSpacing *) edgeSpacing {
    return _edgeSpacing;
}

- (void) setEdgeSpacing: (NSCollectionLayoutEdgeSpacing *) edgeSpacing {
    edgeSpacing = [edgeSpacing copy];
    [_edgeSpacing release];
    _edgeSpacing = edgeSpacing;
}

- (NSCollectionLayoutSize *) layoutSize {
    return _layoutSize;
}

// Readonly on an item; the group, which declares it settable, goes through this.
- (void) _setSupplementaryItems: (NSArray *) supplementaryItems {
    supplementaryItems = [(supplementaryItems ? supplementaryItems : @[]) copy];
    [_supplementaryItems release];
    _supplementaryItems = supplementaryItems;
}

- (NSArray<NSCollectionLayoutSupplementaryItem *> *) supplementaryItems {
    return _supplementaryItems;
}

// A copy keeps every property; the subclasses add theirs on top of this.
- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutItem *copy = [[[self class] allocWithZone: zone] init];

    copy->_contentInsets = _contentInsets;
    copy->_edgeSpacing = [_edgeSpacing copy];
    copy->_layoutSize = [_layoutSize retain];
    copy->_supplementaryItems = [_supplementaryItems copy];
    return copy;
}

@end

@implementation NSCollectionLayoutSupplementaryItem {
    NSInteger _zIndex;
    NSString *_elementKind;
    NSCollectionLayoutAnchor *_containerAnchor;
    NSCollectionLayoutAnchor *_itemAnchor;
}

+ (instancetype) supplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                     elementKind: (NSString *) elementKind
                                 containerAnchor: (NSCollectionLayoutAnchor *) containerAnchor {
    return [self supplementaryItemWithLayoutSize: layoutSize
                                     elementKind: elementKind
                                 containerAnchor: containerAnchor
                                      itemAnchor: nil];
}

+ (instancetype) supplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                     elementKind: (NSString *) elementKind
                                 containerAnchor: (NSCollectionLayoutAnchor *) containerAnchor
                                      itemAnchor: (NSCollectionLayoutAnchor *) itemAnchor {
    NSCollectionLayoutSupplementaryItem *item =
            [self itemWithLayoutSize: layoutSize];

    item->_elementKind = [elementKind copy];
    item->_containerAnchor = [containerAnchor retain];
    item->_itemAnchor = [itemAnchor retain];
    return item;
}

- (void) dealloc {
    [_elementKind release];
    [_containerAnchor release];
    [_itemAnchor release];
    [super dealloc];
}

- (NSInteger) zIndex {
    return _zIndex;
}

- (void) setZIndex: (NSInteger) zIndex {
    _zIndex = zIndex;
}

- (NSString *) elementKind {
    return _elementKind;
}

- (NSCollectionLayoutAnchor *) containerAnchor {
    return _containerAnchor;
}

- (NSCollectionLayoutAnchor *) itemAnchor {
    return _itemAnchor;
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutSupplementaryItem *copy = [super copyWithZone: zone];

    copy->_zIndex = _zIndex;
    copy->_elementKind = [_elementKind copy];
    copy->_containerAnchor = [_containerAnchor retain];
    copy->_itemAnchor = [_itemAnchor retain];
    return copy;
}

@end

// The edges of the container a boundary supplementary item with this alignment is anchored to.
static NSDirectionalRectEdge EdgesForAlignment(NSRectAlignment alignment) {
    switch (alignment) {
    case NSRectAlignmentTop:
        return NSDirectionalRectEdgeTop;
    case NSRectAlignmentTopLeading:
        return NSDirectionalRectEdgeTop | NSDirectionalRectEdgeLeading;
    case NSRectAlignmentLeading:
        return NSDirectionalRectEdgeLeading;
    case NSRectAlignmentBottomLeading:
        return NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeLeading;
    case NSRectAlignmentBottom:
        return NSDirectionalRectEdgeBottom;
    case NSRectAlignmentBottomTrailing:
        return NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeTrailing;
    case NSRectAlignmentTrailing:
        return NSDirectionalRectEdgeTrailing;
    case NSRectAlignmentTopTrailing:
        return NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing;
    case NSRectAlignmentNone:
        break;
    }
    return NSDirectionalRectEdgeNone;
}

@implementation NSCollectionLayoutBoundarySupplementaryItem {
    BOOL _extendsBoundary;
    BOOL _pinToVisibleBounds;
    NSRectAlignment _alignment;
    NSPoint _offset;
}

+ (instancetype) boundarySupplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                             elementKind: (NSString *) elementKind
                                               alignment: (NSRectAlignment) alignment {
    return [self boundarySupplementaryItemWithLayoutSize: layoutSize
                                             elementKind: elementKind
                                               alignment: alignment
                                          absoluteOffset: NSZeroPoint];
}

// GUESS, none of it in the header: the container anchor is the alignment's edges (no item anchor), and a boundary
// item extends the boundary by default (the same property of UIKit's twin class defaults to true) and is not pinned.
+ (instancetype) boundarySupplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                             elementKind: (NSString *) elementKind
                                               alignment: (NSRectAlignment) alignment
                                          absoluteOffset: (NSPoint) absoluteOffset {
    NSCollectionLayoutBoundarySupplementaryItem *item = [self
            supplementaryItemWithLayoutSize: layoutSize
                                elementKind: elementKind
                            containerAnchor: [NSCollectionLayoutAnchor
                                                     layoutAnchorWithEdges: EdgesForAlignment(alignment)
                                                            absoluteOffset: absoluteOffset]];

    item->_alignment = alignment;
    item->_offset = absoluteOffset;
    item->_extendsBoundary = YES;
    return item;
}

- (BOOL) extendsBoundary {
    return _extendsBoundary;
}

- (void) setExtendsBoundary: (BOOL) extendsBoundary {
    _extendsBoundary = extendsBoundary;
}

- (BOOL) pinToVisibleBounds {
    return _pinToVisibleBounds;
}

- (void) setPinToVisibleBounds: (BOOL) pinToVisibleBounds {
    _pinToVisibleBounds = pinToVisibleBounds;
}

- (NSRectAlignment) alignment {
    return _alignment;
}

- (NSPoint) offset {
    return _offset;
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutBoundarySupplementaryItem *copy =
            [super copyWithZone: zone];

    copy->_extendsBoundary = _extendsBoundary;
    copy->_pinToVisibleBounds = _pinToVisibleBounds;
    copy->_alignment = _alignment;
    copy->_offset = _offset;
    return copy;
}

@end

@implementation NSCollectionLayoutDecorationItem {
    NSInteger _zIndex;
    NSString *_elementKind;
}

// GUESS: a background decoration fills its section, so its size is the whole container (the header gives none).
+ (instancetype) backgroundDecorationItemWithElementKind: (NSString *) elementKind {
    NSCollectionLayoutDecorationItem *item = [self
            itemWithLayoutSize: [NSCollectionLayoutSize
                                        sizeWithWidthDimension: [NSCollectionLayoutDimension fractionalWidthDimension: 1.0]
                                               heightDimension: [NSCollectionLayoutDimension fractionalHeightDimension: 1.0]]];

    item->_elementKind = [elementKind copy];
    return item;
}

- (void) dealloc {
    [_elementKind release];
    [super dealloc];
}

- (NSInteger) zIndex {
    return _zIndex;
}

- (void) setZIndex: (NSInteger) zIndex {
    _zIndex = zIndex;
}

- (NSString *) elementKind {
    return _elementKind;
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutDecorationItem *copy = [super copyWithZone: zone];

    copy->_zIndex = _zIndex;
    copy->_elementKind = [_elementKind copy];
    return copy;
}

@end

@implementation NSCollectionLayoutGroup {
    NSArray *_subitems;
    BOOL _vertical;
    NSCollectionLayoutSpacing *_interItemSpacing;
}

// The getter is the item's; -setSupplementaryItems: is below.
@dynamic supplementaryItems;

+ (instancetype) _groupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                             subitems: (NSArray *) subitems
                             vertical: (BOOL) vertical {
    NSCollectionLayoutGroup *group = [self itemWithLayoutSize: layoutSize];

    group->_subitems = [subitems copy];
    group->_vertical = vertical;
    return group;
}

// No layout engine exists to call the provider, and NSCollectionLayoutGroupCustomItem is not defined, so a custom group
// could only be a silent stub: fail loud instead.
+ (instancetype) customGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                              itemProvider: (NSCollectionLayoutGroupCustomItemProvider) itemProvider {
    [NSException raise: NSGenericException
                format: @"+[NSCollectionLayoutGroup customGroupWithLayoutSize:itemProvider:] is not implemented"];
    return nil;
}

+ (NSArray *) _repeatedItem: (NSCollectionLayoutItem *) item count: (NSInteger) count {
    NSMutableArray *items = [NSMutableArray array];

    for (NSInteger i = 0; i < count; i++)
        [items addObject: item];
    return items;
}

+ (instancetype) horizontalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                       subitem: (NSCollectionLayoutItem *) subitem
                                         count: (NSInteger) count {
    return [self horizontalGroupWithLayoutSize: layoutSize
                                      subitems: [self _repeatedItem: subitem count: count]];
}

+ (instancetype) horizontalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                      subitems: (NSArray *) subitems {
    return [self _groupWithLayoutSize: layoutSize subitems: subitems vertical: NO];
}

+ (instancetype) verticalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                     subitem: (NSCollectionLayoutItem *) subitem
                                       count: (NSInteger) count {
    return [self verticalGroupWithLayoutSize: layoutSize
                                    subitems: [self _repeatedItem: subitem count: count]];
}

+ (instancetype) verticalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                    subitems: (NSArray *) subitems {
    return [self _groupWithLayoutSize: layoutSize subitems: subitems vertical: YES];
}

- (void) dealloc {
    [_subitems release];
    [_interItemSpacing release];
    [super dealloc];
}

- (void) setSupplementaryItems: (NSArray<NSCollectionLayoutSupplementaryItem *> *) supplementaryItems {
    [self _setSupplementaryItems: supplementaryItems];
}

- (NSString *) visualDescription {
    return [NSString stringWithFormat: @"<%@: %@ group, %lu subitems, %lu supplementary items>", [self class],
                                       _vertical ? @"vertical" : @"horizontal", (unsigned long) [_subitems count],
                                       (unsigned long) [[self supplementaryItems] count]];
}

- (NSArray<NSCollectionLayoutItem *> *) subitems {
    return _subitems;
}

- (NSCollectionLayoutSpacing *) interItemSpacing {
    return _interItemSpacing;
}

- (void) setInterItemSpacing: (NSCollectionLayoutSpacing *) interItemSpacing {
    interItemSpacing = [interItemSpacing copy];
    [_interItemSpacing release];
    _interItemSpacing = interItemSpacing;
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutGroup *copy = [super copyWithZone: zone];

    copy->_subitems = [_subitems copy];
    copy->_vertical = _vertical;
    copy->_interItemSpacing = [_interItemSpacing copy];
    return copy;
}

@end

@implementation NSCollectionLayoutSection {
    NSCollectionLayoutGroup *_group;
    NSDirectionalEdgeInsets _contentInsets;
    CGFloat _interGroupSpacing;
    NSArray *_boundarySupplementaryItems;
    NSArray *_decorationItems;
    BOOL _supplementariesFollowContentInsets;
}

+ (instancetype) sectionWithGroup: (NSCollectionLayoutGroup *) group {
    NSCollectionLayoutSection *section = [[[self alloc] init] autorelease];

    section->_group = [group retain];
    section->_supplementariesFollowContentInsets = YES;
    return section;
}

- (void) dealloc {
    [_group release];
    [_boundarySupplementaryItems release];
    [_decorationItems release];
    [super dealloc];
}

- (NSDirectionalEdgeInsets) contentInsets {
    return _contentInsets;
}

- (void) setContentInsets: (NSDirectionalEdgeInsets) contentInsets {
    _contentInsets = contentInsets;
}

- (CGFloat) interGroupSpacing {
    return _interGroupSpacing;
}

- (void) setInterGroupSpacing: (CGFloat) interGroupSpacing {
    _interGroupSpacing = interGroupSpacing;
}

- (NSArray<NSCollectionLayoutBoundarySupplementaryItem *> *) boundarySupplementaryItems {
    return _boundarySupplementaryItems;
}

- (void) setBoundarySupplementaryItems: (NSArray<NSCollectionLayoutBoundarySupplementaryItem *> *) items {
    items = [items copy];
    [_boundarySupplementaryItems release];
    _boundarySupplementaryItems = items;
}

- (BOOL) supplementariesFollowContentInsets {
    return _supplementariesFollowContentInsets;
}

- (void) setSupplementariesFollowContentInsets: (BOOL) follow {
    _supplementariesFollowContentInsets = follow;
}

- (NSArray<NSCollectionLayoutDecorationItem *> *) decorationItems {
    return _decorationItems;
}

- (void) setDecorationItems: (NSArray<NSCollectionLayoutDecorationItem *> *) items {
    items = [items copy];
    [_decorationItems release];
    _decorationItems = items;
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutSection *copy = [[[self class] allocWithZone: zone] init];

    copy->_group = [_group copy];
    copy->_contentInsets = _contentInsets;
    copy->_interGroupSpacing = _interGroupSpacing;
    copy->_boundarySupplementaryItems = [_boundarySupplementaryItems copy];
    copy->_decorationItems = [_decorationItems copy];
    copy->_supplementariesFollowContentInsets = _supplementariesFollowContentInsets;
    return copy;
}

@end
