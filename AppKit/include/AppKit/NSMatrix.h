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

#import <AppKit/NSControl.h>

typedef enum {
    NSRadioModeMatrix,
    NSHighlightModeMatrix,
    NSListModeMatrix,
    NSTrackModeMatrix
} NSMatrixMode;

@interface NSMatrix : NSControl {
    id _delegate;
    id _target;
    SEL _action;
    SEL _doubleAction;
    NSFont *_font;
    NSColor *_backgroundColor;
    NSColor *_cellBackgroundColor;

    NSMutableArray *_cells;
    NSInteger _numberOfRows;
    NSInteger _numberOfColumns;
    NSInteger _selectedIndex;
    NSInteger _keyCellIndex;
    NSSize _cellSize;
    NSSize _intercellSpacing;
    id _prototype;
    Class _cellClass;
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
- (SEL) doubleAction;

- (Class) cellClass;
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

- (NSMatrixMode) mode;
- (BOOL) allowsEmptySelection;
- (BOOL) tabKeyTraversesCells;

- (BOOL) autosizesCells;
- (NSSize) cellSize;
- (NSSize) intercellSpacing;

- (BOOL) drawsBackground;
- (NSColor *) backgroundColor;

- (BOOL) drawsCellBackground;
- (NSColor *) cellBackgroundColor;

- (BOOL) isAutoscroll;

- (NSInteger) selectedRow;
- (NSInteger) selectedColumn;
- (NSArray *) selectedCells;

- (void) setDelegate: delegate;
- (void) setDoubleAction: (SEL) action;
- (void) setCellClass: (Class) aClass;
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

- (void) setMode: (NSMatrixMode) mode;
- (void) setAllowsEmptySelection: (BOOL) flag;
- (void) setTabKeyTraversesCells: (BOOL) flag;

- (void) setAutosizesCells: (BOOL) flag;
- (void) setCellSize: (NSSize) size;
- (void) setIntercellSpacing: (NSSize) size;

- (void) setDrawsBackground: (BOOL) flag;
- (void) setBackgroundColor: (NSColor *) color;
- (void) setDrawsCellBackground: (BOOL) flag;
- (void) setCellBackgroundColor: (NSColor *) color;

- (void) setAutoscroll: (BOOL) flag;

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
