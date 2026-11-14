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
