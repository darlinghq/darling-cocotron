/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

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

#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSCollectionViewLayout.h>

// The instance variables fill 37 of the 252 bytes Apple's legacy (i386) layout has
@interface NSCollectionViewLayoutAttributes : NSObject <NSCopying> {
    NSRect _frame;
    CGFloat _alpha;
    NSInteger _zIndex;
    NSIndexPath *_indexPath;
    NSString *_representedElementKind;
    NSCollectionElementCategory _representedElementCategory;
    BOOL _hidden;
    NS_LEGACY_IVAR_PAD(_NSCollectionViewLayoutAttributesReserved, 215)
}

+ (instancetype) layoutAttributesForItemWithIndexPath: (NSIndexPath *) indexPath;
+ (instancetype) layoutAttributesForInterItemGapBeforeIndexPath: (NSIndexPath *) indexPath;
+ (instancetype) layoutAttributesForSupplementaryViewOfKind: (NSCollectionViewSupplementaryElementKind) elementKind
                                              withIndexPath: (NSIndexPath *) indexPath;
+ (instancetype) layoutAttributesForDecorationViewOfKind: (NSCollectionViewDecorationElementKind) decorationViewKind
                                           withIndexPath: (NSIndexPath *) indexPath;

@property NSRect frame;
@property NSSize size;
@property CGFloat alpha;
@property NSInteger zIndex;
@property(getter=isHidden) BOOL hidden;
@property(strong) NSIndexPath *indexPath;
@property(readonly) NSCollectionElementCategory representedElementCategory;
@property(readonly) NSString *representedElementKind;

@end
