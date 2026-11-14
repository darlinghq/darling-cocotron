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
