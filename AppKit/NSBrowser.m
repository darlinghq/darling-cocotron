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
#import <AppKit/NSApplication.h>
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>

@interface NSBrowser (Private)
- (NSRect) frameOfScroller;
@end

@implementation NSBrowser

+ (Class) cellClass {
    return [NSBrowserCell class];
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        unsigned flags = [keyed decodeIntForKey: @"NSBrFlags"];
        NSString *firstTitle =
                [keyed decodeObjectForKey: @"NSFirstColumnTitle"];

        NS_EXTRA(NSBrowser, self)->_explicitTitles = [NSMutableArray new];
        if (firstTitle != nil)
            [NS_EXTRA(NSBrowser, self)->_explicitTitles addObject: firstTitle];
        _titles = [NSMutableArray new];

        NS_EXTRA(NSBrowser, self)->_matrices = [NSMutableArray new];
        NS_EXTRA(NSBrowser, self)->_scrollViews = [NSMutableArray new];

        NS_EXTRA(NSBrowser, self)->_backgroundColor = [[NSColor whiteColor] copy];

        _matrixClass = [NSMatrix class];
        NS_EXTRA(NSBrowser, self)->_cellClass = [[self class] cellClass];
        _cellPrototype = nil;

        NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns =
                [keyed decodeIntForKey: @"NSNumberOfVisibleColumns"];
        NS_EXTRA(NSBrowser, self)->_selectedColumn = -1;

        NS_EXTRA(NSBrowser, self)->_allowsMultipleSelection = (flags & 0x80000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_allowsEmptySelection = (flags & 0x00020000) ? NO : YES;
        NS_EXTRA(NSBrowser, self)->_allowsBranchSelection = (flags & 0x40000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_separatesColumns = (flags & 0x04000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_isTitled = (flags & 0x10000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_hasHorizontalScroller = (flags & 0x00010000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_horizontalScroller = nil; // not stored
        [self setHasHorizontalScroller: NS_EXTRA(NSBrowser, self)->_hasHorizontalScroller];
        NS_EXTRA(NSBrowser, self)->_acceptsArrowKeys = (flags & 0x00100000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_sendsActionOnArrowKeys = (flags & 0x00040000) ? YES : NO;

        NS_EXTRA(NSBrowser, self)->_takesTitleFromPreviousColumn = YES;

        [self tile];
    } else {
        NSInteger version = [coder versionForClassName: @"NSBrowser"];

        if (version < 60)
            [NSException raise: NSInvalidArgumentException
                        format: @"NSBrowser cannot decode class version %ld", (long) version];

        // Two objects (not mapped), then the cell prototype, the path separator, one more
        // object (not mapped), the action and double action, the matrix class, three
        // shorts (the last is the maximum number of visible columns; the others change when
        // the minimum column width is set, meaning not mapped) and the flag word: bit 29
        // reuses columns, 28 titled, 27 takes the title from the previous column, 17 does not
        // allow an empty selection, the others as in a keyed archive.
        id prototype = nil, separator = nil, unknownObject = nil;
        SEL action = NULL, doubleAction = NULL;
        Class matrixClass = Nil;
        short unknownShorts[2], maxVisibleColumns;
        int flags;

        [coder decodeObject];
        [coder decodeObject];
        [coder decodeValuesOfObjCTypes: "@@@::#sssi", &prototype, &separator, &unknownObject, &action,
                                        &doubleAction, &matrixClass, &unknownShorts[0], &unknownShorts[1],
                                        &maxVisibleColumns, &flags];
        [separator release];
        [unknownObject release];

        NS_EXTRA(NSBrowser, self)->_explicitTitles = [NSMutableArray new];
        [NS_EXTRA(NSBrowser, self)->_explicitTitles addObject: @"Browser"];
        _titles = [NSMutableArray new];
        NS_EXTRA(NSBrowser, self)->_matrices = [NSMutableArray new];
        NS_EXTRA(NSBrowser, self)->_scrollViews = [NSMutableArray new];
        NS_EXTRA(NSBrowser, self)->_backgroundColor = [[NSColor whiteColor] copy];

        _matrixClass = matrixClass != Nil ? matrixClass : [NSMatrix class];
        if ([prototype isKindOfClass: [NSCell class]]) {
            _cellPrototype = prototype;
            NS_EXTRA(NSBrowser, self)->_cellClass = [prototype class];
        } else {
            [prototype release];
            NS_EXTRA(NSBrowser, self)->_cellClass = [[self class] cellClass];
        }
        [self setAction: action];
        [self setDoubleAction: doubleAction];
        NS_EXTRA(NSBrowser, self)->_maxVisibleColumns = maxVisibleColumns;
        NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns = 1;
        NS_EXTRA(NSBrowser, self)->_selectedColumn = -1;

        NS_EXTRA(NSBrowser, self)->_allowsMultipleSelection = (flags & 0x80000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_allowsBranchSelection = (flags & 0x40000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_reusesColumns = (flags & 0x20000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_isTitled = (flags & 0x10000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_takesTitleFromPreviousColumn = (flags & 0x08000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_separatesColumns = (flags & 0x04000000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_acceptsArrowKeys = (flags & 0x00100000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_sendsActionOnArrowKeys = (flags & 0x00040000) ? YES : NO;
        NS_EXTRA(NSBrowser, self)->_allowsEmptySelection = (flags & 0x00020000) ? NO : YES;
        NS_EXTRA(NSBrowser, self)->_hasHorizontalScroller = (flags & 0x00010000) ? YES : NO;
        [self setHasHorizontalScroller: NS_EXTRA(NSBrowser, self)->_hasHorizontalScroller];

        [self tile];
    }
    return self;
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];

    NS_EXTRA(NSBrowser, self)->_explicitTitles = [NSMutableArray new];
    [NS_EXTRA(NSBrowser, self)->_explicitTitles addObject: @"Browser"];
    _titles = [NSMutableArray new];

    NS_EXTRA(NSBrowser, self)->_matrices = [NSMutableArray new];
    NS_EXTRA(NSBrowser, self)->_scrollViews = [NSMutableArray new];

    NS_EXTRA(NSBrowser, self)->_horizontalScroller = nil;
    NS_EXTRA(NSBrowser, self)->_backgroundColor = [[NSColor whiteColor] copy];
    _matrixClass = [NSMatrix class];
    NS_EXTRA(NSBrowser, self)->_cellClass = [[self class] cellClass];
    _cellPrototype = nil;

    NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns = 1;
    NS_EXTRA(NSBrowser, self)->_allowsMultipleSelection = NO;
    NS_EXTRA(NSBrowser, self)->_allowsEmptySelection = NO;
    NS_EXTRA(NSBrowser, self)->_allowsBranchSelection = NO;
    NS_EXTRA(NSBrowser, self)->_separatesColumns = NO;
    NS_EXTRA(NSBrowser, self)->_isTitled = YES;
    NS_EXTRA(NSBrowser, self)->_hasHorizontalScroller = NO;

    NS_EXTRA(NSBrowser, self)->_takesTitleFromPreviousColumn = YES;

    return self;
}

- (void) dealloc {
    [_cellPrototype release];
    [NS_EXTRA(NSBrowser, self)->_explicitTitles release];
    [_titles release];
    [NS_EXTRA(NSBrowser, self)->_matrices release];
    [NS_EXTRA(NSBrowser, self)->_scrollViews release];
    [NS_EXTRA(NSBrowser, self)->_horizontalScroller release];
    NS_EXTRA_FREE(NSBrowser, self);
    [super dealloc];
}

- (Class) cellClass {
    return NS_EXTRA(NSBrowser, self)->_cellClass;
}

- (id) cellPrototype {
    return _cellPrototype;
}

- (void) setCellPrototype: (NSCell *) cell {
    [cell retain];
    [_cellPrototype release];
    _cellPrototype = cell;
    if (cell != nil)
        NS_EXTRA(NSBrowser, self)->_cellClass = [cell class];
}

- target {
    return NS_EXTRA(NSBrowser, self)->_target;
}

- (SEL) action {
    return NS_EXTRA(NSBrowser, self)->_action;
}

- (void) setTarget: target {
    NS_EXTRA(NSBrowser, self)->_target = target;
}

- (void) setAction: (SEL) action {
    NS_EXTRA(NSBrowser, self)->_action = action;
}

- delegate {
    return _delegate;
}

- (NSColor *) backgroundColor {
    return NS_EXTRA(NSBrowser, self)->_backgroundColor;
}

- (SEL) doubleAction {
    return _doubleAction;
}

- (Class) matrixClass {
    return _matrixClass;
}

- (NSInteger) maxVisibleColumns {
    return NS_EXTRA(NSBrowser, self)->_maxVisibleColumns;
}

- (BOOL) hasHorizontalScroller {
    return NS_EXTRA(NSBrowser, self)->_hasHorizontalScroller;
}

- (BOOL) separatesColumns {
    return NS_EXTRA(NSBrowser, self)->_separatesColumns;
}

- (BOOL) isTitled {
    return NS_EXTRA(NSBrowser, self)->_isTitled;
}

- (BOOL) takesTitleFromPreviousColumn {
    return NS_EXTRA(NSBrowser, self)->_takesTitleFromPreviousColumn;
}

- (BOOL) allowsMultipleSelection {
    return NS_EXTRA(NSBrowser, self)->_allowsMultipleSelection;
}

- (BOOL) allowsBranchSelection {
    return NS_EXTRA(NSBrowser, self)->_allowsBranchSelection;
}

- (BOOL) allowsEmptySelection {
    return NS_EXTRA(NSBrowser, self)->_allowsEmptySelection;
}

- (BOOL) acceptsArrowKeys {
    return NS_EXTRA(NSBrowser, self)->_acceptsArrowKeys;
}

- (BOOL) sendsActionOnArrowKeys {
    return NS_EXTRA(NSBrowser, self)->_sendsActionOnArrowKeys;
}

- (BOOL) reusesColumns {
    return NS_EXTRA(NSBrowser, self)->_reusesColumns;
}

- (NSInteger) lastColumn {
    return [NS_EXTRA(NSBrowser, self)->_matrices count] - 1;
}

- (NSInteger) lastVisibleColumn {
    return [self firstVisibleColumn] + (NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns - 1);
}

- (NSInteger) firstVisibleColumn {
    return NS_EXTRA(NSBrowser, self)->_firstVisibleColumn;
}

- (NSMatrix *) matrixInColumn: (NSInteger) column {
    if (column < [NS_EXTRA(NSBrowser, self)->_matrices count])
        return [NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: column];

    return nil;
}

- (NSInteger) columnOfMatrix: (NSMatrix *) matrix {
    return [NS_EXTRA(NSBrowser, self)->_matrices indexOfObjectIdenticalTo: matrix];
}

- (NSString *) titleOfColumn: (NSInteger) column {
    id result;

    if (column >= [_titles count])
        result = @"";
    else {
        result = [_titles objectAtIndex: column];

        if (result == [NSNull null]) {
            if (column < [NS_EXTRA(NSBrowser, self)->_explicitTitles count])
                result = [NS_EXTRA(NSBrowser, self)->_explicitTitles objectAtIndex: column];
            else
                result = @"";
        }
    }

    return result;
}

- (NSArray *) selectedCells {
    return [[self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn] selectedCells];
}

- selectedCell {
    return [self selectedCellInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];
}

- selectedCellInColumn: (NSInteger) column {
    return [[self matrixInColumn: column] selectedCell];
}

// This needs to be computed, manipulating individual cell state bypasses
// NS_EXTRA(NSBrowser, self)->_selectedColumn We should get rid of NS_EXTRA(NSBrowser, self)->_selectedColumn eventually
- (NSInteger) selectedColumn {
    NSInteger i, count = [NS_EXTRA(NSBrowser, self)->_matrices count];

    for (i = 0; i < count; i++) {
        NSMatrix *matrix = [NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: i];

        if ([matrix selectedCell] == nil)
            break;
    }

    return i - 1;
}

- (NSInteger) selectedRowInColumn: (NSInteger) column {
    return [[self matrixInColumn: column] selectedRow];
}

- (CGFloat) seperatorWidth {
    return 2;
}

- (CGFloat) titleHeight {
    return 20;
}

- (NSRect) titleFrameOfColumn: (NSInteger) column {
    NSRect result;
    CGFloat columnGap = NS_EXTRA(NSBrowser, self)->_separatesColumns ? [self seperatorWidth] : 0;

    column -= [self firstVisibleColumn];

    result.size.width = ([self bounds].size.width -
                         (NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns - 1) * columnGap) /
                        NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns;
    result.size.height = [self titleHeight];
    result.origin.x = column * (result.size.width + columnGap);
    result.origin.y = [self bounds].size.height - result.size.height;

    return result;
}

- (NSRect) frameOfScrollerBorder {
    NSRect result = [self bounds];

    result = NSInsetRect(result, 2, 2);
    result.size.height = [NSScroller scrollerWidth];
    result = NSInsetRect(result, -2, -2);
    return result;
}

- (NSRect) frameOfScroller {
    NSRect result = [self frameOfScrollerBorder];

    return NSInsetRect(result, 2, 2);
}

- (NSRect) frameOfColumn: (NSInteger) column {
    NSRect result;
    NSRect titleFrame = [self titleFrameOfColumn: column];

    result.origin.x = titleFrame.origin.x;
    result.size.width = titleFrame.size.width;
    result.origin.y = [self bounds].origin.y;
    result.size.height = [self bounds].size.height;

    if ([self isTitled])
        result.size.height -= titleFrame.size.height + [self seperatorWidth];

    if ([self hasHorizontalScroller]) {
        result.origin.y += [self frameOfScrollerBorder].size.height;
        result.size.height -= [self frameOfScrollerBorder].size.height;
    }

    return result;
}

- (NSRect) frameOfInsideOfColumn: (NSInteger) column {
    NSScrollView *scrollView = [NS_EXTRA(NSBrowser, self)->_scrollViews objectAtIndex: 0];
    NSSize size = [scrollView contentSize];

    return NSMakeRect(0, 0, size.width, size.height);
}

- (void) setDelegate: delegate {
    // check delegate validity
    if (![delegate respondsToSelector: @selector(browser:
                                               createRowsForColumn:inMatrix:)])
        if (![delegate respondsToSelector: @selector(browser:
                                                   numberOfRowsInColumn:)] &&
            ![delegate respondsToSelector: @selector
                       (browser:willDisplayCell:atRow:column:)])
            [NSException raise: NSInternalInconsistencyException
                        format: @"-[NSBrowser setDelegate:] doesn't implement "
                                @"delegate methods"];

    _delegate = delegate;
}

- (void) setBackgroundColor: (NSColor *) color {
    color = [color retain];
    [NS_EXTRA(NSBrowser, self)->_backgroundColor release];
    NS_EXTRA(NSBrowser, self)->_backgroundColor = color;
}

- (void) setDoubleAction: (SEL) action {
    _doubleAction = action;
}

- (void) setMatrixClass: (Class) class {
    _matrixClass = class;
}

- (void) setCellClass: (Class) class {
    NS_EXTRA(NSBrowser, self)->_cellClass = class;
    [_cellPrototype release];
    _cellPrototype = nil;
}

- (void) setMaxVisibleColumns: (NSInteger) count {
    NS_EXTRA(NSBrowser, self)->_maxVisibleColumns = count;
    NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns = count;
    [self tile];
    [self setNeedsDisplay: YES];
}

- (void) setHasHorizontalScroller: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_hasHorizontalScroller = flag;
    if (flag) {
        if (NS_EXTRA(NSBrowser, self)->_horizontalScroller == nil) {
            NS_EXTRA(NSBrowser, self)->_horizontalScroller =
                    [[NSScroller alloc] initWithFrame: [self frameOfScroller]];
            [NS_EXTRA(NSBrowser, self)->_horizontalScroller setTarget: self];
            [NS_EXTRA(NSBrowser, self)->_horizontalScroller setAction: @selector(scrollViaScroller:)];
        }
    } else {
        [NS_EXTRA(NSBrowser, self)->_horizontalScroller release];
        NS_EXTRA(NSBrowser, self)->_horizontalScroller = nil;
    }
}

- (void) setSeparatesColumns: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_separatesColumns = flag;
    [self tile];
    [self setNeedsDisplay: YES];
}

- (void) setTitled: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_isTitled = flag;
    [self tile];
    [self setNeedsDisplay: YES];
}

- (void) setTakesTitleFromPreviousColumn: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_takesTitleFromPreviousColumn = flag;
}

- (void) setAllowsMultipleSelection: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_allowsMultipleSelection = flag;
}

- (void) setAllowsBranchSelection: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_allowsBranchSelection = flag;
}

- (void) setAllowsEmptySelection: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_allowsEmptySelection = flag;
}

- (void) setAcceptsArrowKeys: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_acceptsArrowKeys = flag;
}

- (void) setSendsActionOnArrowKeys: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_sendsActionOnArrowKeys = flag;
}

- (void) setReusesColumns: (BOOL) flag {
    NS_EXTRA(NSBrowser, self)->_reusesColumns = flag ? YES : NO;
}

- (void) setTitle: (NSString *) title ofColumn: (NSInteger) column {
    while ([NS_EXTRA(NSBrowser, self)->_explicitTitles count] <= column)
        [NS_EXTRA(NSBrowser, self)->_explicitTitles addObject: @""];

    [NS_EXTRA(NSBrowser, self)->_explicitTitles replaceObjectAtIndex: column withObject: title];
    [self setNeedsDisplay: YES];
}

- (void) _unloadAfterColumn: (NSInteger) column {
    while ([NS_EXTRA(NSBrowser, self)->_matrices count] > column + 1) {
        NSMatrix *matrix = [NS_EXTRA(NSBrowser, self)->_matrices lastObject];

        [matrix removeFromSuperview];
        [NS_EXTRA(NSBrowser, self)->_matrices removeLastObject];
        [_titles removeLastObject];
    }

    [self setNeedsDisplay: YES];
    [self updateScroller];
}

- (void) _reloadSelectionInColumn: (NSInteger) column {
    NSMatrix *matrix = [self matrixInColumn: column];
    NSArray *selectedCells = [matrix selectedCells];

    [_cell autorelease];
    _cell = [[matrix selectedCell] retain];
    NS_EXTRA(NSBrowser, self)->_selectedColumn = column;

    // if multiple cells are selected, the display of that branch is invalid and
    // must be unloaded.
    if ([selectedCells count] > 1)
        [self _unloadAfterColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];
    else if (_cell != nil && ![_cell isLeaf]) {
        [self reloadColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn + 1];
        [self _unloadAfterColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn + 1];

        if (NS_EXTRA(NSBrowser, self)->_selectedColumn == [self lastVisibleColumn])
            [self scrollColumnsRightBy: 1];
    } else if (_cell != nil) // valid cell, no following branch
        [self _unloadAfterColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];

    [self scrollColumnToVisible: NS_EXTRA(NSBrowser, self)->_selectedColumn];
}

- (void) selectRow: (NSInteger) row inColumn: (NSInteger) column {
    NS_EXTRA(NSBrowser, self)->_selectedColumn = column;

    if (column < [NS_EXTRA(NSBrowser, self)->_matrices count]) {
        NSMatrix *matrix = [self matrixInColumn: column];

#if 0
    if([self allowsMultipleSelection]){
     NSBrowserCell *theLuckyCell = [matrix cellAtRow:row column:0];

     // branch selection logic. "whether the user can 
     // select branch items when multiple selection is enabled"
     if ([self selectedCells] > 0 && theLuckyCell != [self selectedCell])
      if (![theLuckyCell isLeaf])
       if (![self allowsBranchSelection])
        return;
    }
#endif

        [matrix selectCellAtRow: row column: 0];
        [matrix scrollRectToVisible: [matrix cellFrameAtRow: row column: 0]];

        [self _reloadSelectionInColumn: column];
    }
}

- (void) setPath: (NSString *) path {
    NSUnimplementedMethod();
}

- (BOOL) sendAction {
    return [self sendAction: [self action] to: [self target]];
}

- (void) doClick: sender {
    [self _reloadSelectionInColumn: [self columnOfMatrix: sender]];

    if ([[[self window] currentEvent] type] != NSKeyDown ||
        NS_EXTRA(NSBrowser, self)->_sendsActionOnArrowKeys == YES)
        [self sendAction];
}

- (void) doDoubleClick: sender {
    [self sendAction: [self doubleAction] to: [self target]];
}

- (void) unloadLastColumn {
    NSMatrix *matrix = [NS_EXTRA(NSBrowser, self)->_matrices lastObject];

    [(NSClipView *) [matrix superview] setDocumentView: nil];
    [NS_EXTRA(NSBrowser, self)->_matrices removeLastObject];
    [_titles removeLastObject];
    [self setNeedsDisplay: YES];
    [self updateScroller];
}

- (void) loadColumnZero {
    while ([NS_EXTRA(NSBrowser, self)->_matrices count] > 1)
        [self unloadLastColumn];

    [self reloadColumn: 0];
}

- (void) viewWillDraw {
    // This should be a flag really

    if ([NS_EXTRA(NSBrowser, self)->_matrices count] == 0 ||
        [[NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: 0] numberOfRows] == 0) {
        [self loadColumnZero];
    }

    [super viewWillDraw];
}

- (NSMatrix *) createMatrixInColumn: (NSInteger) column {
    while ([NS_EXTRA(NSBrowser, self)->_matrices count] <= column) {
        NSRect frame = [self frameOfInsideOfColumn: column];
        NSMatrix *matrix =
                [[[_matrixClass alloc] initWithFrame: frame] autorelease];

        [matrix setTarget: self];
        [matrix setAction: @selector(doClick:)];
        [matrix setDoubleAction: @selector(doDoubleClick:)];

        if (_cellPrototype != nil)
            [matrix setPrototype: _cellPrototype];
        else
            [matrix setCellClass: [self cellClass]];
        [matrix setCellSize: NSMakeSize(frame.size.width, 16)];
        [matrix setAutoresizingMask: NSViewWidthSizable];
        [matrix setAutosizesCells: YES];
        [matrix setAllowsEmptySelection: [self allowsEmptySelection]];

        if ([self allowsMultipleSelection])
            [matrix setMode: NSListModeMatrix];
        else
            [matrix setMode: NSRadioModeMatrix];

#if 0
    if(column>=[self firstVisibleColumn] && column<=[self lastVisibleColumn]){
     NSScrollView *scrollView=[NS_EXTRA(NSBrowser, self)->_scrollViews objectAtIndex:column-[self firstVisibleColumn]];

     [scrollView setDocumentView:matrix];
    }
#endif

        [_titles addObject: [NSNull null]];
        [NS_EXTRA(NSBrowser, self)->_matrices addObject: matrix];
    }

    if (column >= [self firstVisibleColumn] &&
        column <= [self lastVisibleColumn]) {
        NSScrollView *scrollView = [NS_EXTRA(NSBrowser, self)->_scrollViews
                objectAtIndex: column - [self firstVisibleColumn]];

        [scrollView setDocumentView: [NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: column]];
        [scrollView setLineScroll: [[NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: column] cellSize]
                                           .height];
        [scrollView
                setPageScroll: [[scrollView contentView] frame].size.height];
    }

    [self updateScroller];
    return [NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: column];
}

- (NSMatrix *) _reloadColumn: (NSInteger) column
           preserveSelection: (BOOL) preserveSelection
{
    NSMatrix *matrix = [self createMatrixInColumn: column];
    NSInteger selectedRow = [matrix selectedRow],
              selectedColumn = [matrix selectedColumn];
    id title = [NSNull null];

    [matrix renewRows: 0 columns: 1];

    if ([_delegate respondsToSelector: @selector(browser:
                                               createRowsForColumn:inMatrix:)])
        [_delegate browser: self createRowsForColumn: column inMatrix: matrix];
    else {
        NSInteger nrows = [_delegate browser: self
                        numberOfRowsInColumn: column];
        NSInteger i;

        [matrix renewRows: nrows columns: 1];

        for (i = 0; i < nrows; i++) {
            [_delegate browser: self
                    willDisplayCell: [matrix cellAtRow: i column: 0]
                              atRow: i
                             column: column];
        }
    }

    [matrix sizeToFit];

    if (preserveSelection)
        [matrix selectCellAtRow: selectedRow column: selectedColumn];
    else
        [self _unloadAfterColumn: column];

    [matrix setNeedsDisplay: YES];

    if ([_delegate respondsToSelector: @selector(browser:titleOfColumn:)])
        title = [_delegate browser: self titleOfColumn: column];
    else if (NS_EXTRA(NSBrowser, self)->_takesTitleFromPreviousColumn) {
        if (column > 0) {
            title = [[[self matrixInColumn: column - 1] selectedCell]
                    stringValue];
        }
    }

    [_titles replaceObjectAtIndex: column withObject: title];

    return matrix;
}

- (void) reloadColumn: (NSInteger) column {
    [self _reloadColumn: column preserveSelection: NO];
}

- (void) addColumn {
    NSUnimplementedMethod();
}

- (void) setLastColumn: (NSInteger) column {
    [self _reloadColumn: column preserveSelection: YES];

    while ([NS_EXTRA(NSBrowser, self)->_matrices count] > column + 1)
        [NS_EXTRA(NSBrowser, self)->_matrices removeLastObject];

    [self tile];
}

- (void) validateVisibleColumns {
    NSInteger i;

    if ([_delegate respondsToSelector: @selector(browser:isColumnValid:)]) {
        for (i = [self firstVisibleColumn]; i <= [self lastVisibleColumn];
             i++) {
            NSMatrix *matrix;

            if (![_delegate browser: self isColumnValid: i])
                [self _reloadColumn: i preserveSelection: YES];

            matrix = [self matrixInColumn: i];
            if ([matrix selectedRow] < 0) {
                [self _unloadAfterColumn: i];
                break;
            }
        }
    }
}

- (void) scrollColumnsLeftBy: (NSInteger) offset {
    NSInteger i, scrollViewIndex = 0;

    if (NS_EXTRA(NSBrowser, self)->_firstVisibleColumn - offset < 0)
        offset = NS_EXTRA(NSBrowser, self)->_firstVisibleColumn;

    if (offset < 1)
        return;

    NS_EXTRA(NSBrowser, self)->_firstVisibleColumn -= offset;

    for (i = NS_EXTRA(NSBrowser, self)->_firstVisibleColumn;
         i <= [self lastVisibleColumn] && i < [NS_EXTRA(NSBrowser, self)->_matrices count]; i++) {
        NSView *matrix =
                (i < [NS_EXTRA(NSBrowser, self)->_matrices count]) ? [NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: i] : nil;

        [[NS_EXTRA(NSBrowser, self)->_scrollViews objectAtIndex: scrollViewIndex++]
                setDocumentView: matrix];
    }

    [self updateScroller];
}

- (void) scrollColumnsRightBy: (NSInteger) offset {
    NSInteger i, scrollViewIndex = 0;

    if ([self lastVisibleColumn] + offset >= [NS_EXTRA(NSBrowser, self)->_matrices count])
        offset = [NS_EXTRA(NSBrowser, self)->_matrices count] - [self lastVisibleColumn] - 1;

    if (offset < 1)
        return;

    NS_EXTRA(NSBrowser, self)->_firstVisibleColumn += offset;

    // NB here we swap in reverse, since a view doesn't display properly if it
    // is the docView of two scrollViews at once. bug or feature?
    scrollViewIndex = [NS_EXTRA(NSBrowser, self)->_scrollViews count] - 1;
    for (i = [self lastVisibleColumn]; i >= NS_EXTRA(NSBrowser, self)->_firstVisibleColumn; --i) {
        [[NS_EXTRA(NSBrowser, self)->_scrollViews objectAtIndex: scrollViewIndex--]
                setDocumentView: [NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: i]];
    }

    [self updateScroller];
}

- (void) scrollColumnToVisible: (NSInteger) column {
    if (column >= [self firstVisibleColumn] &&
        column <= [self lastVisibleColumn])
        return; // already visible

    if (column < NS_EXTRA(NSBrowser, self)->_firstVisibleColumn)
        [self scrollColumnsLeftBy: NS_EXTRA(NSBrowser, self)->_firstVisibleColumn - column];
    else
        [self scrollColumnsRightBy: column - [self lastVisibleColumn]];
}

- (void) scrollViaScroller: (NSScroller *) sender {
    switch ([sender hitPart]) {
    case NSScrollerDecrementLine:
    case NSScrollerDecrementPage:
        [self scrollColumnsLeftBy: 1];
        break;

    case NSScrollerIncrementLine:
    case NSScrollerIncrementPage:
        [self scrollColumnsRightBy: 1];
        break;

    case NSScrollerKnob:
    case NSScrollerKnobSlot:
        [self scrollColumnToVisible: [sender floatValue] * [NS_EXTRA(NSBrowser, self)->_matrices count]];
        break;

    default:
        break;
    }

    [self setNeedsDisplay: YES];
}

- (void) updateScroller {
    if (NS_EXTRA(NSBrowser, self)->_firstVisibleColumn + NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns > [NS_EXTRA(NSBrowser, self)->_matrices count])
        [self scrollColumnsLeftBy: 1];

    if ([NS_EXTRA(NSBrowser, self)->_matrices count] == 0 ||
        [NS_EXTRA(NSBrowser, self)->_matrices count] <= NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns) {
        [NS_EXTRA(NSBrowser, self)->_horizontalScroller setFloatValue: 0.0 knobProportion: 1.0];
        [NS_EXTRA(NSBrowser, self)->_horizontalScroller setEnabled: NO];
    } else {
        CGFloat val = (CGFloat) NS_EXTRA(NSBrowser, self)->_firstVisibleColumn /
                      (CGFloat)([NS_EXTRA(NSBrowser, self)->_matrices count] - NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns);
        CGFloat knobP =
                (CGFloat) NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns / (CGFloat)[NS_EXTRA(NSBrowser, self)->_matrices count];

        [NS_EXTRA(NSBrowser, self)->_horizontalScroller setFloatValue: val knobProportion: knobP];
        [NS_EXTRA(NSBrowser, self)->_horizontalScroller setEnabled: YES];
    }

    [NS_EXTRA(NSBrowser, self)->_horizontalScroller setNeedsDisplay: YES];
}

- (void) drawTitleOfColumn: (NSInteger) column inRect: (NSRect) rect {
    NSString *title = [self titleOfColumn: column];
    NSSize titleSize = [title sizeWithAttributes: nil];
    NSRect titleFrame = NSInsetRect(rect, 2, 0);

    titleFrame.size.height = titleSize.height;
    titleFrame.origin.y += floor((rect.size.height - titleSize.height) / 2);

    [[self titleOfColumn: column] _clipAndDrawInRect: titleFrame
                                      withAttributes: nil];
}

- (NSScrollView *) createScrollViewAtIndex: (NSInteger) index {
    while ([NS_EXTRA(NSBrowser, self)->_scrollViews count] <= index) {
        NSInteger column = NS_EXTRA(NSBrowser, self)->_firstVisibleColumn + [NS_EXTRA(NSBrowser, self)->_scrollViews count];
        NSRect frame = [self frameOfColumn: column];
        NSScrollView *view =
                [[[NSScrollView alloc] initWithFrame: frame] autorelease];

        [view setBorderType: NSBezelBorder];
        [view setHasVerticalScroller: YES];
        [view setHasHorizontalScroller: NO];
        [view setAutoresizesSubviews: YES];

        [NS_EXTRA(NSBrowser, self)->_scrollViews addObject: view];
        [self addSubview: view];
    }

    return [NS_EXTRA(NSBrowser, self)->_scrollViews objectAtIndex: index];
}

- (void) tile {
    NSInteger i;

    for (i = 0; i < NS_EXTRA(NSBrowser, self)->_numberOfVisibleColumns; i++) {
        NSInteger column = NS_EXTRA(NSBrowser, self)->_firstVisibleColumn + i;
        NSRect frame = [self frameOfColumn: column];
        NSView *scrollView = [self createScrollViewAtIndex: i];

        [scrollView setFrame: frame];
    }

    while ([NS_EXTRA(NSBrowser, self)->_scrollViews count] > NS_EXTRA(NSBrowser, self)->_firstVisibleColumn + i) {
        [[NS_EXTRA(NSBrowser, self)->_scrollViews lastObject] removeFromSuperview];
        [NS_EXTRA(NSBrowser, self)->_scrollViews removeLastObject];
    }

    [NS_EXTRA(NSBrowser, self)->_horizontalScroller setFrame: [self frameOfScroller]];
}

- (void) setEnabled: (BOOL) enabled {
    NSInteger count = [NS_EXTRA(NSBrowser, self)->_matrices count];

    while (--count >= 0) {
        [[NS_EXTRA(NSBrowser, self)->_matrices objectAtIndex: count] setEnabled: enabled];
    }
    [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) rect {
    NSInteger i;

    [NS_EXTRA(NSBrowser, self)->_backgroundColor setFill];
    NSRectFill(rect);

    if ([self isTitled]) {
        for (i = [self firstVisibleColumn]; i <= [self lastVisibleColumn];
             i++) {
            NSRect titleRect = [self titleFrameOfColumn: i];

            [[self graphicsStyle] drawBrowserTitleBackgroundInRect: titleRect];

            titleRect = NSInsetRect(titleRect, 2, 2);

            [self drawTitleOfColumn: i inRect: titleRect];
        }
    }

    if ([self hasHorizontalScroller])
        [[self graphicsStyle] drawBrowserHorizontalScrollerWellInRect:
                                      [self frameOfScrollerBorder]
                                                             clipRect: rect];
}

- (void) resizeSubviewsWithOldSize: (NSSize) oldSize {
    [self tile];
}

- (void) mouseDown: (NSEvent *) event {
    // do nothing, but override NSControl's implementation
}

- (void) keyDown: (NSEvent *) event {
    if (NS_EXTRA(NSBrowser, self)->_acceptsArrowKeys == YES)
        [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

//  up arrow
- (void) moveBackward: sender {
    NSInteger selectedRow = [self selectedRowInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];

    if (selectedRow > 0) {
        if (!([[[self window] currentEvent] modifierFlags] & NSShiftKeyMask))
            [[self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn] deselectAllCells];

        [self selectRow: selectedRow - 1 inColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];
        [self doClick: [self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn]];
    }
}

- (void) moveForward: sender {
    NSInteger selectedRow = [self selectedRowInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];
    if (selectedRow <
        [[self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn] numberOfRows] - 1) {
        if (!([[[self window] currentEvent] modifierFlags] & NSShiftKeyMask))
            [[self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn] deselectAllCells];

        [self selectRow: selectedRow + 1 inColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];
        [self doClick: [self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn]];
    }
}

- (void) moveUp: sender {
    [self moveBackward: sender];
}

- (void) moveDown: sender {
    [self moveForward: sender];
}

- (void) moveLeft: sender {
    if (NS_EXTRA(NSBrowser, self)->_selectedColumn > 0) {
        if (![[self selectedCell] isLeaf])
            [self _unloadAfterColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn];
        if ([self allowsEmptySelection] == YES)
            [[self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn] deselectAllCells];

        //        [self selectRow:0 inColumn:NS_EXTRA(NSBrowser, self)->_selectedColumn - 1];
        NS_EXTRA(NSBrowser, self)->_selectedColumn--;
        // NSLog(@"selectedColumn %d count %d", _selectedColumn, [_matrices
        // count]);
        [self doClick: [self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn]];
    }
}

- (void) moveRight: sender {
    if (![[self selectedCell] isLeaf]) {
        [self selectRow: 0
                inColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn +
                          1]; // nb this changes NS_EXTRA(NSBrowser, self)->_selectedColumn
        [self doClick: [self matrixInColumn: NS_EXTRA(NSBrowser, self)->_selectedColumn]];
    }
}

@end
