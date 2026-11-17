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
// The instance variables are declared @private in the public header: the legacy Objective-C ABI (i386) cannot
// declare them in an @implementation. No other image accesses them.

#import <AppKit/NSCollectionViewCompositionalLayout.h>

// The value classes below are immutable: a copy is the object itself.
// Two optional property values are equal when both are nil or the first is equal to the second.
static BOOL propertiesEqual(id a, id b) {
    return a == b || (a != nil && [a isEqual: b]);
}

static BOOL insetsEqual(NSDirectionalEdgeInsets a, NSDirectionalEdgeInsets b) {
    return a.top == b.top && a.leading == b.leading && a.bottom == b.bottom && a.trailing == b.trailing;
}

enum {
    DimensionKindFractionalWidth,
    DimensionKindFractionalHeight,
    DimensionKindAbsolute,
    DimensionKindEstimated,
};

@implementation NSCollectionLayoutDimension

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

- (BOOL) isEqual: (id) object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [NSCollectionLayoutDimension class]])
        return NO;
    NSCollectionLayoutDimension *other = object;
    return _kind == other->_kind && _dimension == other->_dimension;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutSize

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

- (BOOL) isEqual: (id) object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [NSCollectionLayoutSize class]])
        return NO;
    NSCollectionLayoutSize *other = object;
    return propertiesEqual(_widthDimension, other->_widthDimension) &&
           propertiesEqual(_heightDimension, other->_heightDimension);
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutSpacing

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

- (BOOL) isEqual: (id) object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [NSCollectionLayoutSpacing class]])
        return NO;
    NSCollectionLayoutSpacing *other = object;
    return _spacing == other->_spacing && _flexible == other->_flexible;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutEdgeSpacing

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

- (BOOL) isEqual: (id) object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [NSCollectionLayoutEdgeSpacing class]])
        return NO;
    NSCollectionLayoutEdgeSpacing *other = object;
    return propertiesEqual(_leading, other->_leading) && propertiesEqual(_top, other->_top) &&
           propertiesEqual(_trailing, other->_trailing) && propertiesEqual(_bottom, other->_bottom);
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@implementation NSCollectionLayoutAnchor

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

// QUIRK: an anchor made without an offset has a zero offset and reports it as an absolute offset (isAbsoluteOffset is
// YES, isFractionalOffset NO), whatever the edges. Not documented. Evidence: black-box observation on macOS 26.7.3
// and 27.0.1 (tier 2), vd-upstream/mac-probes/collectionlayout.
// Test: tests/appkit-collection-layout-spacing-anchor.m ("quirk: an anchor without an offset ...").
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

- (BOOL) isEqual: (id) object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [NSCollectionLayoutAnchor class]])
        return NO;
    NSCollectionLayoutAnchor *other = object;
    return _edges == other->_edges && _offset.x == other->_offset.x && _offset.y == other->_offset.y &&
           _fractional == other->_fractional;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

@end

@interface NSCollectionLayoutItem ()
- (void) _setSupplementaryItems: (NSArray *) supplementaryItems;
- (void) _setLayoutSize: (NSCollectionLayoutSize *) layoutSize;
@end

@implementation NSCollectionLayoutItem

+ (instancetype) itemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize {
    return [self itemWithLayoutSize: layoutSize supplementaryItems: @[]];
}

+ (instancetype) itemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                 supplementaryItems:
                         (NSArray<NSCollectionLayoutSupplementaryItem *> *)
                                 supplementaryItems {
    NSCollectionLayoutItem *item = [[[self alloc] init] autorelease];

    item->_layoutSize = [layoutSize retain];
    // QUIRK: passing nil for the supplementary items does not raise and leaves the property nil (an item made without
    // them has an empty array). Not documented. Evidence: black-box observation on macOS 26.7.3 and 27.0.1 (tier 2).
    // Test: tests/appkit-collection-layout-items.m ("quirk: nil supplementary items ...").
    item->_supplementaryItems = [supplementaryItems copy];
    // QUIRK: a new item, supplementary item or group has an edge spacing, with a fixed spacing of zero on every edge,
    // not nil (a decoration item has none). Not documented. Evidence: black-box observation on macOS 26.7.3 (tier 2).
    // Test: tests/appkit-collection-layout-items.m ("quirk: edge spacing starts ...").
    NSCollectionLayoutSpacing *none = [NSCollectionLayoutSpacing fixedSpacing: 0];
    item->_edgeSpacing = [[NSCollectionLayoutEdgeSpacing spacingForLeading: none top: none trailing: none bottom: none] retain];
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

- (void) _setLayoutSize: (NSCollectionLayoutSize *) layoutSize {
    layoutSize = [layoutSize retain];
    [_layoutSize release];
    _layoutSize = layoutSize;
}

// Readonly on an item; the group, which declares it settable, goes through this.
// QUIRK: setting nil does not raise and leaves the property nil. Not documented. Evidence: black-box observation on
// macOS 26.7.3 and 27.0.1 (tier 2). Test: tests/appkit-collection-layout-group-section.m ("quirk: nil supplementary
// items ...").
- (void) _setSupplementaryItems: (NSArray *) supplementaryItems {
    supplementaryItems = [supplementaryItems copy];
    [_supplementaryItems release];
    _supplementaryItems = supplementaryItems;
}

- (NSArray<NSCollectionLayoutSupplementaryItem *> *) supplementaryItems {
    return _supplementaryItems;
}

// A copy keeps every property; the subclasses add theirs on top of this.
// QUIRK: the value classes of the compositional layout (dimension, size, spacing, edge spacing, anchor, item and its
// subclasses, section) compare by their properties, but do not override -hash: equal objects have different hashes,
// and a copy of an item, group or section is equal to the original. An item takes any item, including a group or a
// supplementary item with equal item properties, as equal; a subclass additionally requires the other object to be
// of that subclass, and the subitems and supplementary items are compared in order, each by the receiver's -isEqual:.
// The group's item provider and the section's invalidation handler are not compared by value (two different blocks are
// equal); a handler on one section and none on the other is a difference. A custom group item and the compositional
// layout configuration compare by identity. Not documented. Evidence: black-box observation on macOS 26.7.3 and
// 27.0.1 (tier 2), vd-upstream/mac-probes/collectionlayout/equality-*.
// Test: tests/appkit-collection-layout-equality.m.
- (BOOL) isEqual: (id) object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [NSCollectionLayoutItem class]])
        return NO;
    NSCollectionLayoutItem *other = object;
    return insetsEqual(_contentInsets, other->_contentInsets) && propertiesEqual(_edgeSpacing, other->_edgeSpacing) &&
           propertiesEqual(_layoutSize, other->_layoutSize) &&
           propertiesEqual(_supplementaryItems, other->_supplementaryItems);
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutItem *copy = [[[self class] allocWithZone: zone] init];

    copy->_contentInsets = _contentInsets;
    copy->_edgeSpacing = [_edgeSpacing copy];
    copy->_layoutSize = [_layoutSize retain];
    copy->_supplementaryItems = [_supplementaryItems copy];
    return copy;
}

@end

@implementation NSCollectionLayoutSupplementaryItem

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
    // QUIRK: a supplementary item (a boundary one too) starts with a z index of 1, not 0. Not documented. Evidence:
    // black-box observation on macOS 26.7.3 and 27.0.1 (tier 2).
    // Test: tests/appkit-collection-layout-items.m and appkit-collection-layout-boundary-decoration.m.
    item->_zIndex = 1;
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

- (BOOL) isEqual: (id) object {
    if (![object isKindOfClass: [NSCollectionLayoutSupplementaryItem class]])
        return NO;
    NSCollectionLayoutSupplementaryItem *other = object;
    return [super isEqual: object] && _zIndex == other->_zIndex && propertiesEqual(_elementKind, other->_elementKind) &&
           propertiesEqual(_containerAnchor, other->_containerAnchor) &&
           propertiesEqual(_itemAnchor, other->_itemAnchor);
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

@implementation NSCollectionLayoutBoundarySupplementaryItem

+ (instancetype) boundarySupplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                             elementKind: (NSString *) elementKind
                                               alignment: (NSRectAlignment) alignment {
    return [self boundarySupplementaryItemWithLayoutSize: layoutSize
                                             elementKind: elementKind
                                               alignment: alignment
                                          absoluteOffset: NSZeroPoint];
}

// QUIRK: a boundary item has no container anchor and no item anchor whatever its alignment (its alignment and offset
// say where it goes), extends the boundary and is not pinned to the visible bounds. Only the last two are documented
// by the header's property names alone. Evidence: black-box observation on macOS 26.7.3 and 27.0.1 (tier 2), all nine
// alignments. Test: tests/appkit-collection-layout-boundary-decoration.m.
+ (instancetype) boundarySupplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                             elementKind: (NSString *) elementKind
                                               alignment: (NSRectAlignment) alignment
                                          absoluteOffset: (NSPoint) absoluteOffset {
    NSCollectionLayoutBoundarySupplementaryItem *item = [self
            supplementaryItemWithLayoutSize: layoutSize
                                elementKind: elementKind
                            containerAnchor: nil];

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

- (BOOL) isEqual: (id) object {
    if (![object isKindOfClass: [NSCollectionLayoutBoundarySupplementaryItem class]])
        return NO;
    NSCollectionLayoutBoundarySupplementaryItem *other = object;
    return [super isEqual: object] && _extendsBoundary == other->_extendsBoundary &&
           _pinToVisibleBounds == other->_pinToVisibleBounds && _alignment == other->_alignment &&
           _offset.x == other->_offset.x && _offset.y == other->_offset.y;
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

@implementation NSCollectionLayoutDecorationItem

// QUIRK: a background decoration item has a layout size of the full width and full height of its container (both
// fractional, 1.0), a z index of 0, no content insets and no edge spacing. Not documented. Evidence: black-box
// observation on macOS 26.7.3 and 27.0.1 (tier 2). Test: tests/appkit-collection-layout-boundary-decoration.m.
+ (instancetype) backgroundDecorationItemWithElementKind: (NSString *) elementKind {
    NSCollectionLayoutDecorationItem *item = [self
            itemWithLayoutSize: [NSCollectionLayoutSize
                                        sizeWithWidthDimension: [NSCollectionLayoutDimension fractionalWidthDimension: 1.0]
                                               heightDimension: [NSCollectionLayoutDimension fractionalHeightDimension: 1.0]]];

    item->_elementKind = [elementKind copy];
    [item setEdgeSpacing: nil];
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

- (BOOL) isEqual: (id) object {
    if (![object isKindOfClass: [NSCollectionLayoutDecorationItem class]])
        return NO;
    NSCollectionLayoutDecorationItem *other = object;
    return [super isEqual: object] && _zIndex == other->_zIndex && propertiesEqual(_elementKind, other->_elementKind);
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutDecorationItem *copy = [super copyWithZone: zone];

    copy->_zIndex = _zIndex;
    copy->_elementKind = [_elementKind copy];
    return copy;
}

@end

@implementation NSCollectionLayoutGroup

// The getter is the item's; -setSupplementaryItems: is below.
@dynamic supplementaryItems;

+ (instancetype) _groupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                             subitems: (NSArray *) subitems
                             vertical: (BOOL) vertical
                              checked: (BOOL) checked {
    // A group needs at least one subitem; nil and an empty array both raise (observed on macOS 26.7.3 and 27.0.1;
    // tests/appkit-collection-layout-group-section.m).
    if (checked && [subitems count] == 0)
        [NSException raise: NSInternalInconsistencyException format: @"At least 1 subitem is required for a group"];

    NSCollectionLayoutGroup *group = [self itemWithLayoutSize: layoutSize];

    group->_subitems = [subitems copy];
    group->_vertical = vertical;
    // QUIRK: a new group has a fixed inter item spacing of zero, not nil. Not documented. Evidence: black-box
    // observation on macOS 26.7.3 (tier 2). Test: tests/appkit-collection-layout-group-section.m.
    group->_interItemSpacing = [[NSCollectionLayoutSpacing fixedSpacing: 0] retain];
    return group;
}

// QUIRK: a custom group has no subitems (an empty array, not nil), keeps the provider without calling it at creation
// (it is called only while laying out), and has a zero fixed inter item spacing like any group. A nil layout size raises NSInternalInconsistencyException (checked first), and so does a nil provider.
// Not documented. Evidence: black-box observation on macOS 26.7.3 and 27.0.1 arm64 (tier 2). Test:
// tests/appkit-collection-layout-group-section.m ("quirk: a custom group ...").
+ (instancetype) customGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                              itemProvider: (NSCollectionLayoutGroupCustomItemProvider) itemProvider {
    if (layoutSize == nil)
        [NSException raise: NSInternalInconsistencyException format: @"A size is required."];
    if (itemProvider == nil)
        [NSException raise: NSInternalInconsistencyException format: @"At least 1 subitem is required for a group"];

    NSCollectionLayoutGroup *group = [self _groupWithLayoutSize: layoutSize subitems: @[] vertical: NO checked: NO];

    group->_itemProvider = [itemProvider copy];
    return group;
}

// QUIRK: a repeating group (a subitem and a count) holds one copy of the subitem, not count of them, and the copy's
// size along the group's direction (the width of a horizontal group, the height of a vertical one) becomes the
// fractional dimension 1 / count; the other dimension is kept. A count below 1 raises NSInternalInconsistencyException
// and a nil subitem NSInvalidArgumentException. Not documented. Evidence: black-box observation on macOS 26.7.3 (tier
// 2). Test: tests/appkit-collection-layout-group-section.m ("quirk: a repeating group ...").
+ (instancetype) _groupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                              subitem: (NSCollectionLayoutItem *) subitem
                                count: (NSInteger) count
                             vertical: (BOOL) vertical {
    if (count < 1)
        [NSException raise: NSInternalInconsistencyException
                    format: @"A repeating %@ group should specify a count >= 1", vertical ? @"vertical" : @"horizontal"];
    if (subitem == nil)
        [NSException raise: NSInvalidArgumentException format: @"attempt to insert nil subitem"];

    NSCollectionLayoutItem *repeated = [[subitem copy] autorelease];
    NSCollectionLayoutDimension *share = vertical ? [NSCollectionLayoutDimension fractionalHeightDimension: 1.0 / count]
                                                  : [NSCollectionLayoutDimension fractionalWidthDimension: 1.0 / count];
    NSCollectionLayoutSize *size = [repeated layoutSize];

    [repeated _setLayoutSize: vertical ? [NSCollectionLayoutSize sizeWithWidthDimension: [size widthDimension]
                                                                         heightDimension: share]
                                       : [NSCollectionLayoutSize sizeWithWidthDimension: share
                                                                         heightDimension: [size heightDimension]]];

    NSCollectionLayoutGroup *group = [self _groupWithLayoutSize: layoutSize subitems: @[repeated] vertical: vertical checked: YES];

    group->_count = count;
    return group;
}

+ (instancetype) horizontalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                       subitem: (NSCollectionLayoutItem *) subitem
                                         count: (NSInteger) count {
    return [self _groupWithLayoutSize: layoutSize subitem: subitem count: count vertical: NO];
}

+ (instancetype) horizontalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                      subitems: (NSArray *) subitems {
    return [self _groupWithLayoutSize: layoutSize subitems: subitems vertical: NO checked: YES];
}

+ (instancetype) verticalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                     subitem: (NSCollectionLayoutItem *) subitem
                                       count: (NSInteger) count {
    return [self _groupWithLayoutSize: layoutSize subitem: subitem count: count vertical: YES];
}

+ (instancetype) verticalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                    subitems: (NSArray *) subitems {
    return [self _groupWithLayoutSize: layoutSize subitems: subitems vertical: YES checked: YES];
}

- (void) dealloc {
    [_subitems release];
    [_interItemSpacing release];
    [_itemProvider release];
    [super dealloc];
}

- (void) setSupplementaryItems: (NSArray<NSCollectionLayoutSupplementaryItem *> *) supplementaryItems {
    [self _setSupplementaryItems: supplementaryItems];
}

// A debugging aid: macOS answers a text drawing of the group's frame, whose exact shape nothing should depend on.
// This answers a one-line summary of the group instead.
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

- (BOOL) isEqual: (id) object {
    if (![object isKindOfClass: [NSCollectionLayoutGroup class]])
        return NO;
    NSCollectionLayoutGroup *other = object;
    return [super isEqual: object] && propertiesEqual(_subitems, other->_subitems) && _count == other->_count &&
           _vertical == other->_vertical && propertiesEqual(_interItemSpacing, other->_interItemSpacing);
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutGroup *copy = [super copyWithZone: zone];

    copy->_subitems = [_subitems copy];
    copy->_vertical = _vertical;
    copy->_count = _count;
    copy->_interItemSpacing = [_interItemSpacing copy];
    copy->_itemProvider = [_itemProvider copy];
    return copy;
}

@end

@implementation NSCollectionLayoutGroupCustomItem

+ (instancetype) customItemWithFrame: (NSRect) frame {
    return [self customItemWithFrame: frame zIndex: 0];
}

+ (instancetype) customItemWithFrame: (NSRect) frame zIndex: (NSInteger) zIndex {
    NSCollectionLayoutGroupCustomItem *item = [[[self alloc] init] autorelease];

    item->_frame = frame;
    item->_zIndex = zIndex;
    return item;
}

- (NSRect) frame {
    return _frame;
}

- (NSInteger) zIndex {
    return _zIndex;
}

// QUIRK: a copy of a custom item is a new object that keeps the frame and zIndex but is not equal to the original,
// and two items made alike are not equal either: no -isEqual: or -hash is defined, so equality is identity. Not
// documented. Evidence: black-box observation on macOS 26.7.3 and 27.0.1 arm64 (tier 2). Test:
// tests/appkit-collection-layout-group-section.m ("quirk: a custom item ...").
- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutGroupCustomItem *copy = [[[self class] allocWithZone: zone] init];

    copy->_frame = _frame;
    copy->_zIndex = _zIndex;
    return copy;
}

@end

@implementation NSCollectionLayoutSection

+ (instancetype) sectionWithGroup: (NSCollectionLayoutGroup *) group {
    // A nil group raises (observed on macOS 26.7.3 and 27.0.1; tests/appkit-collection-layout-group-section.m).
    if (group == nil)
        [NSException raise: NSInternalInconsistencyException format: @"Invalid parameter not satisfying: group"];

    NSCollectionLayoutSection *section = [[[self alloc] init] autorelease];

    section->_group = [group retain];
    section->_boundarySupplementaryItems = [@[] retain];
    section->_decorationItems = [@[] retain];
    // The default is YES (observed on macOS 26.7.3 and 27.0.1; tests/appkit-collection-layout-group-section.m).
    section->_supplementariesFollowContentInsets = YES;
    return section;
}

- (void) dealloc {
    [_group release];
    [_boundarySupplementaryItems release];
    [_decorationItems release];
    [_visibleItemsInvalidationHandler release];
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

// QUIRK: setting nil does not raise and leaves the property nil. Not documented. Evidence: black-box observation on
// macOS 26.7.3 and 27.0.1 (tier 2). Test: tests/appkit-collection-layout-group-section.m ("quirk: nil on a section").
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

// QUIRK: setting nil does not raise and leaves an empty array (unlike the boundary items, which become nil). Not
// documented. Evidence: black-box observation on macOS 26.7.3 and 27.0.1 (tier 2).
// Test: tests/appkit-collection-layout-group-section.m ("quirk: nil on a section").
- (void) setDecorationItems: (NSArray<NSCollectionLayoutDecorationItem *> *) items {
    items = [(items ? items : @[]) copy];
    [_decorationItems release];
    _decorationItems = items;
}

- (NSCollectionLayoutSectionOrthogonalScrollingBehavior) orthogonalScrollingBehavior {
    return _orthogonalScrollingBehavior;
}

- (void) setOrthogonalScrollingBehavior: (NSCollectionLayoutSectionOrthogonalScrollingBehavior) behavior {
    _orthogonalScrollingBehavior = behavior;
}

- (NSCollectionLayoutSectionVisibleItemsInvalidationHandler) visibleItemsInvalidationHandler {
    return _visibleItemsInvalidationHandler;
}

- (void) setVisibleItemsInvalidationHandler: (NSCollectionLayoutSectionVisibleItemsInvalidationHandler) handler {
    handler = [handler copy];
    [_visibleItemsInvalidationHandler release];
    _visibleItemsInvalidationHandler = handler;
}

- (BOOL) isEqual: (id) object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [NSCollectionLayoutSection class]])
        return NO;
    NSCollectionLayoutSection *other = object;
    return propertiesEqual(_group, other->_group) && insetsEqual(_contentInsets, other->_contentInsets) &&
           _interGroupSpacing == other->_interGroupSpacing &&
           propertiesEqual(_boundarySupplementaryItems, other->_boundarySupplementaryItems) &&
           propertiesEqual(_decorationItems, other->_decorationItems) &&
           _supplementariesFollowContentInsets == other->_supplementariesFollowContentInsets &&
           _orthogonalScrollingBehavior == other->_orthogonalScrollingBehavior &&
           (_visibleItemsInvalidationHandler != nil) == (other->_visibleItemsInvalidationHandler != nil);
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionLayoutSection *copy = [[[self class] allocWithZone: zone] init];

    copy->_group = [_group copy];
    copy->_contentInsets = _contentInsets;
    copy->_interGroupSpacing = _interGroupSpacing;
    copy->_boundarySupplementaryItems = [_boundarySupplementaryItems copy];
    copy->_decorationItems = [_decorationItems copy];
    copy->_supplementariesFollowContentInsets = _supplementariesFollowContentInsets;
    copy->_orthogonalScrollingBehavior = _orthogonalScrollingBehavior;
    copy->_visibleItemsInvalidationHandler = [_visibleItemsInvalidationHandler copy];
    return copy;
}

@end
