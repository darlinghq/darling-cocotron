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

#import <AppKit/NSLayoutConstraint.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

// The compositional layout's data model (NSCollectionViewCompositionalLayout.h, macOS 10.15): the objects an
// application builds to describe a layout. Nothing here measures or places items.
//
// The NSCollectionLayout* classes are implemented by CollectionViewCore (CollectionViewCore/NSCollectionLayout.m,
// which AppKit re-exports), not by AppKit: on a dyld-cache stage that image is the cache's own. They declare no
// instance variables here, so nothing compiled against this header depends on how either image lays them out.

@interface NSCollectionLayoutDimension : NSObject <NSCopying>

// A fraction of the width or height of the containing group.
+ (instancetype) fractionalWidthDimension: (CGFloat) fractionalWidth;
+ (instancetype) fractionalHeightDimension: (CGFloat) fractionalHeight;
// A point value.
+ (instancetype) absoluteDimension: (CGFloat) absoluteDimension;
// A point value, an estimate: the actual size is known when the content is rendered.
+ (instancetype) estimatedDimension: (CGFloat) estimatedDimension;

@property(readonly) BOOL isFractionalWidth;
@property(readonly) BOOL isFractionalHeight;
@property(readonly) BOOL isAbsolute;
@property(readonly) BOOL isEstimated;
@property(readonly) CGFloat dimension;

@end

@interface NSCollectionLayoutSize : NSObject <NSCopying>

+ (instancetype) sizeWithWidthDimension: (NSCollectionLayoutDimension *) width
                        heightDimension: (NSCollectionLayoutDimension *) height;

@property(readonly) NSCollectionLayoutDimension *widthDimension;
@property(readonly) NSCollectionLayoutDimension *heightDimension;

@end
