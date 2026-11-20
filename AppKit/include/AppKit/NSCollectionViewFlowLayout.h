/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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
#import <Foundation/NSString.h>
#import <AppKit/NSCollectionViewLayout.h>
#import <AppKit/NSCollectionViewLayoutInvalidationContext.h>

APPKIT_EXPORT NSString *const NSCollectionElementKindSectionHeader;
APPKIT_EXPORT NSString *const NSCollectionElementKindSectionFooter;

typedef NS_ENUM(NSInteger, NSCollectionViewScrollDirection) {
    NSCollectionViewScrollDirectionVertical,
    NSCollectionViewScrollDirectionHorizontal,
};

@protocol NSCollectionViewDelegateFlowLayout <NSCollectionViewDelegate>
@optional
- (NSSize) collectionView: (NSCollectionView *) collectionView
                   layout: (NSCollectionViewLayout *) collectionViewLayout
   sizeForItemAtIndexPath: (NSIndexPath *) indexPath;
- (NSEdgeInsets) collectionView: (NSCollectionView *) collectionView
                         layout: (NSCollectionViewLayout *) collectionViewLayout
         insetForSectionAtIndex: (NSInteger) section;
- (CGFloat) collectionView: (NSCollectionView *) collectionView
                                 layout: (NSCollectionViewLayout *) collectionViewLayout
    minimumLineSpacingForSectionAtIndex: (NSInteger) section;
- (CGFloat) collectionView: (NSCollectionView *) collectionView
                                      layout: (NSCollectionViewLayout *) collectionViewLayout
    minimumInteritemSpacingForSectionAtIndex: (NSInteger) section;
- (NSSize) collectionView: (NSCollectionView *) collectionView
                             layout: (NSCollectionViewLayout *) collectionViewLayout
    referenceSizeForHeaderInSection: (NSInteger) section;
- (NSSize) collectionView: (NSCollectionView *) collectionView
                             layout: (NSCollectionViewLayout *) collectionViewLayout
    referenceSizeForFooterInSection: (NSInteger) section;
@end

// The instance variables fill 80 of the 124 bytes Apple's legacy (i386) layout has
@interface NSCollectionViewFlowLayout : NSCollectionViewLayout
{
    NSSize _itemSize;
    NSEdgeInsets _sectionInset;
    CGFloat _minimumLineSpacing;
    CGFloat _minimumInteritemSpacing;
    NSCollectionViewScrollDirection _scrollDirection;
    NSSize _estimatedItemSize;
    NSSize _headerReferenceSize;
    NSSize _footerReferenceSize;
    NSMutableArray *_sectionItems; // per section, the attributes of its items; nil until prepared
    NSMutableArray *_sectionLines; // per section, the rect (an NSValue) of each item's row or column
    NSMutableArray *_sectionStarts; // per section, where its first line begins (an NSNumber, along the flow)
    NSSize _contentSize;
    NS_LEGACY_IVAR_PAD(_NSCollectionViewFlowLayoutReserved, 44)
}

@property NSSize itemSize;
@property NSSize estimatedItemSize;
@property NSEdgeInsets sectionInset;
@property CGFloat minimumLineSpacing;
@property CGFloat minimumInteritemSpacing;
@property NSCollectionViewScrollDirection scrollDirection;
@property NSSize headerReferenceSize;
@property NSSize footerReferenceSize;

@end

@interface NSCollectionViewFlowLayoutInvalidationContext : NSCollectionViewLayoutInvalidationContext
{
    BOOL _invalidateFlowLayoutDelegateMetrics;
    BOOL _invalidateFlowLayoutAttributes;
    NS_LEGACY_IVAR_PAD(_NSCollectionViewFlowLayoutInvalidationContextReserved, 2)
}

@property BOOL invalidateFlowLayoutDelegateMetrics;
@property BOOL invalidateFlowLayoutAttributes;

@end
