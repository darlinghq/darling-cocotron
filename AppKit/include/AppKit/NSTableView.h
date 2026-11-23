/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009 Markus Hitter <mah@jump-ing.de>

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

/*
 * Subclassing notes:
 *
 * NSTableView maintains a cache for the height of each of the rows,
 * even if this array is set to all equal values by sending -setRowHeight.
 * To make sure your subclass does not invalidate this cache you have three
 * choices:
 *
 * 1. Don't override -noteNumberOfRowsChanged or
 * -noteHeightOfRowsWithIndexesChanged: and send them to self where appropriate
 * (and let the cache do it's work).
 *
 * 2. Override -noteNumberOfRowsChanged, but send something like
 *      [super noteHeightOfRowsWithIndexesChanged:[NSIndexSet
 *          indexSetWithIndexesInRange:NSMakeRange(0, <rowCount>)]];
 *    each time the number of rows has changed. Or, send it to
 *    super before doing any size calculations.
 *
 *    If overriding -noteHeightOfRowsWithIndexesChanged:, send
 *    that to super before doing any display size calculations.
 *
 * 3. Override -noteNumberOfRowsChanged, but also override -rectOfRow:,
 *    -rectOfColumn:, -rowInRect:, -columnsInRect:, -setRowHeight:,
 *    -frameOfCellAtColumn:row: and -noteHeightOfRowsWithIndexesChanged:,
 *    i.e. replace everything using the cache.
 */

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSDragging.h>

@protocol NSPasteboardWriting;

@class NSTableHeaderView, NSTableColumn, NSNib, NSTableRowView;

@class NSSortDescriptor;

NS_ASSUME_NONNULL_BEGIN

APPKIT_EXPORT NSString *const NSTableViewSelectionIsChangingNotification;
APPKIT_EXPORT NSString *const NSTableViewSelectionDidChangeNotification;
APPKIT_EXPORT NSString *const NSTableViewColumnDidMoveNotification;
APPKIT_EXPORT NSString *const NSTableViewColumnDidResizeNotification;

APPKIT_EXPORT NSString *const NSTableViewRowViewKey;

typedef NS_OPTIONS(NSUInteger, NSTableViewGridLineStyle) {
    NSTableViewGridNone = 0,
    NSTableViewSolidVerticalGridLineMask = 1 << 0,
    NSTableViewSolidHorizontalGridLineMask = 1 << 1,
    NSTableViewDashedHorizontalGridLineMask = 1 << 3,
};

typedef NS_ENUM(NSInteger, NSTableViewSelectionHighlightStyle) {
    NSTableViewSelectionHighlightStyleNone = -1,
    NSTableViewSelectionHighlightStyleRegular = 0,
    NSTableViewSelectionHighlightStyleSourceList = 1,
};

typedef NS_ENUM(NSInteger, NSTableViewRowSizeStyle) {
    NSTableViewRowSizeStyleDefault = -1,
    NSTableViewRowSizeStyleCustom = 0,
    NSTableViewRowSizeStyleSmall = 1,
    NSTableViewRowSizeStyleMedium = 2,
    NSTableViewRowSizeStyleLarge = 3,
};

typedef NS_ENUM(NSInteger, NSTableViewStyle) {
    NSTableViewStyleAutomatic = 0,
    NSTableViewStyleFullWidth = 1,
    NSTableViewStyleInset = 2,
    NSTableViewStyleSourceList = 3,
    NSTableViewStylePlain = 4,
};

typedef NS_ENUM(NSUInteger, NSTableViewDropOperation) {
    NSTableViewDropOn,
    NSTableViewDropAbove
};

typedef NS_OPTIONS(NSUInteger, NSTableViewAnimationOptions) {
    NSTableViewAnimationEffectNone = 0x0,
    NSTableViewAnimationEffectFade = 0x1,
    NSTableViewAnimationEffectGap = 0x2,
    NSTableViewAnimationSlideUp = 0x10,
    NSTableViewAnimationSlideDown = 0x20,
    NSTableViewAnimationSlideLeft = 0x30,
    NSTableViewAnimationSlideRight = 0x40,
};

typedef NS_ENUM(NSUInteger, NSTableViewColumnAutoresizingStyle) {
    NSTableViewNoColumnAutoresizing = 0,
    NSTableViewUniformColumnAutoresizingStyle,
    NSTableViewSequentialColumnAutoresizingStyle,
    NSTableViewReverseSequentialColumnAutoresizingStyle,
    NSTableViewLastColumnOnlyAutoresizingStyle,
    NSTableViewFirstColumnOnlyAutoresizingStyle,
};

typedef NS_ENUM(NSInteger, NSTableViewDraggingDestinationFeedbackStyle) {
    NSTableViewDraggingDestinationFeedbackStyleNone = -1,
    NSTableViewDraggingDestinationFeedbackStyleRegular = 0,
    NSTableViewDraggingDestinationFeedbackStyleSourceList = 1,
    NSTableViewDraggingDestinationFeedbackStyleGap = 2,
};

typedef NS_ENUM(NSInteger, NSTableRowActionEdge) {
    NSTableRowActionEdgeLeading,
    NSTableRowActionEdgeTrailing,
};

// Legacy ObjC ABI (i386): instance size must stay 0xe4, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSTableView : NSControl <NSDraggingSource> {
    NSTableHeaderView *_headerView;
    NSView *_cornerView;
    NSMutableArray *_tableColumns;
    id _editingCell;
    id _delegate;
    id _dataSource;
    NSSize _intercellSpacing;
    CGFloat _standardRowHeight;
    NS_LEGACY_IVAR_PAD(_NSTableViewReserved1, 8)
    NSInteger _editedRow;
    NSInteger _editedColumn;
    NS_LEGACY_IVAR_PAD(_NSTableViewReserved2, 12)
    NSColor *_backgroundColor;
    NSColor *_gridColor;
    NS_LEGACY_IVAR_PAD(_NSTableViewReserved3, 12)
    SEL _doubleAction;
    NS_LEGACY_IVAR_PAD(_NSTableViewReserved4, 44)
    NS_EXTRA_IVARS_BEGIN(NSTableView)
        id _target;
        SEL _action;



        NSInteger _rowHeightsCount;
        CGFloat *_rowHeights;
        BOOL _allowsColumnReordering;
        BOOL _allowsColumnResizing;
        NSTableViewColumnAutoresizingStyle _columnAutoresizingStyle;
        BOOL _allowsMultipleSelection;
        BOOL _allowsEmptySelection;
        BOOL _allowsColumnSelection;
        BOOL _allowsTypeSelect;

        BOOL _alternatingRowBackground;
        unsigned int _gridStyleMask;
        NSTableViewSelectionHighlightStyle _selectionHighlightStyle;
        BOOL _usesAutomaticRowHeights;
        BOOL _floatsGroupRows;
        NSTableViewRowSizeStyle _rowSizeStyle;
        CGFloat _styledRowHeight;
        NSTableViewStyle _style;

        // temp ivars
        NSMutableArray *_selectedColumns;
        NSIndexSet *_selectedRowIndexes;
        NSInteger _clickedColumn, _clickedRow;
        NSInteger _numberOfRows;
        NSInteger _updatesNestingCount;
        NSRect _editingFrame, _editingBorder;
        NSArray *_sortDescriptors;

        // Drop target proposed by the table and retargeted by the data source; -1 with
        // NSTableViewDropOn is the whole table.
        NSInteger _draggingRow;
        NSTableViewDropOperation _draggingOperation;
        BOOL _draggingTargetKnown;  // validated by the data source, not yet dropped
        BOOL _draggingTargetShown;  // drop feedback is visible
        NSDragOperation _draggingSourceMaskLocal;
        NSDragOperation _draggingSourceMaskNonLocal;
        NSIndexSet *_draggedRows;           // the rows of the dragging session the table began

        NSMutableDictionary *_registeredNibs;
        NSMutableDictionary *_cellViews;    // views in the table, keyed by cell position
        NSMutableDictionary *_reuseQueues;  // identifier -> views waiting for reuse
        NSMutableDictionary *_rowViews;     // row -> NSTableRowView in the table
        NSString *_typeSelectString;
        NSString *_toolTipSignature;
        NSTimeInterval _typeSelectTime;

        NSTableColumn *_highlightedTableColumn; // not retained
        NSMutableDictionary *_indicatorImages;
        BOOL _verticalMotionCannotBeginDrag;
        BOOL _rowActionsVisible;
        BOOL _usesStaticContents;
        NSTableViewDraggingDestinationFeedbackStyle _draggingDestinationFeedbackStyle;
        // Decoded from a nib and not yet sent -awakeFromNib.
        BOOL _awaitingAwakeFromNib;
        // A data source set while loading from a nib is checked on the next -numberOfRows.
        BOOL _dataSourceCheckPending;
        NSString *_autosaveName;
        BOOL _autosaveTableColumns;
    NS_EXTRA_IVARS_END(NSTableView)
}

- (nullable __kindof NSView *) makeViewWithIdentifier: (null_unspecified NSString *) identifier owner: (nullable id) owner;
- (void) registerNib: (nullable NSNib *) nib forIdentifier: (null_unspecified NSString *) identifier;
- (void) setIndicatorImage: (nullable NSImage *) image inTableColumn: (NSTableColumn *) tableColumn;
- (nullable NSImage *) indicatorImageInTableColumn: (NSTableColumn *) tableColumn;
- (NSInteger) rowForView: (NSView *) view;
- (NSInteger) columnForView: (NSView *) view;
- (nullable __kindof NSView *) viewAtColumn: (NSInteger) column row: (NSInteger) row makeIfNecessary: (BOOL) makeIfNecessary;
- (nullable __kindof NSTableRowView *) rowViewAtRow: (NSInteger) row makeIfNecessary: (BOOL) makeIfNecessary;
- (void) enumerateAvailableRowViewsUsingBlock: (void (NS_NOESCAPE ^)(__kindof NSTableRowView *rowView, NSInteger row)) handler;

@property(nonatomic) SEL doubleAction;

@property(null_unspecified, nonatomic, assign) id dataSource;
@property(null_unspecified, nonatomic, assign) id delegate;

@property(null_unspecified, nonatomic, retain) NSView *headerView;
@property(nullable, nonatomic, retain) NSView *cornerView;

@property(nonatomic) CGFloat rowHeight;
@property(nonatomic) NSSize intercellSpacing;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *gridColor;
@property(null_unspecified, nonatomic, copy) NSString *autosaveName;

@property(nonatomic) BOOL drawsGrid;
@property(nonatomic) BOOL allowsColumnReordering;
@property(nonatomic) BOOL allowsColumnResizing;
@property(nonatomic) BOOL autoresizesAllColumnsToFit;
@property(nonatomic) NSTableViewColumnAutoresizingStyle columnAutoresizingStyle;
@property(nullable, nonatomic, assign) NSTableColumn *highlightedTableColumn;
@property(nonatomic) BOOL verticalMotionCanBeginDrag;
@property(nonatomic) BOOL rowActionsVisible;
@property(nonatomic) BOOL usesStaticContents;
@property(nonatomic) NSTableViewDraggingDestinationFeedbackStyle draggingDestinationFeedbackStyle;
@property(readonly) NSTableViewStyle effectiveStyle;
@property(nonatomic) BOOL allowsMultipleSelection;
@property(nonatomic) BOOL allowsEmptySelection;
@property(nonatomic) BOOL allowsColumnSelection;
@property(nonatomic) BOOL allowsTypeSelect;
@property(nonatomic) BOOL autosaveTableColumns;

@property(nonatomic) BOOL usesAlternatingRowBackgroundColors;
@property(nonatomic) NSTableViewGridLineStyle gridStyleMask;
@property(nonatomic) NSTableViewSelectionHighlightStyle selectionHighlightStyle;
@property(nonatomic) BOOL usesAutomaticRowHeights;
// Floating applies to view-based tables only; Cocotron's tables are cell-based.
@property(nonatomic) BOOL floatsGroupRows;
@property(nonatomic) NSTableViewRowSizeStyle rowSizeStyle;
@property(nonatomic, readonly) NSTableViewRowSizeStyle effectiveRowSizeStyle;
@property(nonatomic) NSTableViewStyle style;

@property(nonatomic, readonly) NSInteger numberOfRows;
@property(nonatomic, readonly) NSUInteger numberOfColumns;
@property(nonatomic, readonly) NSArray<NSTableColumn *> *tableColumns;
- (NSInteger) columnWithIdentifier: (null_unspecified id) identifier;
- (nullable NSTableColumn *) tableColumnWithIdentifier: (null_unspecified id) identifier;

- (NSRect) rectOfRow: (NSInteger) row;
- (NSRect) rectOfColumn: (NSInteger) column;
- (NSRange) rowsInRect: (NSRect) rect;
- (NSRange) columnsInRect: (NSRect) rect;
- (NSInteger) rowAtPoint: (NSPoint) point;
- (NSInteger) columnAtPoint: (NSPoint) point;
- (NSRect) frameOfCellAtColumn: (NSInteger) column row: (NSInteger) row;





- (void) setDraggingSourceOperationMask: (NSDragOperation) mask
                               forLocal: (BOOL) isLocal;
- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) isLocal;
// In tableView:validateDrop:proposedRow:proposedDropOperation:, makes the drop go to another row or operation
- (void) setDropRow: (NSInteger) row dropOperation: (NSTableViewDropOperation) dropOperation;


- (void) addTableColumn: (NSTableColumn *) column;
- (void) removeTableColumn: (NSTableColumn *) column;
- (void) moveColumn: (NSInteger) columnIndex toColumn: (NSInteger) newIndex;

@property(nonatomic, readonly) NSInteger editedRow;
@property(nonatomic, readonly) NSInteger editedColumn;
- (void) editColumn: (NSInteger) column
                row: (NSInteger) row
          withEvent: (nullable NSEvent *) event
             select: (BOOL) select;

@property(nonatomic, readonly) NSInteger clickedRow;
@property(nonatomic, readonly) NSInteger clickedColumn;
@property(nonatomic, readonly) NSInteger selectedRow;
@property(nonatomic, readonly) NSInteger selectedColumn;
@property(nonatomic, readonly) NSInteger numberOfSelectedRows;
@property(nonatomic, readonly) NSInteger numberOfSelectedColumns;
- (BOOL) isColumnSelected: (NSInteger) row;
- (BOOL) isRowSelected: (NSInteger) row;
- (NSEnumerator *) selectedRowEnumerator;
- (NSEnumerator *) selectedColumnEnumerator;
@property(nonatomic, readonly) NSIndexSet *selectedColumnIndexes;

- (void) selectRow: (NSInteger) row byExtendingSelection: (BOOL) extend;
- (void) selectColumn: (NSInteger) column byExtendingSelection: (BOOL) extend;
- (void) deselectRow: (NSInteger) row;
- (void) deselectColumn: (NSInteger) column;
- (void) selectColumnIndexes: (NSIndexSet *) indexes
        byExtendingSelection: (BOOL) extend;
- (NSIndexSet *) columnIndexesInRect: (NSRect) rect;

- (void) selectAll: (nullable id) sender;
- (void) deselectAll: (nullable id) sender;

- (void) scrollRowToVisible: (NSInteger) index;
- (void) scrollColumnToVisible: (NSInteger) index;

- (void) beginUpdates;
- (void) endUpdates;
- (void) insertRowsAtIndexes: (NSIndexSet *) indexes withAnimation: (NSTableViewAnimationOptions) animationOptions;
- (void) removeRowsAtIndexes: (NSIndexSet *) indexes withAnimation: (NSTableViewAnimationOptions) animationOptions;
- (void) moveRowAtIndex: (NSInteger) oldIndex toIndex: (NSInteger) newIndex;

- (void) noteNumberOfRowsChanged;
- (void) noteHeightOfRowsWithIndexesChanged: (NSIndexSet *) indexSet;
- (void) reloadData;
- (void) reloadDataForRowIndexes: (NSIndexSet *) rowIndexes
                   columnIndexes: (NSIndexSet *) columnIndexes;
- (void) tile;

- (void) sizeLastColumnToFit;

- (void) highlightSelectionInClipRect: (NSRect) rect;

- (void) drawRow: (NSInteger) row clipRect: (NSRect) rect;
- (void) drawBackgroundInClipRect: (NSRect) rect;
- (void) drawGridInClipRect: (NSRect) rect;
- (nullable NSCell *) preparedCellAtColumn: (NSInteger) columnNumber
                              row: (NSInteger) row;

@property(nonatomic, readonly) NSIndexSet *selectedRowIndexes;
- (void) selectRowIndexes: (NSIndexSet *) indexes
        byExtendingSelection: (BOOL) extend;

@property(nonatomic, copy) NSArray<NSSortDescriptor *> *sortDescriptors;
@end

@protocol NSTableViewDataSource <NSObject>
@optional
- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView;
- (nullable id) tableView: (NSTableView *) tableView
        objectValueForTableColumn: (nullable NSTableColumn *) tableColumn
                              row: (NSInteger) row;
- (void) tableView: (NSTableView *) tableView
        setObjectValue: (nullable id) object
        forTableColumn: (nullable NSTableColumn *) tableColumn
                   row: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView
        writeRowsWithIndexes: (NSIndexSet *) indexes
                toPasteboard: (NSPasteboard *) pasteboard;
- (NSDragOperation) tableView: (NSTableView *) tableView
                 validateDrop: (id <NSDraggingInfo>) draggingInfo
                  proposedRow: (NSInteger) proposedRow
        proposedDropOperation: (NSTableViewDropOperation) dropOperation;
- (BOOL) tableView: (NSTableView *) tableView
           acceptDrop: (id <NSDraggingInfo>) draggingInfo
                  row: (NSInteger) row
        dropOperation: (NSTableViewDropOperation) dropOperation;
- (void) tableView: (NSTableView *) tableView
        sortDescriptorsDidChange: (NSArray<NSSortDescriptor *> *) oldDescriptors;
- (nullable id<NSPasteboardWriting>) tableView: (NSTableView *) tableView pasteboardWriterForRow: (NSInteger) row;
- (void) tableView: (NSTableView *) tableView
         draggingSession: (NSDraggingSession *) session
        willBeginAtPoint: (NSPoint) screenPoint
           forRowIndexes: (NSIndexSet *) rowIndexes;
- (void) tableView: (NSTableView *) tableView
        draggingSession: (NSDraggingSession *) session
           endedAtPoint: (NSPoint) screenPoint
              operation: (NSDragOperation) operation;
@end

@protocol NSTableViewDelegate <NSObject>
@optional
- (BOOL) tableView: (NSTableView *) tableView
        shouldEditTableColumn: (nullable NSTableColumn *) tableColumn
                          row: (NSInteger) row;
- (BOOL) selectionShouldChangeInTableView: (NSTableView *) tableView;
- (CGFloat) tableView: (NSTableView *) tableView heightOfRow: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView shouldSelectRow: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView isGroupRow: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView
        shouldSelectTableColumn: (nullable NSTableColumn *) tableColumn;
- (void) tableView: (NSTableView *) tableView
        mouseDownInHeaderOfTableColumn: (NSTableColumn *) tableColumn;
- (void) tableView: (NSTableView *) tableView
        willDisplayCell: (id) cell
         forTableColumn: (nullable NSTableColumn *) tableColumn
                    row: (NSInteger) row;
- (nullable NSView *) tableView: (NSTableView *) tableView
    viewForTableColumn: (nullable NSTableColumn *) tableColumn
                   row: (NSInteger) row;
- (nullable NSTableRowView *) tableView: (NSTableView *) tableView rowViewForRow: (NSInteger) row;
- (void) tableView: (NSTableView *) tableView didAddRowView: (NSTableRowView *) rowView forRow: (NSInteger) row;
- (void) tableView: (NSTableView *) tableView didRemoveRowView: (NSTableRowView *) rowView forRow: (NSInteger) row;
- (NSIndexSet *) tableView: (NSTableView *) tableView
        selectionIndexesForProposedSelection: (NSIndexSet *) proposedSelectionIndexes;
- (void) tableView: (NSTableView *) tableView didClickTableColumn: (NSTableColumn *) tableColumn;
- (BOOL) tableView: (NSTableView *) tableView shouldReorderColumn: (NSInteger) columnIndex toColumn: (NSInteger) newColumnIndex;
- (CGFloat) tableView: (NSTableView *) tableView sizeToFitWidthOfColumn: (NSInteger) column;
- (NSString *) tableView: (NSTableView *) tableView
          toolTipForCell: (NSCell *) cell
                    rect: (NSRectPointer) rect
             tableColumn: (nullable NSTableColumn *) tableColumn
                     row: (NSInteger) row
           mouseLocation: (NSPoint) mouseLocation;
- (BOOL) tableView: (NSTableView *) tableView shouldShowCellExpansionForTableColumn: (nullable NSTableColumn *) tableColumn row: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView
        shouldTrackCell: (NSCell *) cell
         forTableColumn: (nullable NSTableColumn *) tableColumn
                    row: (NSInteger) row;
- (nullable NSString *) tableView: (NSTableView *) tableView typeSelectStringForTableColumn: (nullable NSTableColumn *) tableColumn row: (NSInteger) row;
- (NSInteger) tableView: (NSTableView *) tableView
        nextTypeSelectMatchFromRow: (NSInteger) startRow
                             toRow: (NSInteger) endRow
                         forString: (NSString *) searchString;
- (BOOL) tableView: (NSTableView *) tableView
        shouldTypeSelectForEvent: (NSEvent *) event
         withCurrentSearchString: (nullable NSString *) searchString;
@end

@interface NSObject (NSTableView_notifications)
- (void) tableViewSelectionIsChanging: (NSNotification *) note;
- (void) tableViewSelectionDidChange: (NSNotification *) note;
- (void) tableViewColumnDidMove: (NSNotification *) note;
- (void) tableViewColumnDidResize: (NSNotification *) note;
@end

NS_ASSUME_NONNULL_END
