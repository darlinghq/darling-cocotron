/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/AppKitExport.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSControl.h>

@protocol NSPasteboardWriting;

@class NSTableColumn, NSButtonCell;

NS_ASSUME_NONNULL_BEGIN

APPKIT_EXPORT NSString *const NSOutlineViewItemWillExpandNotification;
APPKIT_EXPORT NSString *const NSOutlineViewItemDidExpandNotification;
APPKIT_EXPORT NSString *const NSOutlineViewItemWillCollapseNotification;
APPKIT_EXPORT NSString *const NSOutlineViewItemDidCollapseNotification;

APPKIT_EXPORT NSString *const NSOutlineViewColumnDidMoveNotification;
APPKIT_EXPORT NSString *const NSOutlineViewColumnDidResizeNotification;

APPKIT_EXPORT NSString *const NSOutlineViewSelectionDidChangeNotification;
APPKIT_EXPORT NSString *const NSOutlineViewSelectionIsChangingNotification;

APPKIT_EXPORT NSString *const NSOutlineViewDisclosureButtonKey;
APPKIT_EXPORT NSString *const NSOutlineViewShowHideButtonKey;

// Legacy ObjC ABI (i386): instance size must stay 0x14c, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSOutlineView : NSTableView {
    NS_LEGACY_IVAR_PAD(_NSOutlineViewReserved1, 24)
    NSTableColumn *_outlineTableColumn;
    NS_LEGACY_IVAR_PAD(_NSOutlineViewReserved2, 8)
    NSButtonCell *_markerCell;
    NS_LEGACY_IVAR_PAD(_NSOutlineViewReserved3, 60)
    NS_EXTRA_IVARS_BEGIN(NSOutlineView)
        NSMapTable *_rowToItem;
        NSMapTable *_itemToRow;
        NSMapTable *_itemToParent;
        NSMapTable *_itemToLevel;
        NSMapTable *_itemToExpansionState;
        NSMapTable *_itemToNumberOfChildren;

        NSUInteger _numberOfCachedRows;
        BOOL _rowCacheValid;
        BOOL _isBuildingCache;
        NSSize _markerSize;
        id _clickedItem;
        CGFloat _widestColumnWidth;

        CGFloat _indentationPerLevel;
        BOOL _indentationMarkerFollowsCell;
        BOOL _autoresizesOutlineColumn;
        BOOL _autosaveExpandedItems;
        CGFloat _editingCellPadding;
        id _dropItem;                       // the drop being validated, as setDropItem:dropChildIndex: may change it
        NSInteger _dropChildIndex;
    NS_EXTRA_IVARS_END(NSOutlineView)
}

@property(nullable, nonatomic, retain) NSTableColumn *outlineTableColumn;

- (nullable id) itemAtRow: (NSInteger) row;
- (NSInteger) rowForItem: (nullable id) item;
- (nullable id) parentForItem: (nullable id) item;

- (BOOL) isExpandable: (nullable id) item;
- (NSInteger) levelForItem: (nullable id) item;
- (NSInteger) levelForRow: (NSInteger) row;
- (BOOL) isItemExpanded: (nullable id) item;
@property(nonatomic) CGFloat indentationPerLevel;

@property(nonatomic) BOOL autoresizesOutlineColumn;
@property(nonatomic) BOOL indentationMarkerFollowsCell;
@property(nonatomic) BOOL autosaveExpandedItems;



- (void) expandItem: (nullable id) item expandChildren: (BOOL) expandChildren;
- (void) expandItem: (nullable id) item;
- (void) collapseItem: (nullable id) item collapseChildren: (BOOL) collapseChildren;
- (void) collapseItem: (nullable id) item;
- (void) reloadItem: (nullable id) item reloadChildren: (BOOL) reloadChildren;
- (void) reloadItem: (nullable id) item;

- (void) insertItemsAtIndexes: (NSIndexSet *) indexes inParent: (nullable id) parent withAnimation: (NSTableViewAnimationOptions) animationOptions;
- (void) removeItemsAtIndexes: (NSIndexSet *) indexes inParent: (nullable id) parent withAnimation: (NSTableViewAnimationOptions) animationOptions;
- (void) moveItemAtIndex: (NSInteger) fromIndex inParent: (nullable id) oldParent toIndex: (NSInteger) toIndex inParent: (nullable id) newParent;

- (void) setDropItem: (nullable id) item dropChildIndex: (NSInteger) index;
- (BOOL) shouldCollapseAutoExpandedItemsForDeposited: (BOOL) collapse;

- (NSRect) frameOfOutlineCellAtRow: (NSInteger) row;

@end

// The child index of a drop on an item rather than between its children
enum { NSOutlineViewDropOnItemIndex = -1 };

// Every method of both protocols is optional, as on macOS
@protocol NSOutlineViewDataSource <NSObject>
@optional
- (NSInteger) outlineView: (NSOutlineView *) outlineView
        numberOfChildrenOfItem: (nullable id) item;
- (BOOL) outlineView: (NSOutlineView *) outlineView isItemExpandable: (id) item;
- (id) outlineView: (NSOutlineView *) outlineView
         child: (NSInteger) index
        ofItem: (nullable id) item;
- (nullable id) outlineView: (NSOutlineView *) outlineView
        objectValueForTableColumn: (nullable NSTableColumn *) tableColumn
                           byItem: (nullable id) item;
- (void) outlineView: (NSOutlineView *) outlineView
        setObjectValue: (nullable id) object
        forTableColumn: (nullable NSTableColumn *) tableColumn
                byItem: (nullable id) item;
- (void) outlineView: (NSOutlineView *) outlineView sortDescriptorsDidChange: (NSArray<NSSortDescriptor *> *) oldDescriptors;
- (nullable id<NSPasteboardWriting>) outlineView: (NSOutlineView *) outlineView pasteboardWriterForItem: (id) item;
- (void) outlineView: (NSOutlineView *) outlineView
     draggingSession: (NSDraggingSession *) session
    willBeginAtPoint: (NSPoint) screenPoint
            forItems: (NSArray *) draggedItems;
- (void) outlineView: (NSOutlineView *) outlineView
     draggingSession: (NSDraggingSession *) session
        endedAtPoint: (NSPoint) screenPoint
           operation: (NSDragOperation) operation;
- (BOOL) outlineView: (NSOutlineView *) outlineView writeItems: (NSArray *) items toPasteboard: (NSPasteboard *) pasteboard;
- (NSDragOperation) outlineView: (NSOutlineView *) outlineView
                   validateDrop: (id<NSDraggingInfo>) info
                   proposedItem: (nullable id) item
             proposedChildIndex: (NSInteger) index;
- (BOOL) outlineView: (NSOutlineView *) outlineView
          acceptDrop: (id<NSDraggingInfo>) info
                item: (nullable id) item
          childIndex: (NSInteger) index;
@end

@protocol NSOutlineViewDelegate <NSControlTextEditingDelegate>
@optional
- (BOOL) outlineView: (NSOutlineView *) outlineView shouldExpandItem: (id) item;
- (BOOL) outlineView: (NSOutlineView *) outlineView shouldCollapseItem: (id) item;
- (BOOL) selectionShouldChangeInOutlineView: (NSOutlineView *) outlineView;
- (BOOL) outlineView: (NSOutlineView *) outlineView
        shouldEditTableColumn: (nullable NSTableColumn *) tableColumn
                         item: (id) item;
- (BOOL) outlineView: (NSOutlineView *) outlineView shouldSelectItem: (id) item;
- (BOOL) outlineView: (NSOutlineView *) outlineView
        shouldSelectTableColumn: (nullable NSTableColumn *) tableColumn;
- (void) outlineView: (NSOutlineView *) outlineView
        willDisplayCell: (id) cell
         forTableColumn: (nullable NSTableColumn *) tableColumn
                   item: (id) item;
- (void) outlineView: (NSOutlineView *) outlineView
        willDisplayOutlineCell: (id) cell
                forTableColumn: (nullable NSTableColumn *) tableColumn
                          item: (id) item;
- (nullable NSTableRowView *) outlineView: (NSOutlineView *) outlineView rowViewForItem: (id) item;
- (void) outlineView: (NSOutlineView *) outlineView didAddRowView: (NSTableRowView *) rowView forRow: (NSInteger) row;
- (void) outlineView: (NSOutlineView *) outlineView didRemoveRowView: (NSTableRowView *) rowView forRow: (NSInteger) row;
- (nullable NSView *) outlineView: (NSOutlineView *) outlineView
               viewForTableColumn: (nullable NSTableColumn *) tableColumn
                             item: (id) item;
- (BOOL) outlineView: (NSOutlineView *) outlineView isGroupItem: (id) item;
- (BOOL) outlineView: (NSOutlineView *) outlineView shouldShowOutlineCellForItem: (id) item;
@end

@interface NSObject (NSOutlineView_notifications)
- (void) outlineViewItemWillExpand: (NSNotification *) note;
- (void) outlineViewItemDidExpand: (NSNotification *) note;
- (void) outlineViewItemWillCollapse: (NSNotification *) note;
- (void) outlineViewItemDidCollapse: (NSNotification *) note;
- (void) outlineViewColumnDidMove: (NSNotification *) note;
- (void) outlineViewColumnDidResize: (NSNotification *) note;
- (void) outlineViewSelectionIsChanging: (NSNotification *) note;
- (void) outlineViewSelectionDidChange: (NSNotification *) note;
@end

@interface NSObject (NSOutlineView_cellSizing)
- (CGFloat) outlineView: (null_unspecified NSOutlineView *) outlineView
            widthOfCell: (null_unspecified id) cell
         forTableColumn: (null_unspecified NSTableColumn *) tableColumn
                 byItem: (null_unspecified id) item;
@end

NS_ASSUME_NONNULL_END
