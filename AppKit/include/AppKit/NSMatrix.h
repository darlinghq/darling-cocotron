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
#import <AppKit/NSControl.h>

typedef NS_ENUM(NSUInteger, NSMatrixMode) {
    NSRadioModeMatrix,
    NSHighlightModeMatrix,
    NSListModeMatrix,
    NSTrackModeMatrix
};

// Legacy ObjC ABI (i386): instance size must stay 0xb0, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSMatrix : NSControl {
    NS_LEGACY_IVAR_PAD(_NSMatrixReserved1, 8)
    SEL _doubleAction;
    NS_LEGACY_IVAR_PAD(_NSMatrixReserved2, 4)
    id _delegate;
    NS_LEGACY_IVAR_PAD(_NSMatrixReserved3, 12)
    NSInteger _numberOfRows;
    NSInteger _numberOfColumns;
    NSSize _cellSize;
    NSSize _intercellSpacing;
    NSFont *_font;
    id _protoCell;
    Class _cellClass;
    NSColor *_backgroundColor;
    NS_LEGACY_IVAR_PAD(_NSMatrixReserved4, 4)
    NSMutableArray *_cells;
    NS_EXTRA_IVARS_BEGIN(NSMatrix)
        id _target;
        SEL _action;
        NSColor *_cellBackgroundColor;

        NSInteger _selectedIndex;
        NSInteger _keyCellIndex;
        NSMatrixMode _mode;
        BOOL _selectionByRect;
        BOOL _allowsEmptySelection;
        BOOL _tabKeyTraversesCells;
        BOOL _isAutoscroll;
        BOOL _isEnabled;
        BOOL _autosizesCells;
        BOOL _drawsBackground;
        BOOL _drawsCellBackground;
        BOOL _refusesFirstResponder;
    NS_EXTRA_IVARS_END(NSMatrix)
}

- initWithFrame: (NSRect) frame
                   mode: (NSMatrixMode) mode
              prototype: (NSCell *) prototype
           numberOfRows: (NSInteger) rows
        numberOfColumns: (NSInteger) columns;
- initWithFrame: (NSRect) frame
                   mode: (NSMatrixMode) mode
              cellClass: (Class) cls
           numberOfRows: (NSInteger) rows
        numberOfColumns: (NSInteger) columns;

- delegate;
@property(nonatomic) SEL doubleAction;

@property(nonatomic) Class cellClass;
- prototype;

- (NSArray *) cells;
- cellWithTag: (NSInteger) tag;
- cellAtRow: (NSInteger) row column: (NSInteger) column;
- (NSRect) cellFrameAtRow: (NSInteger) row column: (NSInteger) column;
- (BOOL) getRow: (NSInteger *) row
         column: (NSInteger *) column
         ofCell: (NSCell *) cell;
- (BOOL) getRow: (NSInteger *) row
          column: (NSInteger *) column
        forPoint: (NSPoint) point;

- (NSInteger) numberOfRows;
- (NSInteger) numberOfColumns;
- (void) getNumberOfRows: (NSInteger *) rows columns: (NSInteger *) columns;

- (NSString *) toolTipForCell: (NSCell *) cell;

- keyCell;

@property(nonatomic) NSMatrixMode mode;
@property(nonatomic) BOOL allowsEmptySelection;
@property(nonatomic) BOOL tabKeyTraversesCells;

@property(nonatomic) BOOL autosizesCells;
@property(nonatomic) NSSize cellSize;
@property(nonatomic) NSSize intercellSpacing;

@property(nonatomic) BOOL drawsBackground;
@property(nonatomic, retain) NSColor *backgroundColor;

@property(nonatomic) BOOL drawsCellBackground;
@property(nonatomic, retain) NSColor *cellBackgroundColor;

@property(nonatomic, getter=isAutoscroll) BOOL autoscroll;

- (NSInteger) selectedRow;
- (NSInteger) selectedColumn;
- (NSArray *) selectedCells;

- (void) setDelegate: delegate;
- (void) setPrototype: (NSCell *) cell;

- (void) renewRows: (NSInteger) rows columns: (NSInteger) columns;
- (NSCell *) makeCellAtRow: (NSInteger) row column: (NSInteger) col;
- (void) putCell: (NSCell *) cell
           atRow: (NSInteger) row
          column: (NSInteger) column;

- (void) addRow;
- (void) insertRow: (NSInteger) row;
- (void) removeRow: (NSInteger) row;
- (void) insertRow: (NSInteger) row withCells: (NSArray *) cells;

- (void) addColumn;
- (void) removeColumn: (NSInteger) col;

- (void) setToolTip: (NSString *) tip forCell: (NSCell *) cell;

- (void) setKeyCell: cell;





- (void) selectCellAtRow: (NSInteger) row column: (NSInteger) column;
- (void) selectCell: (NSCell *) cell;
- (BOOL) selectCellWithTag: (NSInteger) tag;
- (void) selectAll: sender;
- (void) setSelectionFrom: (NSInteger) from
                       to: (NSInteger) to
                   anchor: (NSInteger) anchor
                highlight: (BOOL) highlight;
- (void) deselectAllCells;
- (void) deselectSelectedCell;

- (void) sizeToCells;

- (void) setState: (NSInteger) state
            atRow: (NSInteger) row
           column: (NSInteger) column;
- (void) highlightCell: (BOOL) highlight
                 atRow: (NSInteger) row
                column: (NSInteger) column;

- (void) drawCellAtRow: (NSInteger) row column: (NSInteger) column;

- (void) scrollCellToVisibleAtRow: (NSInteger) row column: (NSInteger) column;

- (BOOL) sendAction;

@end

@protocol NSMatrixDelegate <NSControlTextEditingDelegate>

// TODO

@end
