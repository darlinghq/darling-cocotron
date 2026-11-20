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
#import <AppKit/NSCollectionViewItem.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSView.h>

@class NSCollectionViewLayout, NSCollectionView, NSCollectionViewLayoutAttributes, NSNib;
@protocol NSCollectionViewDelegate;
typedef NS_ENUM(NSInteger, NSCollectionViewDropOperation) {
    NSCollectionViewDropOn = 0,
    NSCollectionViewDropBefore = 1,
};

typedef NS_OPTIONS(NSUInteger, NSCollectionViewScrollPosition) {
    NSCollectionViewScrollPositionNone = 0,
    NSCollectionViewScrollPositionTop = 1 << 0,
    NSCollectionViewScrollPositionCenteredVertically = 1 << 1,
    NSCollectionViewScrollPositionBottom = 1 << 2,
    NSCollectionViewScrollPositionNearestHorizontalEdge = 1 << 9,
    NSCollectionViewScrollPositionLeft = 1 << 3,
    NSCollectionViewScrollPositionCenteredHorizontally = 1 << 4,
    NSCollectionViewScrollPositionRight = 1 << 5,
    NSCollectionViewScrollPositionLeadingEdge = 1 << 6,
    NSCollectionViewScrollPositionTrailingEdge = 1 << 7,
    NSCollectionViewScrollPositionNearestVerticalEdge = 1 << 8,
};

@protocol NSCollectionViewDataSource <NSObject>
- (NSInteger)collectionView:(NSCollectionView *)view numberOfItemsInSection:(NSInteger)section;
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)view itemForRepresentedObjectAtIndexPath:(NSIndexPath *)path;
@optional
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)view;
@end

typedef NSString *NSCollectionViewSupplementaryElementKind NS_SWIFT_BRIDGED_TYPEDEF;

@interface NSCollectionView : NSView {
    NSArray *_content;
    NSCollectionViewItem *_itemPrototype;
    BOOL _isSelectable;
    NSSize _minItemSize;
    NSSize _maxItemSize;
    NSUInteger _maxNumberOfRows;
    NSUInteger _maxNumberOfColumns;
    NSArray *_backgroundColors;
    BOOL _allowsMultipleSelection;
    NSIndexSet *_selectionIndexes;
    NSCollectionViewLayout *_collectionViewLayout;
    NSMutableDictionary *_itemClasses;
    NSSet *_selectionIndexPaths;
    id<NSCollectionViewDataSource> _dataSource;
    id<NSCollectionViewDelegate> _delegate;
    NSMutableDictionary *_loadedItems; // the visible items, by index path
    NSArray *_loadedPaths;              // unused
    // The rest fills 27 of the 116 bytes Apple's legacy (i386) layout has
    NSMutableDictionary *_reuseQueues;     // identifier -> items not shown, ready for reuse
    NSMutableDictionary *_itemNibs;        // identifier -> NSNib registered for it
    NSMutableDictionary *_itemIdentifiers; // item (unretained NSValue) -> identifier it was made for
    NSView *_backgroundView;
    NSIndexPath *_selectionAnchor; // where a keyboard range starts
    NSIndexPath *_selectionLead;   // where the arrow keys move from
    BOOL _needsPrepareLayout;
    BOOL _backgroundViewScrollsWithContent;
    BOOL _disallowsEmptySelection; // allowsEmptySelection, inverted so that it starts YES
    NS_LEGACY_IVAR_PAD(_NSCollectionViewReserved, 89)
}

- (NSArray *) content;
- (NSCollectionViewItem *) itemPrototype;

- (BOOL) isSelectable;

- (NSSize) minItemSize;
- (NSSize) maxItemSize;

- (NSUInteger) maxNumberOfRows;
- (NSUInteger) maxNumberOfColumns;

- (NSArray *) backgroundColors;
- (BOOL) allowsMultipleSelection;
- (NSIndexSet *) selectionIndexes;

- (void) setContent: (NSArray *) value;
- (void) setItemPrototype: (NSCollectionViewItem *) value;
- (void) setSelectable: (BOOL) value;

- (void) setMinItemSize: (NSSize) value;
- (void) setMaxItemSize: (NSSize) value;
- (void) setMaxNumberOfRows: (NSUInteger) value;
- (void) setMaxNumberOfColumns: (NSUInteger) value;

- (void) setBackgroundColors: (NSArray *) value;
- (void) setAllowsMultipleSelection: (BOOL) value;
- (void) setSelectionIndexes: (NSIndexSet *) value;

- (BOOL) isFirstResponder;
- (NSCollectionViewItem *) newItemForRepresentedObject: object;

@property(assign) id<NSCollectionViewDataSource> dataSource;
@property(assign) id<NSCollectionViewDelegate> delegate;
- (void)reloadData;
- (NSInteger)numberOfSections;
- (NSInteger)numberOfItemsInSection:(NSInteger)section;
- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)path;
@property(retain) NSCollectionViewLayout *collectionViewLayout;
@property(copy) NSSet<NSIndexPath *> *selectionIndexPaths;
@property(getter=isSelectable) BOOL selectable;
@property BOOL allowsMultipleSelection;
@property BOOL allowsEmptySelection;
@property(copy) NSIndexSet *selectionIndexes;

- (void) selectItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths
                  scrollPosition: (NSCollectionViewScrollPosition) scrollPosition;
- (void) deselectItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths;
- (IBAction) selectAll: (id) sender;
- (IBAction) deselectAll: (id) sender;

- (void) registerClass: (Class) itemClass forItemWithIdentifier: (NSString *) identifier;
- (void) registerNib: (NSNib *) nib forItemWithIdentifier: (NSString *) identifier;
- (NSCollectionViewItem *) makeItemWithIdentifier: (NSString *) identifier
                                     forIndexPath: (NSIndexPath *) indexPath;

- (NSArray<NSCollectionViewItem *> *) visibleItems;
- (NSSet<NSIndexPath *> *) indexPathsForVisibleItems;
- (NSIndexPath *) indexPathForItem: (NSCollectionViewItem *) item;
- (NSIndexPath *) indexPathForItemAtPoint: (NSPoint) point;
- (NSCollectionViewLayoutAttributes *) layoutAttributesForItemAtIndexPath: (NSIndexPath *) indexPath;
- (NSRect) frameForItemAtIndex: (NSUInteger) index;
- (void) scrollToItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths
                    scrollPosition: (NSCollectionViewScrollPosition) scrollPosition;

@property(retain) NSView *backgroundView;
@property BOOL backgroundViewScrollsWithContent;

@end

@interface NSIndexPath (NSCollectionViewAdditions)
+ (NSIndexPath *) indexPathForItem: (NSInteger) item inSection: (NSInteger) section;
@property(readonly) NSInteger item;
@property(readonly) NSInteger section;
@end

@protocol NSCollectionViewDelegate <NSObject>
@optional
- (NSSet<NSIndexPath *> *) collectionView: (NSCollectionView *) collectionView
           shouldChangeItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths
                        toHighlightState: (NSCollectionViewItemHighlightState) highlightState;
- (void) collectionView: (NSCollectionView *) collectionView
    didChangeItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths
              toHighlightState: (NSCollectionViewItemHighlightState) highlightState;
- (NSSet<NSIndexPath *> *) collectionView: (NSCollectionView *) collectionView
           shouldSelectItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths;
- (NSSet<NSIndexPath *> *) collectionView: (NSCollectionView *) collectionView
         shouldDeselectItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths;
- (void) collectionView: (NSCollectionView *) collectionView didSelectItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths;
- (void) collectionView: (NSCollectionView *) collectionView
    didDeselectItemsAtIndexPaths: (NSSet<NSIndexPath *> *) indexPaths;
@end
