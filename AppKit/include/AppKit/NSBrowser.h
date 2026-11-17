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

@class NSMatrix, NSScroller;

typedef NS_ENUM(NSUInteger, NSBrowserColumnResizingType) {
    NSBrowserNoColumnResizing = 0,
    NSBrowserAutoColumnResizing = 1,
    NSBrowserUserColumnResizing = 2,
};

typedef NS_ENUM(NSUInteger, NSBrowserDropOperation) {
    NSBrowserDropOn,
    NSBrowserDropAbove,
};

// Legacy ObjC ABI (i386): instance size must stay 0xa0, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSBrowser : NSControl {
    NS_LEGACY_IVAR_PAD(_NSBrowserReserved1, 8)
    id _delegate;
    SEL _doubleAction;
    Class _matrixClass;
    id _cellPrototype;
    NS_LEGACY_IVAR_PAD(_NSBrowserReserved2, 16)
    NSMutableArray *_titles;
    NS_LEGACY_IVAR_PAD(_NSBrowserReserved3, 20)
    NS_EXTRA_IVARS_BEGIN(NSBrowser)
        id _target;
        SEL _action;

        NSMutableArray *_explicitTitles;
        NSMutableArray *_matrices;
        NSMutableArray *_scrollViews;
        NSScroller *_horizontalScroller;
        NSColor *_backgroundColor;

        Class _cellClass;
        int _numberOfVisibleColumns;
        int _minColumnWidth;
        int _firstVisibleColumn;
        int _maxVisibleColumns;
        int _selectedColumn;
        BOOL _reusesColumns;
        BOOL _hasHorizontalScroller;
        BOOL _separatesColumns;
        BOOL _isTitled;
        BOOL _allowsMultipleSelection;
        BOOL _allowsBranchSelection;
        BOOL _allowsEmptySelection;
        BOOL _takesTitleFromPreviousColumn;
        BOOL _acceptsArrowKeys;
        BOOL _sendsActionOnArrowKeys;
    NS_EXTRA_IVARS_END(NSBrowser)
}

- delegate;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic) SEL doubleAction;
@property(nonatomic) Class matrixClass;
@property(nonatomic) NSInteger maxVisibleColumns;
@property(nonatomic) BOOL hasHorizontalScroller;
@property(nonatomic) BOOL separatesColumns;
@property(nonatomic, getter=isTitled) BOOL titled;
@property(nonatomic) BOOL takesTitleFromPreviousColumn;
@property(nonatomic) BOOL allowsMultipleSelection;
@property(nonatomic) BOOL allowsBranchSelection;
@property(nonatomic) BOOL allowsEmptySelection;
@property(nonatomic) BOOL acceptsArrowKeys;
@property(nonatomic) BOOL sendsActionOnArrowKeys;
@property(nonatomic) BOOL reusesColumns;

@property(nonatomic) NSInteger lastColumn;
- (NSInteger) lastVisibleColumn;
- (NSInteger) firstVisibleColumn;

- (NSMatrix *) matrixInColumn: (NSInteger) column;
- (NSInteger) columnOfMatrix: (NSMatrix *) matrix;
- (NSString *) titleOfColumn: (NSInteger) column;

- (NSArray *) selectedCells;
- selectedCell;
- selectedCellInColumn: (NSInteger) column;
- (NSInteger) selectedColumn;
- (NSInteger) selectedRowInColumn: (NSInteger) column;

- (CGFloat) titleHeight;
- (NSRect) titleFrameOfColumn: (NSInteger) column;
- (NSRect) frameOfColumn: (NSInteger) column;
- (NSRect) frameOfInsideOfColumn: (NSInteger) column;

- (void) setDelegate: delegate;
- (void) setCellClass: (Class) aClass;
@property(nonatomic, retain) id cellPrototype;

- (void) setTitle: (NSString *) title ofColumn: (NSInteger) column;

- (void) selectRow: (NSInteger) row inColumn: (NSInteger) column;
- (void) setPath: (NSString *) path;

- (BOOL) sendAction;
- (void) doClick: sender;
- (void) doDoubleClick: sender;

- (void) loadColumnZero;
- (void) reloadColumn: (NSInteger) column;
- (void) addColumn;
- (void) validateVisibleColumns;

- (void) scrollColumnsLeftBy: (NSInteger) delta;
- (void) scrollColumnsRightBy: (NSInteger) delta;
- (void) scrollColumnToVisible: (NSInteger) column;
- (void) scrollViaScroller: (NSScroller *) sender;
- (void) updateScroller;

- (void) drawTitleOfColumn: (NSInteger) column inRect: (NSRect) rect;

- (void) tile;

@end

@protocol NSBrowserDelegate <NSObject>
- (BOOL) browser: (NSBrowser *) browser isColumnValid: (NSInteger) column;

- (NSInteger) browser: (NSBrowser *) browser
        numberOfRowsInColumn: (NSInteger) column;
- (void) browser: (NSBrowser *) browser
        createRowsForColumn: (NSInteger) column
                   inMatrix: (NSMatrix *) matrix;

- (BOOL) browser: (NSBrowser *) browser
        selectRow: (NSInteger) row
         inColumn: (NSInteger) column;
- (BOOL) browser: (NSBrowser *) browser
        selectCellWithString: (NSString *) title
                    inColumn: (NSInteger) column;

- (NSString *) browser: (NSBrowser *) browser titleOfColumn: (NSInteger) column;

- (void) browserWillScroll: (NSBrowser *) browser;
- (void) browserDidScroll: (NSBrowser *) browser;

- (void) browser: (NSBrowser *) browser
        willDisplayCell: cell
                  atRow: (NSInteger) row
                 column: (NSInteger) column;

@end
