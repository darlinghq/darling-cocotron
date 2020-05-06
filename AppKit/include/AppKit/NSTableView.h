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

#import <AppKit/NSControl.h>
#import <AppKit/NSDragging.h>

@class NSTableHeaderView, NSTableColumn;

APPKIT_EXPORT NSString *const NSTableViewSelectionIsChangingNotification;
APPKIT_EXPORT NSString *const NSTableViewSelectionDidChangeNotification;
APPKIT_EXPORT NSString *const NSTableViewColumnDidMoveNotification;
APPKIT_EXPORT NSString *const NSTableViewColumnDidResizeNotification;

APPKIT_EXPORT NSString *const NSTableViewRowViewKey;

enum {
    NSTableViewGridNone,
    NSTableViewSolidVerticalGridLineMask,
    NSTableViewSolidHorizontalGridLineMask
};

enum {
    NSTableViewSelectionHighlightStyleNone = -1,
    NSTableViewSelectionHighlightStyleRegular = 0,
    NSTableViewSelectionHighlightStyleSourceList = 1,
};
typedef NSInteger NSTableViewSelectionHighlightStyle;

typedef enum {
    NSTableViewDropOn,
    NSTableViewDropAbove
} NSTableViewDropOperation;

@interface NSTableView : NSControl {
    id _target;
    SEL _action;
    SEL _doubleAction;

    id _delegate;
    id _dataSource;

    NSTableHeaderView *_headerView;
    NSView *_cornerView;
    NSMutableArray *_tableColumns;

    NSInteger _rowHeightsCount;
    CGFloat *_rowHeights;
    CGFloat _standardRowHeight;
    NSColor *_backgroundColor;
    NSColor *_gridColor;
    BOOL _allowsColumnReordering;
    BOOL _allowsColumnResizing;
    BOOL _autoresizesAllColumnsToFit;
    BOOL _allowsMultipleSelection;
    BOOL _allowsEmptySelection;
    BOOL _allowsColumnSelection;
    NSSize _intercellSpacing;

    BOOL _alternatingRowBackground;
    unsigned int _gridStyleMask;
    NSTableViewSelectionHighlightStyle _selectionHighlightStyle;

    // temp ivars
    NSMutableArray *_selectedColumns;
    NSIndexSet *_selectedRowIndexes;
    NSInteger _clickedColumn, _clickedRow;
    NSInteger _editedColumn, _editedRow;
    NSInteger _numberOfRows;
    id _editingCell;
    NSRect _editingFrame, _editingBorder;
    NSArray *_sortDescriptors;

    NSInteger _draggingRow;
}

- (SEL) doubleAction;

- (id) dataSource;
- (id) delegate;

- (NSView *) headerView;
- (NSView *) cornerView;

- (CGFloat) rowHeight;
- (NSSize) intercellSpacing;
- (NSColor *) backgroundColor;
- (NSColor *) gridColor;
- (NSString *) autosaveName;

- (BOOL) drawsGrid;
- (BOOL) allowsColumnReordering;
- (BOOL) allowsColumnResizing;
- (BOOL) autoresizesAllColumnsToFit;
- (BOOL) allowsMultipleSelection;
- (BOOL) allowsEmptySelection;
- (BOOL) allowsColumnSelection;
- (BOOL) autosaveTableColumns;

- (BOOL) usesAlternatingRowBackgroundColors;
- (unsigned int) gridStyleMask;
- (NSTableViewSelectionHighlightStyle) selectionHighlightStyle;

- (NSInteger) numberOfRows;
- (NSUInteger) numberOfColumns;
- (NSArray *) tableColumns;
- (NSInteger) columnWithIdentifier: (id) identifier;
- (NSTableColumn *) tableColumnWithIdentifier: identifier;

- (NSRect) rectOfRow: (NSInteger) row;
- (NSRect) rectOfColumn: (NSInteger) column;
- (NSRange) rowsInRect: (NSRect) rect;
- (NSRange) columnsInRect: (NSRect) rect;
- (NSInteger) rowAtPoint: (NSPoint) point;
- (NSInteger) columnAtPoint: (NSPoint) point;
- (NSRect) frameOfCellAtColumn: (NSInteger) column row: (NSInteger) row;

- (void) setDoubleAction: (SEL) action;

- (void) setDataSource: dataSource;
- (void) setDelegate: delegate;

- (void) setHeaderView: (NSTableHeaderView *) headerView;
- (void) setCornerView: (NSView *) view;

- (void) setRowHeight: (CGFloat) height;
- (void) setIntercellSpacing: (NSSize) size;
- (void) setBackgroundColor: (NSColor *) color;
- (void) setGridColor: (NSColor *) color;
- (void) setAutosaveName: (NSString *) name;

- (void) setDrawsGrid: (BOOL) flag;
- (void) setAllowsColumnReordering: (BOOL) flag;
- (void) setAllowsColumnResizing: (BOOL) flag;
- (void) setAutoresizesAllColumnsToFit: (BOOL) flag;
- (void) setAllowsMultipleSelection: (BOOL) flag;
- (void) setAllowsEmptySelection: (BOOL) flag;
- (void) setAllowsColumnSelection: (BOOL) flag;
- (void) setAutosaveTableColumns: (BOOL) flag;

- (void) setUsesAlternatingRowBackgroundColors: (BOOL) flag;
- (void) setGridStyleMask: (unsigned int) gridStyle;
- (void) setSelectionHighlightStyle: (NSTableViewSelectionHighlightStyle) value;

- (void) addTableColumn: (NSTableColumn *) column;
- (void) removeTableColumn: (NSTableColumn *) column;
- (void) moveColumn: (NSInteger) columnIndex toColumn: (NSInteger) newIndex;

- (NSInteger) editedRow;
- (NSInteger) editedColumn;
- (void) editColumn: (NSInteger) column
                row: (NSInteger) row
          withEvent: (NSEvent *) event
             select: (BOOL) select;

- (NSInteger) clickedRow;
- (NSInteger) clickedColumn;
- (NSInteger) selectedRow;
- (NSInteger) selectedColumn;
- (NSInteger) numberOfSelectedRows;
- (NSInteger) numberOfSelectedColumns;
- (BOOL) isColumnSelected: (NSInteger) row;
- (BOOL) isRowSelected: (NSInteger) row;
- (NSEnumerator *) selectedRowEnumerator;
- (NSEnumerator *) selectedColumnEnumerator;
- (NSIndexSet *) selectedColumnIndexes;

- (void) selectRow: (NSInteger) row byExtendingSelection: (BOOL) extend;
- (void) selectColumn: (NSInteger) column byExtendingSelection: (BOOL) extend;
- (void) deselectRow: (NSInteger) row;
- (void) deselectColumn: (NSInteger) column;

- (void) selectAll: sender;
- (void) deselectAll: sender;

- (void) scrollRowToVisible: (NSInteger) index;
- (void) scrollColumnToVisible: (NSInteger) index;

- (void) noteNumberOfRowsChanged;
- (void) noteHeightOfRowsWithIndexesChanged: (NSIndexSet *) indexSet;
- (void) reloadData;
- (void) tile;

- (void) sizeLastColumnToFit;

- (void) highlightSelectionInClipRect: (NSRect) rect;

- (void) drawRow: (NSInteger) row clipRect: (NSRect) rect;
- (void) drawBackgroundInClipRect: (NSRect) rect;
- (void) drawGridInClipRect: (NSRect) rect;
- (NSCell *) preparedCellAtColumn: (NSInteger) columnNumber
                              row: (NSInteger) row;

- (NSIndexSet *) selectedRowIndexes;
- (void) selectRowIndexes: (NSIndexSet *) indexes
     byExtendingSelection: (BOOL) extend;

- (NSArray *) sortDescriptors;
- (void) setSortDescriptors: (NSArray *) value;
@end

@interface NSObject (NSTableView_dataSource)
- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView;
- (id) tableView: (NSTableView *) tableView
    objectValueForTableColumn: (NSTableColumn *) tableColumn
                          row: (NSInteger) row;
- (void) tableView: (NSTableView *) tableView
    setObjectValue: object
    forTableColumn: (NSTableColumn *) tableColumn
               row: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView
    writeRowsWithIndexes: (NSIndexSet *) indexes
            toPasteboard: (NSPasteboard *) pasteboard;
- (NSDragOperation) tableView: (NSTableView *) tableView
                 validateDrop: (id<NSDraggingInfo>) draggingInfo
                  proposedRow: (NSInteger) proposedRow
        proposedDropOperation: (NSTableViewDropOperation) dropOperation;
- (BOOL) tableView: (NSTableView *) tableView
        acceptDrop: (id<NSDraggingInfo>) draggingInfo
               row: (NSInteger) row
     dropOperation: (NSTableViewDropOperation) dropOperation;
@end

@interface NSObject (NSTableView_delegate)
- (BOOL) tableView: (NSTableView *) tableView
    shouldEditTableColumn: (NSTableColumn *) tableColumn
                      row: (NSInteger) row;
- (BOOL) selectionShouldChangeInTableView: (NSTableView *) tableView;
- (CGFloat) tableView: (NSTableView *) tableView heightOfRow: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView shouldSelectRow: (NSInteger) row;
- (BOOL) tableView: (NSTableView *) tableView
    shouldSelectTableColumn: (NSTableColumn *) tableColumn;
- (void) tableView: (NSTableView *) tableView
    mouseDownInHeaderOfTableColumn: (NSTableColumn *) tableColumn;
- (void) tableView: (NSTableView *) tableView
    willDisplayCell: cell
     forTableColumn: (NSTableColumn *) tableColumn
                row: (NSInteger) row;
@end

@interface NSObject (NSTableView_notifications)
- (void) tableViewSelectionIsChanging: (NSNotification *) note;
- (void) tableViewSelectionDidChange: (NSNotification *) note;
- (void) tableViewColumnDidMove: (NSNotification *) note;
- (void) tableViewColumnDidResize: (NSNotification *) note;
@end
