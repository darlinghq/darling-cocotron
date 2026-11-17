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
#import <AppKit/NSCollectionViewFlowLayout.h>
#import <AppKit/NSCollectionViewLayout.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

// The compositional layout's data model (NSCollectionViewCompositionalLayout.h, macOS 10.15): the objects an
// application builds to describe a layout. Nothing here measures or places items.
//
// The NSCollectionLayout* classes are implemented by CollectionViewCore (CollectionViewCore/NSCollectionLayout.m,
// which AppKit re-exports), not by AppKit: on a dyld-cache stage that image is the cache's own. They declare no
// instance variables here, so nothing compiled against this header depends on how either image lays them out.

@class NSCollectionLayoutSupplementaryItem;
// Edge specification interpreted according to the user interface layout direction.
typedef NS_OPTIONS(NSUInteger, NSDirectionalRectEdge) {
    NSDirectionalRectEdgeNone = 0,
    NSDirectionalRectEdgeTop = 1 << 0,
    NSDirectionalRectEdgeLeading = 1 << 1,
    NSDirectionalRectEdgeBottom = 1 << 2,
    NSDirectionalRectEdgeTrailing = 1 << 3,
    NSDirectionalRectEdgeAll = NSDirectionalRectEdgeTop | NSDirectionalRectEdgeLeading |
                               NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeTrailing
};
// Alignment specification interpreted according to the user interface layout direction.
typedef NS_ENUM(NSInteger, NSRectAlignment) {
    NSRectAlignmentNone = 0,
    NSRectAlignmentTop,
    NSRectAlignmentTopLeading,
    NSRectAlignmentLeading,
    NSRectAlignmentBottomLeading,
    NSRectAlignmentBottom,
    NSRectAlignmentBottomTrailing,
    NSRectAlignmentTrailing,
    NSRectAlignmentTopTrailing,
};

@interface NSCollectionLayoutDimension : NSObject <NSCopying> {
@private
    NSInteger _kind;
    CGFloat _dimension;
}

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

@interface NSCollectionLayoutSize : NSObject <NSCopying> {
@private
    NSCollectionLayoutDimension *_widthDimension;
    NSCollectionLayoutDimension *_heightDimension;
}

+ (instancetype) sizeWithWidthDimension: (NSCollectionLayoutDimension *) width
                        heightDimension: (NSCollectionLayoutDimension *) height;

@property(readonly) NSCollectionLayoutDimension *widthDimension;
@property(readonly) NSCollectionLayoutDimension *heightDimension;

@end

@interface NSCollectionLayoutSpacing : NSObject <NSCopying> {
@private
    CGFloat _spacing;
    BOOL _flexible;
}

// A flexible spacing is a minimum (>=); a fixed spacing is exact (==).
+ (instancetype) flexibleSpacing: (CGFloat) flexibleSpacing;
+ (instancetype) fixedSpacing: (CGFloat) fixedSpacing;

@property(readonly) CGFloat spacing;
@property(readonly) BOOL isFlexibleSpacing;
@property(readonly) BOOL isFixedSpacing;

@end

@interface NSCollectionLayoutEdgeSpacing : NSObject <NSCopying> {
@private
    NSCollectionLayoutSpacing *_leading;
    NSCollectionLayoutSpacing *_top;
    NSCollectionLayoutSpacing *_trailing;
    NSCollectionLayoutSpacing *_bottom;
}

// Additional outsets around items; an edge may be omitted.
+ (instancetype) spacingForLeading: (NSCollectionLayoutSpacing *) leading
                               top: (NSCollectionLayoutSpacing *) top
                          trailing: (NSCollectionLayoutSpacing *) trailing
                            bottom: (NSCollectionLayoutSpacing *) bottom;

@property(readonly) NSCollectionLayoutSpacing *leading;
@property(readonly) NSCollectionLayoutSpacing *top;
@property(readonly) NSCollectionLayoutSpacing *trailing;
@property(readonly) NSCollectionLayoutSpacing *bottom;

@end

@interface NSCollectionLayoutAnchor : NSObject <NSCopying> {
@private
    NSDirectionalRectEdge _edges;
    NSPoint _offset;
    BOOL _fractional;
}

+ (instancetype) layoutAnchorWithEdges: (NSDirectionalRectEdge) edges;
+ (instancetype) layoutAnchorWithEdges: (NSDirectionalRectEdge) edges
                        absoluteOffset: (NSPoint) absoluteOffset;
+ (instancetype) layoutAnchorWithEdges: (NSDirectionalRectEdge) edges
                      fractionalOffset: (NSPoint) fractionalOffset;

@property(readonly) NSDirectionalRectEdge edges;
@property(readonly) NSPoint offset;
@property(readonly) BOOL isAbsoluteOffset;
@property(readonly) BOOL isFractionalOffset;

@end

@interface NSCollectionLayoutItem : NSObject <NSCopying> {
@private
    NSDirectionalEdgeInsets _contentInsets;
    NSCollectionLayoutEdgeSpacing *_edgeSpacing;
    NSCollectionLayoutSize *_layoutSize;
    NSArray *_supplementaryItems;
}

+ (instancetype) itemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize;
+ (instancetype) itemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                 supplementaryItems:
                         (NSArray<NSCollectionLayoutSupplementaryItem *> *)
                                 supplementaryItems;

// Adjusts the final size of the item after layout; ignored for estimated dimensions.
@property NSDirectionalEdgeInsets contentInsets;
// Additional space surrounding the item when laying out.
@property(copy, nullable) NSCollectionLayoutEdgeSpacing *edgeSpacing;
@property(readonly) NSCollectionLayoutSize *layoutSize;
@property(readonly) NSArray<NSCollectionLayoutSupplementaryItem *> *supplementaryItems;

@end

@interface NSCollectionLayoutSupplementaryItem : NSCollectionLayoutItem {
@private
    NSInteger _zIndex;
    NSString *_elementKind;
    NSCollectionLayoutAnchor *_containerAnchor;
    NSCollectionLayoutAnchor *_itemAnchor;
}

+ (instancetype) supplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                     elementKind: (NSString *) elementKind
                                 containerAnchor: (NSCollectionLayoutAnchor *) containerAnchor;
+ (instancetype) supplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                     elementKind: (NSString *) elementKind
                                 containerAnchor: (NSCollectionLayoutAnchor *) containerAnchor
                                      itemAnchor: (NSCollectionLayoutAnchor *) itemAnchor;

@property NSInteger zIndex;
@property(readonly) NSString *elementKind;
@property(readonly) NSCollectionLayoutAnchor *containerAnchor;
@property(readonly, nullable) NSCollectionLayoutAnchor *itemAnchor;

@end

@interface NSCollectionLayoutBoundarySupplementaryItem : NSCollectionLayoutSupplementaryItem {
@private
    BOOL _extendsBoundary;
    BOOL _pinToVisibleBounds;
    NSRectAlignment _alignment;
    NSPoint _offset;
}

+ (instancetype) boundarySupplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                             elementKind: (NSString *) elementKind
                                               alignment: (NSRectAlignment) alignment;
+ (instancetype) boundarySupplementaryItemWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                             elementKind: (NSString *) elementKind
                                               alignment: (NSRectAlignment) alignment
                                          absoluteOffset: (NSPoint) absoluteOffset;

@property BOOL extendsBoundary;
@property BOOL pinToVisibleBounds;
@property(readonly) NSRectAlignment alignment;
@property(readonly) NSPoint offset;

@end

@interface NSCollectionLayoutDecorationItem : NSCollectionLayoutItem {
@private
    NSInteger _zIndex;
    NSString *_elementKind;
}

+ (instancetype) backgroundDecorationItemWithElementKind: (NSString *) elementKind;

// Default 0; the other items of a section are promoted to 1.
@property NSInteger zIndex;
@property(readonly) NSString *elementKind;

@end

@protocol NSCollectionLayoutEnvironment;
@class NSCollectionLayoutGroupCustomItem;

// Supplies the arrangement of a custom group. A custom group only stores it: there is no layout engine to call it.
typedef NSArray<NSCollectionLayoutGroupCustomItem *> * (^NSCollectionLayoutGroupCustomItemProvider)(
        id<NSCollectionLayoutEnvironment> layoutEnvironment);

@interface NSCollectionLayoutGroup : NSCollectionLayoutItem {
@private
    NSArray *_subitems;
    NSInteger _count;
    BOOL _vertical;
    NSCollectionLayoutSpacing *_interItemSpacing;
    NSCollectionLayoutGroupCustomItemProvider _itemProvider;
}

+ (instancetype) horizontalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                       subitem: (NSCollectionLayoutItem *) subitem
                                         count: (NSInteger) count;
+ (instancetype) horizontalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                      subitems: (NSArray<NSCollectionLayoutItem *> *) subitems;
+ (instancetype) verticalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                     subitem: (NSCollectionLayoutItem *) subitem
                                       count: (NSInteger) count;
+ (instancetype) verticalGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                                    subitems: (NSArray<NSCollectionLayoutItem *> *) subitems;

// The group has no subitems and the provider is kept, not called: there is no layout engine here.
// Raises NSInternalInconsistencyException for a nil layout size or a nil provider.
+ (instancetype) customGroupWithLayoutSize: (NSCollectionLayoutSize *) layoutSize
                              itemProvider: (NSCollectionLayoutGroupCustomItemProvider) itemProvider;

@property(copy, nullable) NSCollectionLayoutSpacing *interItemSpacing;
@property(readonly) NSArray<NSCollectionLayoutItem *> *subitems;
// Settable on a group (readonly on an item).
@property(copy) NSArray<NSCollectionLayoutSupplementaryItem *> *supplementaryItems;

// A description of the group for debugging its layout; do not parse it.
- (NSString *) visualDescription;

@end

// One item placed by the provider of a custom group. Immutable; two items are equal only if they are the same object.
@interface NSCollectionLayoutGroupCustomItem : NSObject <NSCopying> {
@private
    NSRect _frame;
    NSInteger _zIndex;
}

+ (instancetype) customItemWithFrame: (NSRect) frame;
// The zIndex is 0 for the first form.
+ (instancetype) customItemWithFrame: (NSRect) frame zIndex: (NSInteger) zIndex;

@property(readonly) NSRect frame;
@property(readonly) NSInteger zIndex;

- (instancetype) init NS_UNAVAILABLE;

@end

// How a section scrolls across the main axis of its layout.
typedef NS_ENUM(NSInteger, NSCollectionLayoutSectionOrthogonalScrollingBehavior) {
    NSCollectionLayoutSectionOrthogonalScrollingBehaviorNone = 0,
    NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuous,
    NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary,
    NSCollectionLayoutSectionOrthogonalScrollingBehaviorPaging,
    NSCollectionLayoutSectionOrthogonalScrollingBehaviorGroupPaging,
    NSCollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered,
};

// An item that is on screen, as a visible items invalidation handler sees it.
@protocol NSCollectionLayoutVisibleItem <NSObject>
@property(readonly) NSString *name;
@property(readonly) NSIndexPath *indexPath;
@property(readonly, nullable) NSString *representedElementKind;
@property(readonly) NSCollectionElementCategory representedElementCategory;
@property CGFloat alpha;
@property(getter=isHidden) BOOL hidden;
@property(readonly) NSRect frame;
@property(readonly) NSRect bounds;
@property NSPoint center;
@property NSInteger zIndex;
@end

// Called before each layout cycle, with the section's visible items, the scroll offset and the environment. The
// handler is stored and handed back; nothing calls it, because no layout engine exists yet.
typedef void (^NSCollectionLayoutSectionVisibleItemsInvalidationHandler)(
        NSArray<id<NSCollectionLayoutVisibleItem>> *visibleItems, NSPoint contentOffset,
        id<NSCollectionLayoutEnvironment> layoutEnvironment);

@interface NSCollectionLayoutSection : NSObject <NSCopying> {
@private
    NSCollectionLayoutGroup *_group;
    NSDirectionalEdgeInsets _contentInsets;
    CGFloat _interGroupSpacing;
    NSArray *_boundarySupplementaryItems;
    NSArray *_decorationItems;
    BOOL _supplementariesFollowContentInsets;
    NSCollectionLayoutSectionOrthogonalScrollingBehavior _orthogonalScrollingBehavior;
    NSCollectionLayoutSectionVisibleItemsInvalidationHandler _visibleItemsInvalidationHandler;
}

+ (instancetype) sectionWithGroup: (NSCollectionLayoutGroup *) group;

@property NSDirectionalEdgeInsets contentInsets;
@property CGFloat interGroupSpacing;
@property(copy) NSArray<NSCollectionLayoutBoundarySupplementaryItem *> *boundarySupplementaryItems;
@property BOOL supplementariesFollowContentInsets;
@property(copy) NSArray<NSCollectionLayoutDecorationItem *> *decorationItems;
@property NSCollectionLayoutSectionOrthogonalScrollingBehavior orthogonalScrollingBehavior;
@property(copy, nullable) NSCollectionLayoutSectionVisibleItemsInvalidationHandler visibleItemsInvalidationHandler;

@end

@protocol NSCollectionLayoutContainer <NSObject>
@property(readonly) NSSize contentSize;
@property(readonly) NSSize effectiveContentSize;
@property(readonly) NSDirectionalEdgeInsets contentInsets;
@property(readonly) NSDirectionalEdgeInsets effectiveContentInsets;
@end

@protocol NSCollectionLayoutEnvironment <NSObject>
@property(readonly) id<NSCollectionLayoutContainer> container;
@end

typedef NSCollectionLayoutSection * (^NSCollectionViewCompositionalLayoutSectionProvider)(
        NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> layoutEnvironment);

// AppKit defines the two classes below (they are not part of CollectionViewCore): they are layouts, subclasses of
// AppKit's NSCollectionViewLayout, and hold the sections built from the classes above.
@interface NSCollectionViewCompositionalLayoutConfiguration : NSObject <NSCopying> {
@private
    NSCollectionViewScrollDirection _scrollDirection;
    CGFloat _interSectionSpacing;
    NSArray *_boundarySupplementaryItems;
}

@property NSCollectionViewScrollDirection scrollDirection;
@property CGFloat interSectionSpacing;
@property(copy) NSArray<NSCollectionLayoutBoundarySupplementaryItem *> *boundarySupplementaryItems;

@end

@interface NSCollectionViewCompositionalLayout : NSCollectionViewLayout {
@private
    NSCollectionLayoutSection *_section;
    NSCollectionViewCompositionalLayoutSectionProvider _sectionProvider;
    NSCollectionViewCompositionalLayoutConfiguration *_configuration;
}

- (instancetype) initWithSection: (NSCollectionLayoutSection *) section;
- (instancetype) initWithSection: (NSCollectionLayoutSection *) section
                   configuration: (NSCollectionViewCompositionalLayoutConfiguration *) configuration;
- (instancetype) initWithSectionProvider: (NSCollectionViewCompositionalLayoutSectionProvider) sectionProvider;
- (instancetype) initWithSectionProvider: (NSCollectionViewCompositionalLayoutSectionProvider) sectionProvider
                           configuration: (NSCollectionViewCompositionalLayoutConfiguration *) configuration;

@property(copy) NSCollectionViewCompositionalLayoutConfiguration *configuration;

@end
