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
#import <AppKit/NSCollectionView.h>
#import <Foundation/NSString.h>

typedef NSString *NSCollectionViewDecorationElementKind NS_SWIFT_BRIDGED_TYPEDEF;

APPKIT_EXPORT NSCollectionViewSupplementaryElementKind const
        NSCollectionElementKindInterItemGapIndicator;

typedef NS_ENUM(NSInteger, NSCollectionElementCategory) {
    NSCollectionElementCategoryItem,
    NSCollectionElementCategorySupplementaryView,
    NSCollectionElementCategoryDecorationView,
    NSCollectionElementCategoryInterItemGap,
};

typedef NS_ENUM(NSInteger, NSCollectionUpdateAction) {
    NSCollectionUpdateActionInsert,
    NSCollectionUpdateActionDelete,
    NSCollectionUpdateActionReload,
    NSCollectionUpdateActionMove,
    NSCollectionUpdateActionNone,
};

@class NSCollectionViewLayoutAttributes, NSCollectionViewLayoutInvalidationContext, NSNib;

// The instance variables fill 8 of the 124 bytes Apple's legacy (i386) layout has
@interface NSCollectionViewLayout : NSObject <NSCoding> {
    NSCollectionView *_collectionView; // not retained: the collection view owns its layout
    NSMutableDictionary *_decorationViews;
    NS_LEGACY_IVAR_PAD(_NSCollectionViewLayoutReserved, 116)
}

@property(readonly, weak) NSCollectionView *collectionView;

- (void) invalidateLayout;
- (void) invalidateLayoutWithContext: (NSCollectionViewLayoutInvalidationContext *) context;

- (void) registerClass: (Class) viewClass forDecorationViewOfKind: (NSCollectionViewDecorationElementKind) elementKind;
- (void) registerNib: (NSNib *) nib forDecorationViewOfKind: (NSCollectionViewDecorationElementKind) elementKind;

@end

@interface NSCollectionViewLayout (NSSubclassingHooks)

@property(class, readonly) Class layoutAttributesClass;
@property(class, readonly) Class invalidationContextClass;

- (void) prepareLayout;
- (NSArray<__kindof NSCollectionViewLayoutAttributes *> *) layoutAttributesForElementsInRect: (NSRect) rect;
- (NSCollectionViewLayoutAttributes *) layoutAttributesForItemAtIndexPath: (NSIndexPath *) indexPath;
- (NSCollectionViewLayoutAttributes *) layoutAttributesForSupplementaryViewOfKind: (NSCollectionViewSupplementaryElementKind) elementKind
                                                                      atIndexPath: (NSIndexPath *) indexPath;
- (NSCollectionViewLayoutAttributes *) layoutAttributesForDecorationViewOfKind: (NSCollectionViewDecorationElementKind) elementKind
                                                                   atIndexPath: (NSIndexPath *) indexPath;
- (NSCollectionViewLayoutAttributes *) layoutAttributesForDropTargetAtPoint: (NSPoint) pointInCollectionView;
- (NSCollectionViewLayoutAttributes *) layoutAttributesForInterItemGapBeforeIndexPath: (NSIndexPath *) indexPath;

- (BOOL) shouldInvalidateLayoutForBoundsChange: (NSRect) newBounds;
- (NSCollectionViewLayoutInvalidationContext *) invalidationContextForBoundsChange: (NSRect) newBounds;

- (NSPoint) targetContentOffsetForProposedContentOffset: (NSPoint) proposedContentOffset;

@property(readonly) NSSize collectionViewContentSize;

@end
