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

#import "NSKeyValueBinding/NSKVOBinder.h"
#import "NSKeyValueBinding/NSMultipleValueBinder.h"
#import <AppKit/AppKit.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSTableCornerView.h>
#import <AppKit/NSTableCellView.h>
#import <AppKit/NSImageView.h>
#import <Foundation/NSKeyedArchiver.h>

NSString *const NSTableViewSelectionIsChangingNotification =
        @"NSTableViewSelectionIsChangingNotification";
NSString *const NSTableViewSelectionDidChangeNotification =
        @"NSTableViewSelectionDidChangeNotification";
NSString *const NSTableViewColumnDidMoveNotification =
        @"NSTableViewColumnDidMoveNotification";
NSString *const NSTableViewColumnDidResizeNotification =
        @"NSTableViewColumnDidResizeNotification";

NSString *const NSTableViewRowViewKey = @"NSTableViewRowViewKey";

const CGFloat NSTableViewDefaultRowHeight = 16.0f;

@interface NSTableView (NSTableView_notifications)

- (BOOL) delegateShouldSelectTableColumn: (NSTableColumn *) tableColumn;
- (BOOL) delegateShouldSelectRow: (NSInteger) row;
- (BOOL) delegateShouldEditTableColumn: (NSTableColumn *) tableColumn
                                   row: (NSInteger) row;
- (BOOL) delegateSelectionShouldChange;
- (void) noteSelectionIsChanging;
- (void) noteSelectionDidChange;
- (void) noteColumnDidResizeWithOldWidth: (CGFloat) oldWidth;
- (BOOL) dataSourceCanSetObjectValue;
- (void) dataSourceSetObjectValue: object
                   forTableColumn: (NSTableColumn *) tableColumn
                              row: (NSInteger) row;

@end

@implementation NSTableView

- (id) _replacementKeyPathForBinding: (id) binding {
    if ([binding isEqual: @"selectionIndexes"])
        return @"selectedRowIndexes";
    return [super _replacementKeyPathForBinding: binding];
}

+ (Class) _binderClassForBinding: (id) binding {
    if ([binding isEqual: @"content"])
        return [_NSTableViewContentBinder class];
    return [_NSKVOBinder class];
}

- (void) _boundValuesChanged {
    [_tableColumns makeObjectsPerformSelector: @selector(_boundValuesChanged)];
    [self reloadData];
}

- (void) _establishBindingsWithDestinationIfUnbound: (id) destination {
    // this method is called after table column bindings have been established.
    // if the table view doesn't have any bindings at this point, it needs to
    // have its content, sortDescriptors and selectedIndexes bindings
    // established
    if ([[self _allUsedBinders] count] == 0) {
        [self bind: @"content"
                   toObject: destination
                withKeyPath: @"arrangedObjects"
                    options: nil];
        [self bind: @"sortDescriptors"
                   toObject: destination
                withKeyPath: @"sortDescriptors"
                    options: nil];
        [self bind: @"selectionIndexes"
                   toObject: destination
                withKeyPath: @"selectionIndexes"
                    options: nil];
    }
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        unsigned flags = [keyed decodeIntForKey: @"NSTvFlags"];

        _headerView = [[keyed decodeObjectForKey: @"NSHeaderView"] retain];
        [_headerView setTableView: self];
        _cornerView = [[keyed decodeObjectForKey: @"NSCornerView"] retain];
        _tableColumns = [[NSMutableArray alloc]
                initWithArray: [keyed decodeObjectForKey: @"NSTableColumns"]];
        [_tableColumns makeObjectsPerformSelector: @selector(setTableView:)
                                       withObject: self];
        _backgroundColor =
                [[keyed decodeObjectForKey: @"NSBackgroundColor"] retain];
        _gridColor = [[keyed decodeObjectForKey: @"NSGridColor"] retain];
        NS_EXTRA(NSTableView, self)->_rowHeightsCount = 0;
        NS_EXTRA(NSTableView, self)->_rowHeights = NULL;
        _standardRowHeight = [keyed decodeFloatForKey: @"NSRowHeight"];
        NS_EXTRA(NSTableView, self)->_allowsColumnReordering = (flags & 0x80000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsColumnResizing = (flags & 0x40000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_autoresizesAllColumnsToFit = (flags & 0x00008000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsMultipleSelection = (flags & 0x08000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsEmptySelection = (flags & 0x10000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsColumnSelection = (flags & 0x04000000) ? YES : NO;
        _intercellSpacing = NSMakeSize(3.0, 2.0);
        NS_EXTRA(NSTableView, self)->_selectedRowIndexes = [[NSIndexSet alloc] init];
        NS_EXTRA(NSTableView, self)->_selectedColumns = [[NSMutableArray alloc] init];
        NS_EXTRA(NSTableView, self)->_registeredNibs = [[NSMutableDictionary alloc] init];
        NS_EXTRA(NSTableView, self)->_activeRowViews = [[NSMutableArray alloc] init];
        _editedColumn = -1;
        _editedRow = -1;
        NS_EXTRA(NSTableView, self)->_numberOfRows = -1;
        NS_EXTRA(NSTableView, self)->_draggingRow = -1;
        NS_EXTRA(NSTableView, self)->_draggingSourceMaskLocal = NSDragOperationEvery;
        NS_EXTRA(NSTableView, self)->_draggingSourceMaskNonLocal = NSDragOperationNone;
        // Nibs archive "every operation" as -1; NSDragOperationEvery is 32 bits wide here.
        if ([keyed containsValueForKey: @"NSDraggingSourceMaskForLocal"])
            NS_EXTRA(NSTableView, self)->_draggingSourceMaskLocal = (NSDragOperation) [keyed
                    decodeIntegerForKey: @"NSDraggingSourceMaskForLocal"] &
                    NSDragOperationEvery;
        if ([keyed containsValueForKey: @"NSDraggingSourceMaskForNonLocal"])
            NS_EXTRA(NSTableView, self)->_draggingSourceMaskNonLocal = (NSDragOperation) [keyed
                    decodeIntegerForKey: @"NSDraggingSourceMaskForNonLocal"] &
                    NSDragOperationEvery;

        // row background and grid attributes for OS X >= 10.3
        NS_EXTRA(NSTableView, self)->_alternatingRowBackground = (flags & 0x00800000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_floatsGroupRows = YES;
        if ([keyed containsValueForKey: @"NSGridStyleMask"])
            NS_EXTRA(NSTableView, self)->_gridStyleMask = [keyed decodeIntForKey: @"NSGridStyleMask"];
        else
            NS_EXTRA(NSTableView, self)->_gridStyleMask = NSTableViewGridNone;
    } else {
        NS_EXTRA(NSTableView, self)->_selectedRowIndexes = [[NSIndexSet alloc] init];
        NS_EXTRA(NSTableView, self)->_selectedColumns = [[NSMutableArray alloc] init];
        _editedColumn = -1;
        _editedRow = -1;
        NS_EXTRA(NSTableView, self)->_numberOfRows = -1;
        NS_EXTRA(NSTableView, self)->_draggingRow = -1;
        _intercellSpacing = NSMakeSize(3.0, 2.0);
        _standardRowHeight = 16.0;
        NS_EXTRA(NSTableView, self)->_allowsColumnReordering = YES;
        NS_EXTRA(NSTableView, self)->_allowsColumnResizing = YES;
        NS_EXTRA(NSTableView, self)->_autoresizesAllColumnsToFit = YES;

        id headerView = nil, cornerView = nil, cols = nil;
        id bgColor = nil, gridColor = nil;
        float spacingW = 3.0, spacingH = 2.0, rowH = 16.0;
        SEL action = NULL, doubleAction = NULL;
        int flags = 0;

        // Layout as recorded from Mac archives (one for every class version): header
        // view, corner view, table columns, cell spacing, background and grid colours, row
        // height, action, double action and a flag word, then the delegate, the data
        // source and the target. The flag word holds column reordering in bit 31, column
        // resizing in 30, empty selection in 28, multiple selection in 27, column
        // selection in 26, alternating row backgrounds in 23 and uniform column
        // autoresizing in 15. The grid style and autosave name are not archived.
        [coder decodeValuesOfObjCTypes: "@@@ff@@f::i", &headerView, &cornerView, &cols, &spacingW, &spacingH, &bgColor,
                                        &gridColor, &rowH, &action, &doubleAction, &flags];
        id aDelegate = [coder decodeObject];
        _dataSource = [coder decodeObject];
        NS_EXTRA(NSTableView, self)->_target = [coder decodeObject];
        [self setDelegate: aDelegate];

        _headerView = headerView;
        [_headerView setTableView: self];
        _cornerView = cornerView;
        if ([cols isKindOfClass: [NSArray class]]) {
            _tableColumns = [cols mutableCopy];
        } else {
            _tableColumns = [[NSMutableArray alloc] init];
        }
        [cols release];
        [_tableColumns makeObjectsPerformSelector: @selector(setTableView:) withObject: self];

        _intercellSpacing = NSMakeSize(spacingW, spacingH);
        _backgroundColor = bgColor;
        _gridColor = gridColor;
        _standardRowHeight = rowH > 0 ? rowH : 16.0;
        NS_EXTRA(NSTableView, self)->_action = action;
        _doubleAction = doubleAction;

        NS_EXTRA(NSTableView, self)->_allowsColumnReordering = (flags & 0x80000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsColumnResizing = (flags & 0x40000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_autoresizesAllColumnsToFit = (flags & 0x00008000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsMultipleSelection = (flags & 0x08000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsEmptySelection = (flags & 0x10000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsColumnSelection = (flags & 0x04000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_alternatingRowBackground = (flags & 0x00800000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_gridStyleMask = NSTableViewGridNone;
    }
    return self;
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    NS_EXTRA(NSTableView, self)->_rowHeightsCount = 0;
    NS_EXTRA(NSTableView, self)->_rowHeights = NULL;
    _standardRowHeight = NSTableViewDefaultRowHeight;
    _intercellSpacing = NSMakeSize(3.0, 2.0);
    NS_EXTRA(NSTableView, self)->_selectedRowIndexes = [[NSIndexSet alloc] init];
    NS_EXTRA(NSTableView, self)->_selectedColumns = [[NSMutableArray alloc] init];
    NS_EXTRA(NSTableView, self)->_registeredNibs = [[NSMutableDictionary alloc] init];
    NS_EXTRA(NSTableView, self)->_activeRowViews = [[NSMutableArray alloc] init];
    _editedColumn = -1;
    _editedRow = -1;
    NS_EXTRA(NSTableView, self)->_numberOfRows = -1;
    NS_EXTRA(NSTableView, self)->_draggingRow = -1;
    NS_EXTRA(NSTableView, self)->_draggingSourceMaskLocal = NSDragOperationEvery;
    NS_EXTRA(NSTableView, self)->_draggingSourceMaskNonLocal = NSDragOperationNone;

    NS_EXTRA(NSTableView, self)->_allowsColumnReordering = YES;
    NS_EXTRA(NSTableView, self)->_allowsColumnResizing = YES;
    NS_EXTRA(NSTableView, self)->_autoresizesAllColumnsToFit =
            NO; // the default isn't actually given in the spec, but this seems
                // more like default behavior
    NS_EXTRA(NSTableView, self)->_allowsMultipleSelection = NO;
    NS_EXTRA(NSTableView, self)->_allowsEmptySelection = YES;
    NS_EXTRA(NSTableView, self)->_allowsColumnSelection = YES;

    _headerView = [[NSTableHeaderView alloc]
            initWithFrame: NSMakeRect(0, 0, [self bounds].size.width,
                                      _standardRowHeight +
                                              _intercellSpacing.height)];
    [_headerView setTableView: self];

    _cornerView = [[NSTableCornerView alloc]
            initWithFrame: NSMakeRect(0, 0, _standardRowHeight,
                                      _standardRowHeight)];

    _tableColumns = [[NSMutableArray alloc] init];
    _backgroundColor = [[NSColor controlBackgroundColor] retain];
    _gridColor = [[NSColor gridColor] retain];

    // row background and grid attributes for OS X >= 10.3
    NS_EXTRA(NSTableView, self)->_alternatingRowBackground = NO;
    NS_EXTRA(NSTableView, self)->_gridStyleMask = NSTableViewGridNone;
    NS_EXTRA(NSTableView, self)->_floatsGroupRows = YES;

    return self;
}

- (void) dealloc {
    NSZoneFree(NULL, NS_EXTRA(NSTableView, self)->_rowHeights);
    [_headerView release];
    [_cornerView release];
    [_tableColumns release];
    [_backgroundColor release];
    [_gridColor release];
    [NS_EXTRA(NSTableView, self)->_selectedRowIndexes release];
    [NS_EXTRA(NSTableView, self)->_selectedColumns release];
    [NS_EXTRA(NSTableView, self)->_sortDescriptors release];
    [NS_EXTRA(NSTableView, self)->_registeredNibs release];
    [NS_EXTRA(NSTableView, self)->_activeRowViews release];
    NS_EXTRA_FREE(NSTableView, self);
    [super dealloc];
}

- target {
    return NS_EXTRA(NSTableView, self)->_target;
}

- (SEL) action {
    return NS_EXTRA(NSTableView, self)->_action;
}

- (SEL) doubleAction {
    return _doubleAction;
}

- dataSource {
    return _dataSource;
}

- delegate {
    return _delegate;
}

- (NSView *) headerView {
    return _headerView;
}

- (NSView *) cornerView {
    return [[_cornerView retain] autorelease];
}

- (CGFloat) rowHeight {
    return _standardRowHeight;
}

- (NSSize) intercellSpacing {
    return _intercellSpacing;
}

- (NSColor *) backgroundColor {
    return _backgroundColor;
}

- (NSColor *) gridColor {
    return _gridColor;
}

- (NSString *) autosaveName {
    NSUnimplementedMethod();
    return nil;
}

// deprecated in OS X >= 10.3
// use gridStyleMask instead
- (BOOL) drawsGrid {
    return NS_EXTRA(NSTableView, self)->_gridStyleMask != NSTableViewGridNone;
}

- (NSTableViewSelectionHighlightStyle) selectionHighlightStyle {
    return NS_EXTRA(NSTableView, self)->_selectionHighlightStyle;
}

- (BOOL) usesAutomaticRowHeights {
    return NS_EXTRA(NSTableView, self)->_usesAutomaticRowHeights;
}

- (void) setUsesAutomaticRowHeights: (BOOL) value {
    NS_EXTRA(NSTableView, self)->_usesAutomaticRowHeights = value;
}

- (BOOL) floatsGroupRows {
    return NS_EXTRA(NSTableView, self)->_floatsGroupRows;
}

- (NSTableViewRowSizeStyle) rowSizeStyle {
    return NS_EXTRA(NSTableView, self)->_rowSizeStyle;
}

// Darling has no sidebar size setting; Medium is macOS's out-of-the-box choice.
- (NSTableViewRowSizeStyle) effectiveRowSizeStyle {
    if (NS_EXTRA(NSTableView, self)->_rowSizeStyle == NSTableViewRowSizeStyleDefault)
        return NSTableViewRowSizeStyleMedium;
    return NS_EXTRA(NSTableView, self)->_rowSizeStyle;
}

- (BOOL) allowsColumnReordering {
    return NS_EXTRA(NSTableView, self)->_allowsColumnReordering;
}

- (BOOL) allowsColumnResizing {
    return NS_EXTRA(NSTableView, self)->_allowsColumnResizing;
}

- (BOOL) autoresizesAllColumnsToFit {
    return NS_EXTRA(NSTableView, self)->_autoresizesAllColumnsToFit;
}

- (BOOL) allowsMultipleSelection {
    return NS_EXTRA(NSTableView, self)->_allowsMultipleSelection;
}

- (BOOL) allowsEmptySelection {
    return NS_EXTRA(NSTableView, self)->_allowsEmptySelection;
}

- (BOOL) allowsColumnSelection {
    return NS_EXTRA(NSTableView, self)->_allowsColumnSelection;
}

- (BOOL) allowsTypeSelect {
    return NS_EXTRA(NSTableView, self)->_allowsTypeSelect;
}

- (BOOL) autosaveTableColumns {
    NSUnimplementedMethod();
    return NO;
}

// row background and grid attributes for OS X >= 10.3
- (BOOL) usesAlternatingRowBackgroundColors {
    return NS_EXTRA(NSTableView, self)->_alternatingRowBackground;
}

- (unsigned int) gridStyleMask {
    return NS_EXTRA(NSTableView, self)->_gridStyleMask;
}

- (NSInteger) numberOfRows {

    if (NS_EXTRA(NSTableView, self)->_numberOfRows < 0) {
        id binding = [self _binderForBinding: @"content"];

        if (binding)
            NS_EXTRA(NSTableView, self)->_numberOfRows = [binding numberOfRows];

        if (NS_EXTRA(NSTableView, self)->_numberOfRows < 0) {
            if (_dataSource == nil)
                NS_EXTRA(NSTableView, self)->_numberOfRows = 0;
            else {
                if ([_dataSource respondsToSelector: @selector
                                 (numberOfRowsInTableView:)] == YES)
                    NS_EXTRA(NSTableView, self)->_numberOfRows = [_dataSource numberOfRowsInTableView: self];
                else {
                    // Apple AppKit only logs here, so we do the same.
                    NSLog(@"data source %@ does not respond to "
                          @"numberOfRowsInTableView:",
                          _dataSource);
                    NS_EXTRA(NSTableView, self)->_numberOfRows = 0;
                }
            }
        }
    }

    return NS_EXTRA(NSTableView, self)->_numberOfRows;
}

- (NSUInteger) numberOfColumns {
    return [_tableColumns count];
}

- (NSArray *) tableColumns {
    return _tableColumns;
}

- (NSInteger) columnWithIdentifier: (id) identifier {
    NSEnumerator *tableColumnEnumerator = [_tableColumns objectEnumerator];
    NSTableColumn *column;

    NSInteger idx = 0;
    while ((column = [tableColumnEnumerator nextObject]) != nil) {
        if ([[column identifier] isEqual: identifier])
            return idx;

        idx++;
    }

    return -1;
}

- (NSTableColumn *) tableColumnWithIdentifier: identifier {
    NSEnumerator *tableColumnEnumerator = [_tableColumns objectEnumerator];
    NSTableColumn *column;

    while ((column = [tableColumnEnumerator nextObject]) != nil)
        if ([[column identifier] isEqual: identifier])
            return column;

    return nil;
}

// Apple gives no heights for the small, medium and large styles; use the line
// height of the system font for the matching control size. Only the laid-out
// rows follow the style: -rowHeight is not tied to it (a table keeps reporting
// the height that was set, as on macOS).
static CGFloat styledRowHeight(NSTableViewRowSizeStyle style) {
    // NSFont has no larger control size to offer, so the large style uses the
    // regular system font like the medium one.
    NSControlSize size = style == NSTableViewRowSizeStyleSmall
                                 ? NSSmallControlSize
                                 : NSRegularControlSize;

    return [[NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: size]]
            defaultLineHeightForFont];
}

- (CGFloat) _effectiveRowHeight {
    return NS_EXTRA(NSTableView, self)->_rowSizeStyle == NSTableViewRowSizeStyleCustom ? _standardRowHeight
                                                          : NS_EXTRA(NSTableView, self)->_styledRowHeight;
}

static CGFloat rowHeightAtIndex(NSTableView *self, NSInteger index) {
    if (index < NS_EXTRA(NSTableView, self)->_rowHeightsCount)
        return NS_EXTRA(NSTableView, self)->_rowHeights[index];

    return [self _effectiveRowHeight];
}

- (NSRect) rectOfRow: (NSInteger) row {
    NSRect rect = _bounds;
    NSInteger i, count;

    if (row < 0 || row >= [self numberOfRows]) {
        return NSZeroRect;
    }

    rect.origin.x = 0.;
    rect.origin.y = 0.;
    for (i = 0; i < row; i++)
        rect.origin.y += rowHeightAtIndex(self, i) + _intercellSpacing.height;

    rect.size.width = 0.;
    count = [_tableColumns count];
    for (i = 0; i < count; i++)
        rect.size.width += [[_tableColumns objectAtIndex: i] width] +
                           _intercellSpacing.width;
    rect.size.height = rowHeightAtIndex(self, row) + _intercellSpacing.height;

    return rect;
}

- (NSRect) rectOfColumn: (NSInteger) column {
    NSInteger numberOfRows = [self numberOfRows];
    NSRect rect = _bounds;
    NSInteger i;

    if (column < 0 || column >= [_tableColumns count]) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"rectOfColumn: invalid index %ld (valid {%d, %lu})",
                            (long) column, 0, (unsigned long) [_tableColumns count]];
    }

    rect.origin.x = 0.;
    for (i = 0; i < column; i++)
        rect.origin.x += [[_tableColumns objectAtIndex: i] width] +
                         _intercellSpacing.width;
    rect.origin.y = 0.;

    rect.size.width = [[_tableColumns objectAtIndex: column] width] +
                      _intercellSpacing.width;
    rect.size.height = 0.;
    for (i = 0; i < numberOfRows; i++)
        rect.size.height +=
                rowHeightAtIndex(self, i) + _intercellSpacing.height;
    rect.size.height =
            MAX(rect.size.height, [[self superview] bounds].size.height);

    return rect;
}

- (NSRange) rowsInRect: (NSRect) rect {
    NSRange range = NSMakeRange(0, 0);
    NSInteger numberOfRows = [self numberOfRows];
    NSInteger i;
    CGFloat height = 0.;

    for (i = 0; i < numberOfRows; i++) {
        if (height + rowHeightAtIndex(self, i) + _intercellSpacing.height >
            rect.origin.y)
            break;
        else
            height += rowHeightAtIndex(self, i) + _intercellSpacing.height;
    }
    if (i < numberOfRows) {
        range.location = i;

        for (; i < numberOfRows; i++) {
            if (height > rect.origin.y + rect.size.height)
                break;
            else
                height += rowHeightAtIndex(self, i) + _intercellSpacing.height;
        }
        if (i < numberOfRows)
            range.length = i - range.location + 1;
        else
            range.length = numberOfRows - range.location;
    }

    return range; // returns 0,0 if not found, not NSNotFound
}

- (NSRange) columnsInRect: (NSRect) rect {
    NSRange range = NSMakeRange(0, 0);
    NSInteger numberOfColumns = [self numberOfColumns];
    NSInteger i;
    CGFloat width = 0.;

    for (i = 0; i < numberOfColumns; i++) {
        width += [[_tableColumns objectAtIndex: i] width] +
                 _intercellSpacing.width;

        if (width > rect.origin.x)
            break;
    }
    if (i < numberOfColumns) {
        range.location = i;

        for (; i < numberOfColumns; i++) {
            if (width > rect.origin.x + rect.size.width)
                break;

            width += [[_tableColumns objectAtIndex: i] width] +
                     _intercellSpacing.width;
        }
        if (i < numberOfColumns)
            range.length = i - range.location + 1;
        else
            range.length = numberOfColumns - range.location;
    }

    return range; // returns 0,0 if not found, not NSNotFound
}

- (NSInteger) rowAtPoint: (NSPoint) point {
    NSInteger row = -1;
    NSRange range;

    range = [self rowsInRect: NSMakeRect(point.x, point.y, 0., 0.)];
    if (range.length != 0)
        row = range.location;

    return row;
}

- (NSInteger) columnAtPoint: (NSPoint) point {
    NSInteger column = -1;
    NSRange range;

    range = [self columnsInRect: NSMakeRect(point.x, point.y, 0., 0.)];
    if (range.length != 0)
        column = range.location;

    return column;
}

- (NSRect) frameOfCellAtColumn: (NSInteger) column row: (NSInteger) row {
    NSRect frame;
    NSInteger i;

    if (column < 0 || column > [self numberOfColumns] || row < 0 ||
        row > [self numberOfRows])
        return NSZeroRect;

    frame.origin.x = 0.;
    for (i = 0; i < column; i++)
        frame.origin.x += [[_tableColumns objectAtIndex: i] width] +
                          _intercellSpacing.width;

    frame.origin.y = 0.;
    for (i = 0; i < row; i++)
        frame.origin.y += rowHeightAtIndex(self, i) + _intercellSpacing.height;

    frame.size.width = [[_tableColumns objectAtIndex: column] width] +
                       _intercellSpacing.width;
    frame.size.height = rowHeightAtIndex(self, row) + _intercellSpacing.height;

    return frame;
}

- (void) setTarget: target {
    NS_EXTRA(NSTableView, self)->_target = target;
}

- (void) setAction: (SEL) action {
    NS_EXTRA(NSTableView, self)->_action = action;
}

- (void) setDoubleAction: (SEL) action {
    _doubleAction = action;
}

- (void) setDataSource: dataSource {
    _dataSource = dataSource;
    [self tile]; // documented
}

- (void) setDelegate: delegate {
    struct {
        NSString *name;
        SEL selector;
    } notes[] = {{NSTableViewSelectionDidChangeNotification,
                  @selector(tableViewSelectionDidChange:)},
                 {NSTableViewColumnDidMoveNotification,
                  @selector(tableViewColumnDidMove:)},
                 {NSTableViewColumnDidResizeNotification,
                  @selector(tableViewColumnDidResize:)},
                 {NSTableViewSelectionIsChangingNotification,
                  @selector(tableViewSelectionIsChanging:)},
                 {nil, NULL}};
    NSInteger i;

    if (_delegate != nil)
        for (i = 0; notes[i].name != nil; ++i)
            [[NSNotificationCenter defaultCenter] removeObserver: _delegate
                                                            name: notes[i].name
                                                          object: self];

    _delegate = delegate;

    for (i = 0; notes[i].name != nil; ++i)
        if ([_delegate respondsToSelector: notes[i].selector])
            [[NSNotificationCenter defaultCenter] addObserver: _delegate
                                                     selector: notes[i].selector
                                                         name: notes[i].name
                                                       object: self];
}

- (void) setHeaderView: (NSTableHeaderView *) headerView {
    [headerView retain];
    [_headerView release];
    _headerView = headerView;
    [_headerView setTableView: self];
    [[self enclosingScrollView] tile];
}

- (void) setCornerView: (NSView *) view {
    [view retain];
    [_cornerView release];
    _cornerView = view;
    [[self enclosingScrollView] tile];
}

- (void) setRowHeight: (CGFloat) height {
    NSInteger numberOfRows = [self numberOfRows];
    NSInteger i;

    if (height > 0.)
        _standardRowHeight = height;
    else
        // Cocoa doesn't even NSLog() here, instead the table isn't drawn.
        _standardRowHeight = 0.;

    for (i = 0; i < NS_EXTRA(NSTableView, self)->_rowHeightsCount; i++)
        NS_EXTRA(NSTableView, self)->_rowHeights[i] = [self _effectiveRowHeight];

    [self tile];
}

- (void) setIntercellSpacing: (NSSize) size {
    _intercellSpacing = size;
    [self setNeedsDisplay: YES];
}

- (void) setBackgroundColor: (NSColor *) color {
    color = [color retain];
    [_backgroundColor release];
    _backgroundColor = color;
}

- (void) setGridColor: (NSColor *) color {
    color = [color retain];
    [_gridColor release];
    _gridColor = color;
}

- (void) setAutosaveName: (NSString *) name {
    NSUnimplementedMethod();
}

// deprecated in OS X >= 10.3
// use setGridStyleMask instead
- (void) setDrawsGrid: (BOOL) flag {
    if (flag)
        NS_EXTRA(NSTableView, self)->_gridStyleMask = NSTableViewSolidVerticalGridLineMask |
                         NSTableViewSolidHorizontalGridLineMask;
    else
        NS_EXTRA(NSTableView, self)->_gridStyleMask = NSTableViewGridNone;
}

- (void) setAllowsColumnReordering: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_allowsColumnReordering = flag;
}

- (void) setAllowsColumnResizing: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_allowsColumnResizing = flag;
}

- (void) setAutoresizesAllColumnsToFit: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_autoresizesAllColumnsToFit = flag;
}

- (void) setAllowsMultipleSelection: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_allowsMultipleSelection = flag;
}

- (void) setAllowsEmptySelection: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_allowsEmptySelection = flag;
}

- (void) setAllowsColumnSelection: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_allowsColumnSelection = flag;
}

- (void) setAllowsTypeSelect: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_allowsTypeSelect = flag;
}

- (void) setAutosaveTableColumns: (BOOL) flag {
    NSUnimplementedMethod();
}

// row background and grid attributes for OS X >= 10.3
- (void) setUsesAlternatingRowBackgroundColors: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_alternatingRowBackground = flag;
}

- (void) setGridStyleMask: (unsigned int) gridStyle {
    NS_EXTRA(NSTableView, self)->_gridStyleMask = gridStyle;
    [self setNeedsDisplay: YES];
}

- (void) setSelectionHighlightStyle: (NSTableViewSelectionHighlightStyle) value
{
    NS_EXTRA(NSTableView, self)->_selectionHighlightStyle = value;
    [self setNeedsDisplay: YES];
}

- (void) setFloatsGroupRows: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_floatsGroupRows = flag;
}

- (void) setRowSizeStyle: (NSTableViewRowSizeStyle) style {
    NS_EXTRA(NSTableView, self)->_rowSizeStyle = style;
    if (style != NSTableViewRowSizeStyleCustom)
        NS_EXTRA(NSTableView, self)->_styledRowHeight = styledRowHeight([self effectiveRowSizeStyle]);
    [self tile];
}

// the appkit dox are pretty vague on these two. should they trigger a redraw or
// reloadData? also.. i wonder if remove should use an isEqual method in
// NSTableColumn, or removeObjectIdenticalTo...
- (void) addTableColumn: (NSTableColumn *) column {
    [_tableColumns addObject: column];
    [column setTableView: self];
    [self reloadData];
    [_headerView setNeedsDisplay: YES];
}

- (void) removeTableColumn: (NSTableColumn *) column {
    [column setTableView: nil];
    [_tableColumns removeObject: column];
    [self reloadData];
    [_headerView setNeedsDisplay: YES];
}

- (void) moveColumn: (NSInteger) columnIndex toColumn: (NSInteger) newIndex {
    NSUnimplementedMethod();
}

- (NSInteger) editedRow {
    return _editedRow;
}

- (NSInteger) editedColumn {
    return _editedColumn;
}

- (id) dataSourceObjectValueForTableColumn: (NSTableColumn *) tableColumn
                                       row: (NSInteger) row
{
    if ([_delegate respondsToSelector: @selector(tableView:viewForTableColumn:row:)])
        return nil;

    if (_dataSource != nil &&
        [_dataSource respondsToSelector: @selector
                     (tableView:objectValueForTableColumn:row:)] == YES)
        return [_dataSource tableView: self
                objectValueForTableColumn: tableColumn
                                      row: row];

    id binder = [tableColumn _binderForBinding: @"value"];
    id vals = [[binder destination]
            valueForKeyPath: [binder valueForKey: @"keyPath"]];
    if (vals != nil) {
        return [vals objectAtIndex: row];
    }
    // Apple AppKit only logs here, so we do the same.
    NSLog(@"data source %@ does not respond to "
          @"tableView:objectValueForTableColumn:row:",
          _dataSource);
    return nil;
}

- (NSRect) _adjustedFrame: (NSRect) frame forCell: (NSCell *) dataCell {
    frame.origin.x += _intercellSpacing.width - 1.;
    frame.origin.y += _intercellSpacing.height;
    frame.size.width -= _intercellSpacing.width;
    frame.size.height -= _intercellSpacing.height;
    if ([dataCell isKindOfClass: [NSTextFieldCell class]])
        frame.size.height--;
    else {
        frame.origin.x--;
        frame.origin.y--;
    }
    if (frame.origin.x < 0.)
        frame.origin.x = 0.;
    if (frame.origin.y < 0.)
        frame.origin.y = 0.;
    if (frame.size.width < 0.)
        frame.size.width = 0.;
    if (frame.size.height < 0.)
        frame.size.height = 0.;

    return frame;
}

- (void) editColumn: (NSInteger) column
                row: (NSInteger) row
          withEvent: (NSEvent *) event
             select: (BOOL) select
{
    if (_editingCell)
        [self textDidEndEditing: nil];

    NSCell *editingCell;
    NSTableColumn *editingColumn = [_tableColumns objectAtIndex: column];
    NSInteger numberOfRows = [self numberOfRows];

    // light sanity check; invalid columns caught above in objectAtIndex:
    if (row < 0 || row >= numberOfRows)
        [NSException raise: NSInvalidArgumentException
                    format: @"invalid row in %@", NSStringFromSelector(_cmd)];

    if (![editingColumn isEditable])
        return;

    if ([self delegateShouldEditTableColumn: editingColumn row: row] == NO)
        return;

    if ([self dataSourceCanSetObjectValue] == NO &&
        [[editingColumn _binderForBinding: @"value"
                                   create: NO] allowsEditingForRow: row] == NO)
        [NSException raise: NSInternalInconsistencyException
                    format: @"data source does not respond to "
                            @"tableView:setObjectValue:forTableColumn:row: and "
                            @"binding is read-only"];

    editingCell = [[self preparedCellAtColumn: column row: row] copy];

    [_editingCell release];
    _editingCell = nil;
    _editedColumn = column;
    _editedRow = row;
    NS_EXTRA(NSTableView, self)->_editingFrame = NS_EXTRA(NSTableView, self)->_editingBorder = [self frameOfCellAtColumn: column
                                                           row: row];
    NS_EXTRA(NSTableView, self)->_editingFrame = [self _adjustedFrame: NS_EXTRA(NSTableView, self)->_editingFrame forCell: editingCell];
    NS_EXTRA(NSTableView, self)->_editingBorder.origin.x--;
    NS_EXTRA(NSTableView, self)->_editingBorder.origin.y--;
    NS_EXTRA(NSTableView, self)->_editingBorder.size.width++;
    NS_EXTRA(NSTableView, self)->_editingBorder.size.height++;
    if ([editingCell isKindOfClass: [NSTextFieldCell class]]) {
        _editingCell = editingCell;

        [_editingCell setDrawsBackground: YES];
        [_editingCell setBackgroundColor: _backgroundColor];

        NSText *oldEditor = NS_EXTRA(NSControl, self)->_currentEditor;
        [NS_EXTRA(NSControl, self)->_currentEditor setDelegate: nil];
        NSText *editor = [[self window] fieldEditor: YES forObject: self];
        NS_EXTRA(NSControl, self)->_currentEditor =
                [[_editingCell setUpFieldEditorAttributes: editor] retain];
        [NS_EXTRA(NSControl, self)->_currentEditor setDelegate: self];
        [oldEditor release];

        if (select == YES)
            [_editingCell selectWithFrame: NS_EXTRA(NSTableView, self)->_editingFrame
                                   inView: self
                                   editor: NS_EXTRA(NSControl, self)->_currentEditor
                                 delegate: self
                                    start: 0
                                   length: [[_editingCell stringValue] length]];
        else
            [_editingCell editWithFrame: NS_EXTRA(NSTableView, self)->_editingFrame
                                 inView: self
                                 editor: NS_EXTRA(NSControl, self)->_currentEditor
                               delegate: self
                                  event: event];

        [self setNeedsDisplay: YES];
    } else
        [editingCell release];
}

- (NSInteger) clickedRow {
    return NS_EXTRA(NSTableView, self)->_clickedRow;
}

- (NSInteger) clickedColumn {
    return NS_EXTRA(NSTableView, self)->_clickedColumn;
}

- (NSArray *) sortDescriptors {
    if (!NS_EXTRA(NSTableView, self)->_sortDescriptors)
        NS_EXTRA(NSTableView, self)->_sortDescriptors = [NSArray new];
    return [[NS_EXTRA(NSTableView, self)->_sortDescriptors retain] autorelease];
}

- (void) setSortDescriptors: (NSArray *) value {
    if (NS_EXTRA(NSTableView, self)->_sortDescriptors != value) {
        [NS_EXTRA(NSTableView, self)->_sortDescriptors release];
        NS_EXTRA(NSTableView, self)->_sortDescriptors = [value copy];
    }
}

- (NSIndexSet *) selectedRowIndexes {
    return NS_EXTRA(NSTableView, self)->_selectedRowIndexes;
}

// Use this so that KVO/Bindings notifications work automatically
- (void) _setSelectedRowIndexes: (NSIndexSet *) value {
    value = [value copy];
    [NS_EXTRA(NSTableView, self)->_selectedRowIndexes release];
    NS_EXTRA(NSTableView, self)->_selectedRowIndexes = value;

    if ([NS_EXTRA(NSTableView, self)->_selectedRowIndexes count] == 0 && !NS_EXTRA(NSTableView, self)->_allowsEmptySelection) {
        [NS_EXTRA(NSTableView, self)->_selectedRowIndexes release];
        NS_EXTRA(NSTableView, self)->_selectedRowIndexes = [[NSIndexSet alloc] initWithIndex: 0];
    }

    if ([NS_EXTRA(NSTableView, self)->_selectedRowIndexes count] > 0 && [NS_EXTRA(NSTableView, self)->_selectedColumns count] > 0) {
        // selecting a row deselects the previously selected column
        [NS_EXTRA(NSTableView, self)->_selectedColumns removeAllObjects];
        [self setNeedsDisplay: YES];
        [_headerView setNeedsDisplay: YES];
    }

    [self noteSelectionDidChange];
}

// That's the setter for _selectedRowIndexes.
- (void) selectRowIndexes: (NSIndexSet *) indexes
        byExtendingSelection: (BOOL) extend
{
    unsigned index;
    NSIndexSet *newIndexes;
    NSInteger i, last,
    try
        ;
    BOOL changed = NO;

    // Mac OS X doesn't raise an exception if one of the indices
    // is out of range. Instead, the selection is left untouched.
    if ([indexes firstIndex] != NSNotFound &&
        ([indexes firstIndex] < 0 ||
         [indexes lastIndex] >= [self numberOfRows]))
        return;

    // Selecting a row deselects all columns.
    if ([NS_EXTRA(NSTableView, self)->_selectedColumns count]) {
        [NS_EXTRA(NSTableView, self)->_selectedColumns removeAllObjects];
        [self setNeedsDisplay: YES];
        [_headerView setNeedsDisplay: YES];
        changed = YES;
    }

    if (extend) {
        NSMutableIndexSet *mutableIndexes = [[NSMutableIndexSet alloc]
                initWithIndexSet: NS_EXTRA(NSTableView, self)->_selectedRowIndexes];
        [mutableIndexes addIndexes: indexes];
        newIndexes = [[[NSIndexSet alloc] initWithIndexSet: mutableIndexes]
                autorelease];
        [mutableIndexes release];
    } else
        newIndexes = indexes;

    // Find the changed rows and mark them for redraw.
    i = [NS_EXTRA(NSTableView, self)->_selectedRowIndexes firstIndex];
    if (i == NSNotFound)
        i = [newIndexes firstIndex];
    else {
        try
            = [newIndexes firstIndex];
        if (try != NSNotFound && try < i)
            i =
            try
                ;
    }
    last = [NS_EXTRA(NSTableView, self)->_selectedRowIndexes lastIndex];
    if (last == NSNotFound)
        last = [newIndexes lastIndex];
    else {
        try
            = [newIndexes lastIndex];
        if (try != NSNotFound && try > last)
            last =
            try
                ;
    }
    if (i != NSNotFound) // If i is valid, last is valid as well.
        for (; i <= last; i++)
            if ([NS_EXTRA(NSTableView, self)->_selectedRowIndexes containsIndex: i] !=
                [newIndexes containsIndex: i]) {
                if (_editedRow == i && _editingCell != nil)
                    [self textDidEndEditing: nil];

                [self setNeedsDisplay: YES];
                changed = YES;
                // NSLog(@"NSTableView row %d for redraw.", i);
            }

    if (changed)
        [self _setSelectedRowIndexes: newIndexes];
}

- (NSInteger) selectedRow {
    NSInteger row = [NS_EXTRA(NSTableView, self)->_selectedRowIndexes firstIndex];

    if (row == NSNotFound)
        return -1;

    return row;
}

- (NSInteger) selectedColumn {
    if ([NS_EXTRA(NSTableView, self)->_selectedColumns count] == 0)
        return -1;

    return [_tableColumns indexOfObject: [NS_EXTRA(NSTableView, self)->_selectedColumns objectAtIndex: 0]];
}

- (NSInteger) numberOfSelectedRows {
    return [NS_EXTRA(NSTableView, self)->_selectedRowIndexes count];
}

- (NSInteger) numberOfSelectedColumns {
    return [NS_EXTRA(NSTableView, self)->_selectedColumns count];
}

- (BOOL) isRowSelected: (NSInteger) row {
    return [NS_EXTRA(NSTableView, self)->_selectedRowIndexes containsIndex: row];
}

- (BOOL) isColumnSelected: (NSInteger) col {
    return [NS_EXTRA(NSTableView, self)->_selectedColumns
            containsObject: [_tableColumns objectAtIndex: col]];
}

- (NSEnumerator *) selectedColumnEnumerator {
    return [NS_EXTRA(NSTableView, self)->_selectedColumns objectEnumerator];
}

- (NSIndexSet *) selectedColumnIndexes {
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    NSInteger i, count = [NS_EXTRA(NSTableView, self)->_selectedColumns count];

    for (i = 0; i < count; i++) {
        NSInteger index = [_tableColumns
                indexOfObjectIdenticalTo: [NS_EXTRA(NSTableView, self)->_selectedColumns objectAtIndex: i]];
        [result addIndex: index];
    }

    return result;
}

// Deprecated in Mac OS X 10.3.
- (NSEnumerator *) selectedRowEnumerator {
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger i, count = [NS_EXTRA(NSTableView, self)->_selectedRowIndexes count];
    NSUInteger buffer[count];

    [NS_EXTRA(NSTableView, self)->_selectedRowIndexes getIndexes: buffer maxCount: count inIndexRange: NULL];
    for (i = 0; i < count; i++)
        [rows addObject: [NSNumber numberWithInteger: buffer[i]]];

    return [rows objectEnumerator];
}

// Deprecated in Mac OS X 10.3.
- (void) selectRow: (NSInteger) row byExtendingSelection: (BOOL) extend {

    if (extend) {
        NSUInteger startRow = [self selectedRow], endRow = row;
        if (startRow > endRow) {
            endRow = startRow;
            startRow = row;
        }
        [self selectRowIndexes: [NSIndexSet
                                        indexSetWithIndexesInRange:
                                                NSMakeRange(startRow,
                                                            endRow - startRow +
                                                                    1)]
                byExtendingSelection: NO];
    } else
        [self selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
                byExtendingSelection: NO];
}

- (void) selectColumn: (NSInteger) column byExtendingSelection: (BOOL) extend {
    [self selectColumnIndexes: [NSIndexSet indexSetWithIndex: column]
         byExtendingSelection: extend];
}

- (void) selectColumnIndexes: (NSIndexSet *) indexes
        byExtendingSelection: (BOOL) extend
{
    // Like selectRowIndexes:, out-of-range indexes leave the selection untouched.
    if ([indexes count] > 0 && [indexes lastIndex] >= [_tableColumns count])
        return;

    // Selecting a column deselects all rows. Not through selectRowIndexes:, which
    // also clears the columns and, without allowsEmptySelection, re-selects row 0.
    if ([NS_EXTRA(NSTableView, self)->_selectedRowIndexes count] > 0) {
        [self willChangeValueForKey: @"selectedRowIndexes"];
        [NS_EXTRA(NSTableView, self)->_selectedRowIndexes release];
        NS_EXTRA(NSTableView, self)->_selectedRowIndexes = [[NSIndexSet alloc] init];
        [self didChangeValueForKey: @"selectedRowIndexes"];
    }

    if (extend == NO)
        [NS_EXTRA(NSTableView, self)->_selectedColumns removeAllObjects];

    for (NSUInteger i = [indexes firstIndex]; i != NSNotFound;
         i = [indexes indexGreaterThanIndex: i]) {
        NSTableColumn *tableColumn = [_tableColumns objectAtIndex: i];

        if (![NS_EXTRA(NSTableView, self)->_selectedColumns containsObject: tableColumn] &&
            [self delegateShouldSelectTableColumn: tableColumn])
            [NS_EXTRA(NSTableView, self)->_selectedColumns addObject: tableColumn];
    }

    [self noteSelectionDidChange];
    [self setNeedsDisplay: YES];
    [_headerView setNeedsDisplay: YES];
}

- (NSIndexSet *) columnIndexesInRect: (NSRect) rect {
    return [NSIndexSet indexSetWithIndexesInRange: [self columnsInRect: rect]];
}

- (void) deselectRow: (NSInteger) row {
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];

    if ([selectedRowIndexes containsIndex: row]) {
        NSMutableIndexSet *newSelection =
                [[selectedRowIndexes mutableCopy] autorelease];

        [newSelection removeIndex: row];
        [self selectRowIndexes: newSelection byExtendingSelection: NO];
    }
}

- (void) deselectColumn: (NSInteger) column {
    if ([NS_EXTRA(NSTableView, self)->_selectedColumns
                containsObject: [_tableColumns objectAtIndex: column]]) {
        [NS_EXTRA(NSTableView, self)->_selectedColumns removeObject: [_tableColumns objectAtIndex: column]];
        [self setNeedsDisplayInRect: [self rectOfColumn: column]];
        [_headerView setNeedsDisplay: YES];
    }
}

- (void) selectAll: sender {
    [self selectRowIndexes: [NSIndexSet
                                    indexSetWithIndexesInRange:
                                            NSMakeRange(0, [self numberOfRows])]
            byExtendingSelection: NO];
}

- (void) deselectAll: sender {
    [self selectRowIndexes: [NSIndexSet indexSet] byExtendingSelection: NO];
    [NS_EXTRA(NSTableView, self)->_selectedColumns removeAllObjects];
}

- (void) scrollRowToVisible: (NSInteger) index {
    [self scrollRectToVisible: [self rectOfRow: index]];
}

- (void) scrollColumnToVisible: (NSInteger) index {
    [self scrollRectToVisible: [self rectOfColumn: index]];
}

// This also resizes the row heights cache size as appropriate.
- (void) noteHeightOfRowsWithIndexesChanged: (NSIndexSet *) indexSet {
    NSInteger numberOfRows = [self numberOfRows];
    NSInteger row;

    if ([indexSet firstIndex] != NSNotFound &&
        ([indexSet firstIndex] < 0 || [indexSet lastIndex] >= numberOfRows))
        [NSException raise: NSInternalInconsistencyException
                    format: @"Index set %@ out of range (valid are 0 to %ld).",
                            indexSet, (long) numberOfRows];

    NS_EXTRA(NSTableView, self)->_rowHeights = realloc(NS_EXTRA(NSTableView, self)->_rowHeights, sizeof(CGFloat) * numberOfRows);

    row = [indexSet firstIndex];
    if (_delegate != nil && [_delegate respondsToSelector: @selector
                                       (tableView:heightOfRow:)] == YES) {
        while (row != NSNotFound) {
            NS_EXTRA(NSTableView, self)->_rowHeights[row] = [_delegate tableView: self heightOfRow: row];
            row = [indexSet indexGreaterThanIndex: row];
        }
    } else {
        while (row != NSNotFound) {
            NS_EXTRA(NSTableView, self)->_rowHeights[row] = [self _effectiveRowHeight];
            row = [indexSet indexGreaterThanIndex: row];
        }
    }
}

- (void) beginUpdates {
    NS_EXTRA(NSTableView, self)->_updatesNestingCount++;
}

- (void) endUpdates {
    if (NS_EXTRA(NSTableView, self)->_updatesNestingCount > 0) {
        NS_EXTRA(NSTableView, self)->_updatesNestingCount--;
        if (NS_EXTRA(NSTableView, self)->_updatesNestingCount == 0) {
            [self noteNumberOfRowsChanged];
            [self setNeedsDisplay: YES];
        }
    }
}

- (void) insertRowsAtIndexes: (NSIndexSet *) indexes withAnimation: (NSTableViewAnimationOptions) animationOptions {
    [self noteNumberOfRowsChanged];
    [self setNeedsDisplay: YES];
}

- (void) removeRowsAtIndexes: (NSIndexSet *) indexes withAnimation: (NSTableViewAnimationOptions) animationOptions {
    [self noteNumberOfRowsChanged];
    [self setNeedsDisplay: YES];
}

- (void) moveRowAtIndex: (NSInteger) oldIndex toIndex: (NSInteger) newIndex {
    [self noteNumberOfRowsChanged];
    [self setNeedsDisplay: YES];
}

- (void) noteNumberOfRowsChanged {
    NSSize size = [self frame].size;
    NSSize headerSize = [_headerView frame].size;

    NS_EXTRA(NSTableView, self)->_numberOfRows = -1;
    NSInteger numberOfRows = [self numberOfRows];

    // There isn't much point in trying to validate the heights of
    // visible rows only, as the often used -rectOfColumn: needs them all.
    [self noteHeightOfRowsWithIndexesChanged:
                    [NSIndexSet
                            indexSetWithIndexesInRange: NSMakeRange(
                                                                0,
                                                                numberOfRows)]];

    // if there's any editing going on, we'd better stop it.
    if (_editingCell != nil)
        [self textDidEndEditing: nil];

    if (numberOfRows > 0) {
        size.width = [self rectOfRow: 0].size.width;
    }
    if ([_tableColumns count] > 0)
        size.height = [self rectOfColumn: 0].size.height;

    headerSize.width = size.width;

    [self setFrameSize: size];
    [_headerView setFrameSize: headerSize];

    NSMutableIndexSet *selection =
            [[NS_EXTRA(NSTableView, self)->_selectedRowIndexes mutableCopy] autorelease];
    NSInteger count = [selection count];
    NSUInteger indexes[count];
    [selection getIndexes: indexes maxCount: count inIndexRange: NULL];

    while (--count >= 0) {
        if (indexes[count] >= numberOfRows)
            [selection removeIndex: indexes[count]];
    }

    /* Do not change the selection if it didnt change. _setSelectedRowIndexes
       posts a notification and doing it unnecessarily can cause performance and
       behavior problems. For example, if there is no selection in a newly
       created tableview and you post the notification indirectly with
       setDataSource:, an application which expects a non-empty selection will
       have problems.

       FIXME: investigate whether _setSelectedRowIndexes: should do this check
       or not.
      */
    if (![selection isEqualToIndexSet: NS_EXTRA(NSTableView, self)->_selectedRowIndexes])
        [self _setSelectedRowIndexes: selection];
}

- (void) reloadData {
    for (NSView *view in NS_EXTRA(NSTableView, self)->_activeRowViews) {
        [view removeFromSuperview];
    }
    [NS_EXTRA(NSTableView, self)->_activeRowViews removeAllObjects];
    [self noteNumberOfRowsChanged];
    [self setNeedsDisplay: YES];
    [_headerView setNeedsDisplay: YES];
}

- (void) reloadDataForRowIndexes: (NSIndexSet *) rowIndexes
                   columnIndexes: (NSIndexSet *) columnIndexes
{
    [self setNeedsDisplay: YES];
}

- (void) tile {
    NSRect rect;

    [self sizeLastColumnToFit];
    [self noteNumberOfRowsChanged];
    rect = [_headerView frame];
    rect.size.width = [self frame].size.width;
    [_headerView setFrameSize: rect.size];

    [[self enclosingScrollView]
            setVerticalLineScroll: [self _effectiveRowHeight] +
                                   _intercellSpacing.height];

    [self setNeedsDisplay: YES];
    [_headerView setNeedsDisplay: YES];
}

- (void) sizeLastColumnToFit {
    NSClipView *clipView = (NSClipView *) [self superview];

    if ([clipView isKindOfClass: [NSClipView class]]) {
        NSSize size = [clipView bounds].size;
        NSInteger i, count = [_tableColumns count];
        CGFloat lastWidth = size.width - (count * _intercellSpacing.width);
        NSTableColumn *lastColumn = [_tableColumns lastObject];

        for (i = 0; i < count - 1; ++i)
            lastWidth -= [[_tableColumns objectAtIndex: i] width];

        if (lastWidth > 0)
            [lastColumn setWidth: lastWidth];
        else if (lastWidth < 0)
            [lastColumn setWidth: [lastColumn width] + lastWidth];

        [self setNeedsDisplay: YES];
    }
}

- (void) drawHighlightedSelectionForColumn: (NSInteger) column
                                       row: (NSInteger) row
                                    inRect: (NSRect) rect
{
    [[NSColor selectedControlColor] setFill];
    NSRectFill(rect);
}

- (void) highlightSelectionInClipRect: (NSRect) rect {
    NSInteger row, column;
    NSInteger numberOfRows = [self numberOfRows];

    for (column = 0; column < [_tableColumns count]; ++column)
        for (row = 0; row < numberOfRows; ++row)
            if ([self isColumnSelected: column] || [self isRowSelected: row])
                if (!(row == _editedRow && column == _editedColumn))
                    [self drawHighlightedSelectionForColumn: column
                                                        row: row
                                                     inRect: [self frameOfCellAtColumn:
                                                                             column
                                                                                   row: row]];
}

- (NSCell *) preparedCellAtColumn: (NSInteger) columnNumber
                              row: (NSInteger) row
{
    NSTableColumn *column = [_tableColumns objectAtIndex: columnNumber];
    NSCell *dataCell = [column dataCellForRow: row];

    [dataCell setControlView: self];
    id value = [self dataSourceObjectValueForTableColumn: column row: row];
    if ([dataCell isKindOfClass: [NSPopUpButtonCell class]]) {
        [(NSPopUpButtonCell *) dataCell selectItemAtIndex: [value intValue]];
    } else {
        [dataCell setObjectValue: value];
    }

    if ([dataCell respondsToSelector: @selector(setTextColor:)]) {
        if ([self isRowSelected: row] ||
            [self isColumnSelected: columnNumber]) {
            [(NSTextFieldCell *) dataCell
                    setDrawsBackground: NO]; // so the selection shows properly,
                                             // dont just set the color so
                                             // custom background works
            [(NSTextFieldCell *) dataCell
                    setTextColor: [NSColor selectedTextColor]];
        } else
            [(NSTextFieldCell *) dataCell setTextColor: [NSColor textColor]];
    }

    [column prepareCell: dataCell inRow: row];

    if ([_delegate respondsToSelector: @selector
                   (tableView:willDisplayCell:forTableColumn:row:)])
        [_delegate tableView: self
                willDisplayCell: dataCell
                 forTableColumn: column
                            row: row];

    return dataCell;
}

- (void) drawRow: (NSInteger) row clipRect: (NSRect) clipRect {
    if ([_delegate respondsToSelector: @selector(tableView:viewForTableColumn:row:)]) {
        NSRange visibleColumns = [self columnsInRect: clipRect];
        NSInteger drawThisColumn = visibleColumns.location;

        if ([self isRowSelected: row]) {
            [[NSColor selectedControlColor] setFill];
            NSRectFill([self rectOfRow: row]);
        }

        for (; drawThisColumn < NSMaxRange(visibleColumns); drawThisColumn++) {
            NSTableColumn *column = [_tableColumns objectAtIndex: drawThisColumn];
            NSRect cellRect = [self frameOfCellAtColumn: drawThisColumn row: row];
            NSView *cellView = [_delegate tableView: self viewForTableColumn: column row: row];
            if (cellView != nil) {
                [cellView setFrame: cellRect];
                if ([cellView superview] != self) {
                    [self addSubview: cellView];
                }
                [cellView setHidden: NO];
                [cellView displayRectIgnoringOpacity: [cellView bounds]];
            }
        }
        return;
    }

    // draw only visible columns.
    NSRange visibleColumns = [self columnsInRect: clipRect];
    NSInteger drawThisColumn = visibleColumns.location;
    NSInteger numberOfRows = [self numberOfRows];

    if (row < 0 || row >= numberOfRows)
        [NSException raise: NSInvalidArgumentException
                    format: @"invalid row in drawRow:clipRect:"];

    for (; drawThisColumn < NSMaxRange(visibleColumns); drawThisColumn++) {

        if (row == _editedRow && drawThisColumn == _editedColumn &&
            _editingCell != nil) {
            [_backgroundColor setFill];
            NSRectFill(NS_EXTRA(NSTableView, self)->_editingBorder);
            [_editingCell setControlView: self];
            [_editingCell drawWithFrame: NS_EXTRA(NSTableView, self)->_editingFrame inView: self];
            if ([_editingCell focusRingType] != NSFocusRingTypeNone) {
                [[NSColor keyboardFocusIndicatorColor] setStroke];
                NSFrameRectWithWidth(NS_EXTRA(NSTableView, self)->_editingBorder, 2.0);
            }
        } else {
            NSCell *dataCell = [self preparedCellAtColumn: drawThisColumn
                                                      row: row];
            NSRect cellRect = [self
                    _adjustedFrame: [self frameOfCellAtColumn: drawThisColumn
                                                          row: row]
                           forCell: dataCell];

            [dataCell drawWithFrame: cellRect inView: self];
        }
    }
}

- (void) drawBackgroundInClipRect: (NSRect) clipRect {
    NSArray *rowColors = [NSColor controlAlternatingRowBackgroundColors];
    NSInteger colorCount = [rowColors count];

    if (colorCount == 0 || !NS_EXTRA(NSTableView, self)->_alternatingRowBackground) {
        [_backgroundColor setFill];
        NSRectFill(clipRect);
    } else if (colorCount == 1) {
        [(NSColor *) [rowColors objectAtIndex: 0] setFill];
        NSRectFill(clipRect);
    } else {
        NSRange rangeOfRows = [self rowsInRect: clipRect];
        NSInteger i;
        NSRect rectToFill = clipRect;
        CGFloat heightFilled = 0.;

        for (i = rangeOfRows.location;
             i < rangeOfRows.location + rangeOfRows.length; i++) {
            rectToFill = [self rectOfRow: i];

            [(NSColor *) [rowColors objectAtIndex: i % colorCount] setFill];
            NSRectFill(rectToFill);
            rectToFill.origin.y +=
                    rectToFill.size.height; // This is for beyond the loop.
            heightFilled = rectToFill.origin.y;
        }
        if ([self _effectiveRowHeight] > 0.) {
            rectToFill.size.height =
                    [self _effectiveRowHeight] + _intercellSpacing.height;
            while (heightFilled < clipRect.size.height) {
                [(NSColor *) [rowColors objectAtIndex: i % colorCount] setFill];
                NSRectFill(rectToFill);
                heightFilled += rectToFill.size.height;
                rectToFill.origin.y += rectToFill.size.height;
                i++;
            }
        }
    }
}

// That is, draw a line one pixel wide in color gridColor at the
// bottom/right of each row/column, including the last row/column.
// Verified by comparing screen shots on Mac OS X 10.4.10.
- (void) drawGridInClipRect: (NSRect) clipRect {
    NSBezierPath *line = [NSBezierPath bezierPath];
    NSInteger i, n;
    CGFloat x, y;

    [_gridColor setStroke];

    if ((NS_EXTRA(NSTableView, self)->_gridStyleMask & NSTableViewSolidVerticalGridLineMask) ==
        NSTableViewSolidVerticalGridLineMask) {
        NSRange rangeOfColumns = [self columnsInRect: clipRect];
        n = rangeOfColumns.location + rangeOfColumns.length;
        for (i = rangeOfColumns.location; i < n; i++) {
            NSRect columnRect = [self rectOfColumn: i];
            x = columnRect.origin.x + columnRect.size.width +
                ((i < n - 1) ? -0.5 : 0.5);
            y = clipRect.origin.y;
            [line moveToPoint: NSMakePoint(x, y)];
            [line lineToPoint: NSMakePoint(x, y + clipRect.size.height)];
        }
    }

    if ((NS_EXTRA(NSTableView, self)->_gridStyleMask & NSTableViewSolidHorizontalGridLineMask) ==
        NSTableViewSolidHorizontalGridLineMask) {
        NSRange rangeOfRows = [self rowsInRect: clipRect];
        n = rangeOfRows.location + rangeOfRows.length;
        y = -0.5;
        for (i = rangeOfRows.location; i < n; i++) {
            NSRect rowRect = [self rectOfRow: i];
            x = clipRect.origin.x;
            y = rowRect.origin.y + rowRect.size.height - 0.5;
            [line moveToPoint: NSMakePoint(x, y)];
            [line lineToPoint: NSMakePoint(x + clipRect.size.width, y)];
        }

        if ([self _effectiveRowHeight] > 0.0) {
            while (y < clipRect.size.height) {
                y += [self _effectiveRowHeight] + _intercellSpacing.height;
                [line moveToPoint: NSMakePoint(clipRect.origin.x, y)];
                [line lineToPoint: NSMakePoint(clipRect.origin.x +
                                                       clipRect.size.width,
                                               y)];
            }
        }
    }

    [line stroke];
}

// can't use rectOfRow because empty tableviews will explode!
- (CGFloat) _displayWidthOfColumns {
    NSInteger i, count = [_tableColumns count];
    CGFloat result = 0;

    for (i = 0; i < count; ++i)
        result += [[_tableColumns objectAtIndex: i] width] +
                  _intercellSpacing.width;

    return result;
}

- (void) resizeWithOldSuperviewSize: (NSSize) oldSize {
    NSSize size = [self frame].size;

    if (size.width < [[self superview] bounds].size.width) {
        size.width = [[self superview] bounds].size.width;
        [self setFrameSize: size];
    }

    if (NS_EXTRA(NSTableView, self)->_autoresizesAllColumnsToFit) {
        CGFloat delta = [[self enclosingScrollView] contentSize].width -
                        [self _displayWidthOfColumns];
        NSInteger i, count = [_tableColumns count];

        for (i = 0; i < count; ++i) {
            NSTableColumn *column = [_tableColumns objectAtIndex: i];
            [column setWidth: [column width] + floor((delta / count))];
        }

    } else
        [self sizeLastColumnToFit];

    [self tile];
}

- (BOOL) isFlipped {
    return YES;
}

- (BOOL) delegateShouldSelectTableColumn: (NSTableColumn *) tableColumn {
    if ([_delegate respondsToSelector: @selector(tableView:
                                               shouldSelectTableColumn:)])
        return [_delegate tableView: self shouldSelectTableColumn: tableColumn];

    return YES;
}

- (BOOL) delegateShouldSelectRow: (NSInteger) row {
    if ([_delegate respondsToSelector: @selector(tableView:shouldSelectRow:)])
        return [_delegate tableView: self shouldSelectRow: row];

    return YES;
}

- (void) dataSourceSetObjectValue: object
                   forTableColumn: (NSTableColumn *) tableColumn
                              row: (NSInteger) row
{
    if ([_dataSource respondsToSelector: @selector
                     (tableView:setObjectValue:forTableColumn:row:)])
        [_dataSource tableView: self
                setObjectValue: object
                forTableColumn: tableColumn
                           row: row];
}

- (BOOL) abortEditing {
    [super abortEditing];
    [_editingCell release];
    _editingCell = nil;
    [self setNeedsDisplayInRect: NSInsetRect(NS_EXTRA(NSTableView, self)->_editingBorder, -1, -1)];
    NS_EXTRA(NSTableView, self)->_editingFrame = NSMakeRect(-1, -1, -1, -1);
    _editedRow = -1;
    _editedColumn = -1;
    return NO;
}

- (void) textDidEndEditing: (NSNotification *) note {
    NSTableColumn *editedColumn = [_tableColumns objectAtIndex: _editedColumn];
    NSInteger textMovement =
            [[[note userInfo] objectForKey: @"NSTextMovement"] intValue];
    NSInteger numberOfRows = [self numberOfRows];

    [_editingCell endEditing: NS_EXTRA(NSControl, self)->_currentEditor];

    if (_editedRow >= 0 && _editedRow < numberOfRows) {
        if ([self dataSourceCanSetObjectValue]) {
            [self dataSourceSetObjectValue: [_editingCell objectValue]
                            forTableColumn: editedColumn
                                       row: _editedRow];
        } else {
            [[editedColumn _binderForBinding: @"value"
                                      create: NO] applyFromCell: _editingCell
                                                          inRow: _editedRow];
        }
    }

    [self abortEditing];
    [_window makeFirstResponder: nil];

    // NSReturnTextMovement has lousy behaviour , fix.
    // don't really need any of the text movement stuff, so we ignore it for now
    textMovement = NSIllegalTextMovement;

    if (textMovement == NSReturnTextMovement) {
        NSInteger nextRow = _editedRow + 1;

        if (nextRow >= numberOfRows)
            nextRow = 0;

        [self selectRow: nextRow byExtendingSelection: NO];
        [self editColumn: _editedColumn
                      row: nextRow
                withEvent: [[self window] currentEvent]
                   select: YES];
    } else if (textMovement == NSTabTextMovement) {
        NSInteger nextColumn = _editedColumn;
        NSInteger nextRow = _editedRow;

        do {
            nextColumn++;
            if (nextColumn >= [_tableColumns count]) {
                nextColumn = 0;
                nextRow++;
                if (nextRow >= numberOfRows)
                    nextRow = 0;
            }

            if ([[_tableColumns objectAtIndex: nextColumn] isEditable])
                break;
        } while (YES);

        [self selectRow: nextRow byExtendingSelection: NO];
        [self editColumn: nextColumn
                      row: nextRow
                withEvent: [[self window] currentEvent]
                   select: YES];
    } else if (textMovement == NSBacktabTextMovement) {
        NSInteger prevColumn = _editedColumn - 1;
        NSInteger prevRow = _editedRow;

        if (prevColumn < 0) {
            prevColumn = [_tableColumns count] - 1;
            prevRow -= 1;
            if (prevRow < 0)
                prevRow = numberOfRows - 1;
        }

        [self selectRow: prevRow byExtendingSelection: NO];
        [self editColumn: prevColumn
                      row: prevRow
                withEvent: [[self window] currentEvent]
                   select: YES];
    } else {
        _editedColumn = -1;
        _editedRow = -1;
    }
}

- (BOOL) delegateShouldEditTableColumn: (NSTableColumn *) tableColumn
                                   row: (NSInteger) row
{
    if ([_delegate respondsToSelector: @selector(tableView:
                                               shouldEditTableColumn:row:)])
        return [_delegate tableView: self
                shouldEditTableColumn: tableColumn
                                  row: row];

    return YES;
}

- (void) updateCell: (NSCell *) sender {
    // blank
}

- (void) updateCellInside: (NSCell *) cell {
    // blank
}

- (void) drawRect: (NSRect) clipRect {
    NSRange visibleRows;
    NSInteger drawThisRow, numberOfRows = [self numberOfRows];

    [self drawBackgroundInClipRect: clipRect];

    if (numberOfRows > 0) {
        [self highlightSelectionInClipRect: clipRect];

        visibleRows = [self rowsInRect: clipRect];
        if (visibleRows.length > 0) {
            drawThisRow = visibleRows.location;

            // FIX: Always drawing entire rows is inefficient.
            //      Should draw visible cells, only.
            while (drawThisRow < NSMaxRange(visibleRows) &&
                   drawThisRow < numberOfRows)
                [self drawRow: drawThisRow++ clipRect: clipRect];
        }
    }

    if ([self drawsGrid])
        [self drawGridInClipRect: clipRect];

    if (NS_EXTRA(NSTableView, self)->_draggingRow >= 0) {
        NSRect rowRect;
        [[NSColor blackColor] setStroke];
        if ([self numberOfRows] == 0)
            [NSBezierPath
                    strokeLineFromPoint: NSMakePoint(0, 0)
                                toPoint: NSMakePoint([self bounds].size.width,
                                                     0)];
        else {
            if (NS_EXTRA(NSTableView, self)->_draggingRow == [self numberOfRows]) {
                rowRect = NSIntersectionRect([self rectOfRow: NS_EXTRA(NSTableView, self)->_draggingRow - 1],
                                             [self visibleRect]);
                [NSBezierPath
                        strokeLineFromPoint: NSMakePoint(
                                                     0, rowRect.origin.y +
                                                                rowRect.size
                                                                        .height)
                                    toPoint: NSMakePoint(
                                                     rowRect.size.width,
                                                     rowRect.origin.y +
                                                             rowRect.size
                                                                     .height)];
            } else {
                rowRect = NSIntersectionRect([self rectOfRow: NS_EXTRA(NSTableView, self)->_draggingRow],
                                             [self visibleRect]);
                [NSBezierPath
                        strokeLineFromPoint: NSMakePoint(0, rowRect.origin.y)
                                    toPoint: NSMakePoint(rowRect.size.width,
                                                         rowRect.origin.y)];
            }
        }
    }
}

- (BOOL) delegateSelectionShouldChange {
    if ([_delegate respondsToSelector: @selector
                   (selectionShouldChangeInTableView:)])
        return [_delegate selectionShouldChangeInTableView: self];

    return YES;
}

- (void) noteSelectionIsChanging {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSTableViewSelectionIsChangingNotification
                          object: self];
}

- (void) noteSelectionDidChange {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSTableViewSelectionDidChangeNotification
                          object: self];
}

- (void) noteColumnDidResizeWithOldWidth: (CGFloat) oldWidth {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSTableViewColumnDidResizeNotification
                          object: self
                        userInfo: [NSDictionary
                                          dictionaryWithObjectsAndKeys:
                                                  [NSNumber numberWithFloat:
                                                                    oldWidth],
                                                  @"NSOldWidth", nil]];
}

- (BOOL) dataSourceCanSetObjectValue {
    return [_dataSource respondsToSelector: @selector
                        (tableView:setObjectValue:forTableColumn:row:)];
}

- (void) mouseDown: (NSEvent *) event {
    NSPoint location = [self convertPoint: [event locationInWindow]
                                 fromView: nil];
    NSInteger numberOfRows = [self numberOfRows];

    NS_EXTRA(NSTableView, self)->_clickedColumn = [self columnAtPoint: location];
    NS_EXTRA(NSTableView, self)->_clickedRow = [self rowAtPoint: location];

    if (NS_EXTRA(NSTableView, self)->_clickedRow < 0) { // click beyond the end of the table
        if (_editingCell != nil)
            [self textDidEndEditing: nil];
        [self selectRowIndexes: [NSIndexSet indexSet] byExtendingSelection: NO];
        [NS_EXTRA(NSTableView, self)->_selectedColumns removeAllObjects];
        return;
    }

    NSTableColumn *clickedColumnObject =
            [_tableColumns objectAtIndex: NS_EXTRA(NSTableView, self)->_clickedColumn];

    if (![self delegateShouldSelectTableColumn: clickedColumnObject])
        return;
    if (![self delegateShouldSelectRow: NS_EXTRA(NSTableView, self)->_clickedRow])
        return;

    NSCell *clickedCell = [clickedColumnObject dataCellForRow: NS_EXTRA(NSTableView, self)->_clickedRow];

    [clickedCell setControlView: self];
    if ([clickedCell isKindOfClass: [NSButtonCell class]]) {
        [clickedCell
                setObjectValue:
                        [self dataSourceObjectValueForTableColumn:
                                        clickedColumnObject
                                                              row: NS_EXTRA(NSTableView, self)->_clickedRow]];

        if ([clickedCell trackMouse: event
                             inRect: [self frameOfCellAtColumn: NS_EXTRA(NSTableView, self)->_clickedColumn
                                                           row: NS_EXTRA(NSTableView, self)->_clickedRow]
                             ofView: self
                       untilMouseUp: YES]) {
            [clickedCell setNextState];
            NSNumber *value = nil;
            if ([clickedCell isKindOfClass: [NSPopUpButtonCell class]]) {
                value = [NSNumber
                        numberWithInt: [(NSPopUpButtonCell *) clickedCell
                                               indexOfSelectedItem]];
            } else {
                value = [NSNumber numberWithInt: [clickedCell state]];
            }
            [self dataSourceSetObjectValue: value
                            forTableColumn: clickedColumnObject
                                       row: NS_EXTRA(NSTableView, self)->_clickedRow];
            [self sendAction: [clickedCell action] to: [clickedCell target]];
        }

        [self setNeedsDisplay: YES];

        return;
    }

    // NSLog(@"click in col %d row %d", _clickedColumn, _clickedRow);
    // single click behavior
    if ([event clickCount] < 2) {
        if ([self delegateSelectionShouldChange] ==
            NO) // provide delegate opportunity
            return;

        if ([event modifierFlags] &
            NSAlternateKeyMask) {                    // extend/change selection
            if ([self isRowSelected: NS_EXTRA(NSTableView, self)->_clickedRow]) { // deselect previously
                                                     // selected?
                if ([self allowsEmptySelection] ||
                    [self numberOfSelectedColumns] > 1)
                    [self deselectRow: NS_EXTRA(NSTableView, self)->_clickedRow];
            } else if ([self allowsMultipleSelection]) {
                [self selectRowIndexes: [NSIndexSet
                                                indexSetWithIndex: NS_EXTRA(NSTableView, self)->_clickedRow]
                        byExtendingSelection: YES]; // add to selection
            }
        } else if ([event modifierFlags] & NSShiftKeyMask) {
            if ([self allowsMultipleSelection] && [self selectedRow] != -1) {
                NSInteger startRow = [self selectedRow];
                NSInteger endRow = NS_EXTRA(NSTableView, self)->_clickedRow;

                if (NS_EXTRA(NSTableView, self)->_clickedRow < startRow) {
                    endRow = startRow;
                    startRow = NS_EXTRA(NSTableView, self)->_clickedRow;
                }

                [self selectRowIndexes:
                                [NSIndexSet
                                        indexSetWithIndexesInRange:
                                                NSMakeRange(startRow,
                                                            endRow - startRow +
                                                                    1)]
                        byExtendingSelection: NO];
            } else
                [self selectRowIndexes: [NSIndexSet
                                                indexSetWithIndex: NS_EXTRA(NSTableView, self)->_clickedRow]
                        byExtendingSelection: NO];
        } else { // normal selection, allow for dragging
            BOOL dragging = NO;
            if ([_dataSource respondsToSelector: @selector
                             (tableView:writeRowsWithIndexes:toPasteboard:)]) {
                NSPoint currentPoint;
                do {
                    event = [_window
                            nextEventMatchingMask: NSLeftMouseUpMask |
                                                   NSLeftMouseDraggedMask
                                        untilDate: [NSDate distantFuture]
                                           inMode: NSEventTrackingRunLoopMode
                                          dequeue: NO];
                    if ([event type] == NSLeftMouseDragged)
                        event = [_window
                                nextEventMatchingMask: NSLeftMouseUpMask |
                                                       NSLeftMouseDraggedMask];
                    else
                        break;
                    currentPoint = [self convertPoint: [event locationInWindow]
                                             fromView: nil];
                    if (fabs(location.x - currentPoint.x) > 5 ||
                        fabs(location.y - currentPoint.y) > 5) {
                        dragging = YES;
                        break;
                    }
                } while ([event type] != NSLeftMouseUp);
            }
            if (dragging) {
                NSIndexSet *rowIndexes = [self selectedRowIndexes];
                if ([rowIndexes containsIndex: NS_EXTRA(NSTableView, self)->_clickedRow] == NO)
                    rowIndexes = [NSIndexSet indexSetWithIndex: NS_EXTRA(NSTableView, self)->_clickedRow];

                NSPasteboard *pasteboard =
                        [NSPasteboard pasteboardWithName: NSDragPboard];
                if ([_dataSource tableView: self
                            writeRowsWithIndexes: rowIndexes
                                    toPasteboard: pasteboard] == NO)
                    dragging = NO;
                else {
                    NSImage *image = [[[NSImage alloc]
                            initWithSize: NSMakeSize(0, 0)] autorelease];
                    [self dragImage: image
                                    at: NSMakePoint(0, 0)
                                offset: NSMakeSize(0, 0)
                                 event: event
                            pasteboard: pasteboard
                                source: self
                             slideBack: YES];
                }
            }

            if (dragging == NO) {
                // normal selection, allow for dragging
                NSInteger firstClickedRow = NS_EXTRA(NSTableView, self)->_clickedRow;

                [self selectRowIndexes: [NSIndexSet
                                                indexSetWithIndex: NS_EXTRA(NSTableView, self)->_clickedRow]
                        byExtendingSelection: NO];
                if ([self allowsMultipleSelection] == YES) {
                    do {
                        NSPoint point;
                        NSInteger row;

                        event = [_window
                                nextEventMatchingMask: NSLeftMouseUpMask |
                                                       NSLeftMouseDraggedMask];
                        point = [self convertPoint: [event locationInWindow]
                                          fromView: nil];

                        row = [self rowAtPoint: point];
                        if (row != -1) {
                            // we need to smooth out the selection granularity.
                            // on my slow system, the mouse moves too quickly
                            // for the NSEvents to show up for each row..
                            NSInteger startRow, endRow, i;

                            if (firstClickedRow > row) {
                                endRow = firstClickedRow;
                                startRow = row;
                            } else {
                                startRow = firstClickedRow;
                                endRow = row;
                            }

                            for (i = 0; i < numberOfRows; i++) {
                                if (i >= startRow && i <= endRow)
                                    [self selectRowIndexes:
                                                    [NSIndexSet
                                                            indexSetWithIndex:
                                                                    i]
                                            byExtendingSelection: YES];
                                else
                                    [self deselectRow: i];
                            }
                        }

                        [self noteSelectionIsChanging];
                    } while ([event type] != NSLeftMouseUp);
                }
            }
        }

        [self sendAction: [self action] to: [self target]];
    } else if ([event clickCount] == 2) {
        // nb this logic was backwards previously

        id binder = [[_tableColumns objectAtIndex: NS_EXTRA(NSTableView, self)->_clickedColumn]
                _binderForBinding: @"value"
                           create: NO];
        BOOL interpretedAsEdit = NO;
        if ([[_tableColumns objectAtIndex: NS_EXTRA(NSTableView, self)->_clickedColumn] isEditable]) {
            if ([self dataSourceCanSetObjectValue] ||
                [binder allowsEditingForRow: NS_EXTRA(NSTableView, self)->_clickedRow]) {
                if (NS_EXTRA(NSTableView, self)->_clickedColumn != -1 && NS_EXTRA(NSTableView, self)->_clickedRow != -1) {
                    if ([self delegateShouldEditTableColumn:
                                        [_tableColumns
                                                objectAtIndex: NS_EXTRA(NSTableView, self)->_clickedColumn]
                                                        row: NS_EXTRA(NSTableView, self)->_clickedRow]) {
                        interpretedAsEdit = YES;
                        [self editColumn: [self clickedColumn]
                                      row: NS_EXTRA(NSTableView, self)->_clickedRow
                                withEvent: event
                                   select: YES];
                    }
                }
            }
        }
        if (!interpretedAsEdit)
            [self sendAction: [self doubleAction] to: [self target]];
    }
}

- (void) _tightenUpColumn: (NSTableColumn *) column {
    NSInteger i, numberOfRows = [self numberOfRows];
    CGFloat minWidth = 0.0, width;

    for (i = 0; i < numberOfRows; ++i) {
        NSCell *dataCell = [column dataCellForRow: i];

        [dataCell setControlView: self];
        [dataCell setObjectValue:
                          [self dataSourceObjectValueForTableColumn: column
                                                                row: i]];

        width = [[dataCell attributedStringValue] size].width;
        if (width > minWidth)
            minWidth = width;
    }
    width = [[[column headerCell] attributedStringValue] size].width;
    if (width > minWidth)
        minWidth = width;

    [column setMinWidth: minWidth];
}

- (void) sizeToFit {
    NSInteger i, count = [_tableColumns count];

    for (i = 0; i < count; ++i) {
        NSTableColumn *column = [_tableColumns objectAtIndex: i];

        [self _tightenUpColumn: column];
        [column setWidth: [column minWidth]];
    }

    [self tile];
}

- (void) setDraggingSourceOperationMask: (NSDragOperation) mask
                               forLocal: (BOOL) isLocal
{
    if (isLocal)
        NS_EXTRA(NSTableView, self)->_draggingSourceMaskLocal = mask;
    else
        NS_EXTRA(NSTableView, self)->_draggingSourceMaskNonLocal = mask;
}

- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) isLocal {
    return isLocal ? NS_EXTRA(NSTableView, self)->_draggingSourceMaskLocal : NS_EXTRA(NSTableView, self)->_draggingSourceMaskNonLocal;
}

- (NSInteger) _getDraggedRow: (id<NSDraggingInfo>) info {
    NSPoint dragPoint = [self convertPoint: [info draggingLocation]
                                  fromView: nil];
    NSInteger draggedRow = [self rowAtPoint: dragPoint];
    if (-1 == draggedRow) {
        if (dragPoint.y >= [self rectOfRow: [self numberOfRows] - 1].origin.y) {
            draggedRow = [self numberOfRows];
        }
    }
    return draggedRow;
}

- (unsigned) _validateDraggedRow: (id<NSDraggingInfo>) info {
    BOOL result;
    NSInteger proposedRow = [self _getDraggedRow: info];

    if ([_dataSource
                respondsToSelector: @selector
                (tableView:validateDrop:proposedRow:proposedDropOperation:)]) {
        if ((result = [_dataSource tableView: self
                                validateDrop: info
                                 proposedRow: proposedRow
                       proposedDropOperation: NSTableViewDropAbove]))
            NS_EXTRA(NSTableView, self)->_draggingRow = proposedRow;
        else
            NS_EXTRA(NSTableView, self)->_draggingRow = -1;
    }

    [self display];

    return result;
}

- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) sender {
    for (NSInteger i = 0; i < [[self _draggedTypes] count]; i++) {
        if ([[[sender draggingPasteboard] types]
                    containsObject: [[self _draggedTypes] objectAtIndex: i]])
            return [self _validateDraggedRow: sender];
    }
    return NSDragOperationNone;
}

- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) sender {
    for (NSInteger i = 0; i < [[self _draggedTypes] count]; i++) {
        if ([[[sender draggingPasteboard] types]
                    containsObject: [[self _draggedTypes] objectAtIndex: i]])
            return [self _validateDraggedRow: sender];
    }
    return NSDragOperationNone;
}

- (void) draggingExited: (id<NSDraggingInfo>) sender {
    NS_EXTRA(NSTableView, self)->_draggingRow = -1;
    [self display];
}

- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) sender {
    NS_EXTRA(NSTableView, self)->_draggingRow = -1;
    [self display];
    return YES;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender {
    return [_dataSource tableView: self
                       acceptDrop: sender
                              row: [self _getDraggedRow: sender]
                    dropOperation: NSTableViewDropAbove];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ %0x08lx tableColumns: %@>",
                                       [self class], self, _tableColumns];
}

- (void) _moveUp: (BOOL) up extend: (BOOL) extend {

    NSInteger rowToSelect = -1;

    if ([NS_EXTRA(NSTableView, self)->_selectedRowIndexes count] == 0)
        rowToSelect = 0;
    else if (up) {
        NSInteger first = [NS_EXTRA(NSTableView, self)->_selectedRowIndexes firstIndex];
        if (first > 0)
            rowToSelect = first - 1;
        else if (!extend)
            rowToSelect = first;
    } else {
        NSInteger last = [NS_EXTRA(NSTableView, self)->_selectedRowIndexes lastIndex];
        if (last < [self numberOfRows] - 1)
            rowToSelect = last + 1;
        else if (!extend)
            rowToSelect = last;
    }

    if (rowToSelect != -1) {
        [self selectRow: rowToSelect byExtendingSelection: extend];
        [self scrollRowToVisible: rowToSelect];
    }
}

- (void) moveUp: sender {
    [self _moveUp: YES extend: NO];
}

- (void) moveUpAndModifySelection: sender {
    [self _moveUp: YES extend: YES];
}

- (void) moveDown: sender {
    [self _moveUp: NO extend: NO];
}

- (void) moveDownAndModifySelection: sender {
    [self _moveUp: NO extend: YES];
}

- (void)_writePersistentTableColumns {
    NSUnimplementedMethod();
}

- (void) registerNib: (NSNib *) nib forIdentifier: (NSString *) identifier {
    if (identifier == nil)
        return;
    if (nib != nil)
        [NS_EXTRA(NSTableView, self)->_registeredNibs setObject: nib forKey: identifier];
    else
        [NS_EXTRA(NSTableView, self)->_registeredNibs removeObjectForKey: identifier];
}

- (NSView *) viewAtColumn: (NSInteger) column row: (NSInteger) row makeIfNecessary: (BOOL) makeIfNecessary {
    if (column >= 0 && column < [_tableColumns count] &&
        [_delegate respondsToSelector: @selector(tableView:viewForTableColumn:row:)]) {
        NSTableColumn *col = [_tableColumns objectAtIndex: column];
        return [_delegate tableView: self viewForTableColumn: col row: row];
    }
    return nil;
}

// Creates the view from the nib registered for the identifier, owned by the
// given object. Returns nil when no nib is registered for it.
- (NSView *) makeViewWithIdentifier: (NSString *) identifier owner: (id) owner {
    NSNib *nib = identifier != nil ? [NS_EXTRA(NSTableView, self)->_registeredNibs objectForKey: identifier] : nil;
    NSArray *topLevelObjects = nil;

    if (nib == nil || ![nib instantiateWithOwner: owner topLevelObjects: &topLevelObjects])
        return nil;

    for (id object in topLevelObjects) {
        if ([object isKindOfClass: [NSView class]]) {
            if ([object identifier] == nil)
                [object setIdentifier: identifier];
            [NS_EXTRA(NSTableView, self)->_activeRowViews addObject: object];
            return object;
        }
    }
    return nil;
}

- (void)_readPersistentTableColumns {
    NSUnimplementedMethod();
}

@end

@implementation NSTableView (Bindings)

@end

@implementation NSTableView (NSTableViewStyle)

// Cocotron draws rows in the plain style only, so the style is stored purely so
// the getter round-trips a value set by a nib or a delegate. Deliberately does
// not reloadData: that notifies numberOfRows, driving a bound NSArrayController
// to re-apply a selection against rows it has not rebuilt, which raises.
- (NSTableViewStyle) style {
    return NS_EXTRA(NSTableView, self)->_style == NSTableViewStyleAutomatic ? NSTableViewStylePlain : NS_EXTRA(NSTableView, self)->_style;
}

- (void) setStyle: (NSTableViewStyle) style {
    NS_EXTRA(NSTableView, self)->_style = style;
}

// Private AppKit: the insets a table view style adds around its rows. Cocotron
// has only the plain style.
- (NSEdgeInsets) _styleContentInsets {
    return NSEdgeInsetsMake(0, 0, 0, 0);
}

@end
