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

// The row height of a new table view, as macOS 10.14.4 gives it (17 points;
// the intercell spacing is {3, 2}).
const CGFloat NSTableViewDefaultRowHeight = 17.0f;

@interface NSTableView (NSTableView_notifications)

- (BOOL) delegateShouldSelectTableColumn: (NSTableColumn *) tableColumn;
- (BOOL) delegateShouldSelectRow: (NSInteger) row;
- (BOOL) delegateShouldEditTableColumn: (NSTableColumn *) tableColumn
                                   row: (NSInteger) row;
- (BOOL) delegateSelectionShouldChange;
- (NSIndexSet *) _delegateFilteredSelection: (NSIndexSet *) proposed;
- (BOOL) _userSelectRowIndexes: (NSIndexSet *) indexes byExtendingSelection: (BOOL) extend;
- (void) _recycleAllCellViews;
- (void) _sizeColumnToFit: (NSInteger) columnIndex;
- (void) _moveColumn: (NSInteger) columnIndex toColumn: (NSInteger) newIndex notify: (BOOL) notify;
- (void) _noteColumnDidMoveFrom: (NSInteger) oldIndex to: (NSInteger) newIndex;
- (void) _recycleView: (NSView *) view;
- (void) _recycleCellViewsOutsideRows: (NSRange) rows;
- (NSView *) _cellViewAtColumn: (NSInteger) column row: (NSInteger) row make: (BOOL) make;
- (NSRect) _spacedFrameOfCellAtColumn: (NSInteger) column row: (NSInteger) row;
- (NSRect) _drawingFrameOfCellAtColumn: (NSInteger) column row: (NSInteger) row;
- (void) _setObjectValueOfCellView: (NSView *) view column: (NSTableColumn *) column row: (NSInteger) row;
- (BOOL) _delegateMakesCellViews;
- (NSView *) _delegateCellViewForTableColumn: (NSTableColumn *) column row: (NSInteger) row;
- (NSTableRowView *) _delegateRowViewForRow: (NSInteger) row;
- (void) _delegateDidAddRowView: (NSTableRowView *) rowView forRow: (NSInteger) row;
- (void) _delegateDidRemoveRowView: (NSTableRowView *) rowView forRow: (NSInteger) row;
- (NSTableRowView *) _rowViewForRow: (NSInteger) row make: (BOOL) make;
- (void) _removeRowViewsOutsideRows: (NSRange) rows;
- (BOOL) _typeSelectEvent: (NSEvent *) event;
- (void) _updateToolTipAreas;
- (void) noteSelectionIsChanging;
- (void) noteSelectionDidChange;
- (void) noteColumnDidResizeWithOldWidth: (CGFloat) oldWidth;
- (CGFloat) _spaceTakenByColumn: (NSTableColumn *) column;
- (BOOL) dataSourceCanSetObjectValue;
- (void) dataSourceSetObjectValue: object
                   forTableColumn: (NSTableColumn *) tableColumn
                              row: (NSInteger) row;

@end

@interface NSTableHeaderView (NSTableHeaderViewDefaultHeight)
+ (CGFloat) _defaultHeight;
@end

@implementation NSTableView

// Operated at once: the click that activates the window is delivered to it
// (see -[NSWindow sendEvent:]).
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

// The accessors are in the NSTableViewStyle category below.
@dynamic style;

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

// QUIRK: clickedRow and clickedColumn answer the click only while the click is being handled (the action and
// double action messages); the click's end puts both back to -1, and a table that has not been clicked reports -1
// too. Observed on macOS 26.7.3 (black-box, tier 2): the test below was run there and passes. The documentation of
// clickedRow and clickedColumn says they are meaningful in the action and double-action methods and does not say
// what they return afterwards.
// Test: test_clicked_row_and_column_are_reset_after_the_click in tests/appkit-table-click-beside-columns.m.
static void forgetClickedCell(NSTableView *table) {
    NS_EXTRA(NSTableView, table)->_clickedColumn = -1;
    NS_EXTRA(NSTableView, table)->_clickedRow = -1;
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];
    forgetClickedCell(self);

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        unsigned flags = [keyed decodeIntForKey: @"NSTvFlags"];

        NS_EXTRA(NSTableView, self)->_awaitingAwakeFromNib = YES;

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
        if ([keyed containsValueForKey: @"NSColumnAutoresizingStyle"])
            NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle = [keyed decodeIntForKey: @"NSColumnAutoresizingStyle"];
        else
            NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle = (flags & 0x00008000) ? NSTableViewUniformColumnAutoresizingStyle : NSTableViewLastColumnOnlyAutoresizingStyle;
        NS_EXTRA(NSTableView, self)->_allowsMultipleSelection = (flags & 0x08000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsEmptySelection = (flags & 0x10000000) ? YES : NO;
        NS_EXTRA(NSTableView, self)->_allowsColumnSelection = (flags & 0x04000000) ? YES : NO;
        _intercellSpacing = NSMakeSize(3.0, 2.0);
        NS_EXTRA(NSTableView, self)->_selectedRowIndexes = [[NSIndexSet alloc] init];
        NS_EXTRA(NSTableView, self)->_selectedColumns = [[NSMutableArray alloc] init];
        NS_EXTRA(NSTableView, self)->_registeredNibs = [[NSMutableDictionary alloc] init];
        // The cell views drawn into a view-based table in Interface Builder
        // are archived as one nib per view identifier, for
        // -makeViewWithIdentifier:owner: to make the views from, as if they
        // had been registered with -registerNib:forIdentifier:.
        // Test: tests/appkit-table-archived-cell-views.m
        id reusableViews = [keyed decodeObjectForKey: @"NSTableViewArchivedReusableViewsKey"];
        if ([reusableViews isKindOfClass: [NSDictionary class]]) {
            for (id identifier in reusableViews) {
                id nib = [reusableViews objectForKey: identifier];

                if ([identifier isKindOfClass: [NSString class]] && [nib isKindOfClass: [NSNib class]])
                    [NS_EXTRA(NSTableView, self)->_registeredNibs setObject: nib forKey: identifier];
            }
        }
        NS_EXTRA(NSTableView, self)->_cellViews = [[NSMutableDictionary alloc] init];
        NS_EXTRA(NSTableView, self)->_rowViews = [[NSMutableDictionary alloc] init];
        NS_EXTRA(NSTableView, self)->_reuseQueues = [[NSMutableDictionary alloc] init];
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
            NS_EXTRA(NSTableView, self)->_gridStyleMask = (NSTableViewGridLineStyle)[keyed decodeIntForKey: @"NSGridStyleMask"];
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
        NS_EXTRA(NSTableView, self)->_allowsTypeSelect = YES;
        NS_EXTRA(NSTableView, self)->_allowsColumnResizing = YES;
        NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

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
        NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle = (flags & 0x00008000) ? NSTableViewUniformColumnAutoresizingStyle : NSTableViewLastColumnOnlyAutoresizingStyle;
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
    forgetClickedCell(self);
    NS_EXTRA(NSTableView, self)->_rowHeightsCount = 0;
    NS_EXTRA(NSTableView, self)->_rowHeights = NULL;
    _standardRowHeight = NSTableViewDefaultRowHeight;
    _intercellSpacing = NSMakeSize(3.0, 2.0);
    NS_EXTRA(NSTableView, self)->_selectedRowIndexes = [[NSIndexSet alloc] init];
    NS_EXTRA(NSTableView, self)->_selectedColumns = [[NSMutableArray alloc] init];
    NS_EXTRA(NSTableView, self)->_registeredNibs = [[NSMutableDictionary alloc] init];
    NS_EXTRA(NSTableView, self)->_cellViews = [[NSMutableDictionary alloc] init];
    NS_EXTRA(NSTableView, self)->_rowViews = [[NSMutableDictionary alloc] init];
        NS_EXTRA(NSTableView, self)->_reuseQueues = [[NSMutableDictionary alloc] init];
    _editedColumn = -1;
    _editedRow = -1;
    NS_EXTRA(NSTableView, self)->_numberOfRows = -1;
    NS_EXTRA(NSTableView, self)->_draggingRow = -1;
    NS_EXTRA(NSTableView, self)->_draggingSourceMaskLocal = NSDragOperationEvery;
    NS_EXTRA(NSTableView, self)->_draggingSourceMaskNonLocal = NSDragOperationNone;

    NS_EXTRA(NSTableView, self)->_allowsColumnReordering = YES;
    NS_EXTRA(NSTableView, self)->_allowsTypeSelect = YES;
    NS_EXTRA(NSTableView, self)->_allowsColumnResizing = YES;
    NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NS_EXTRA(NSTableView, self)->_allowsMultipleSelection = NO;
    NS_EXTRA(NSTableView, self)->_allowsEmptySelection = YES;
    NS_EXTRA(NSTableView, self)->_allowsColumnSelection = YES;

    // The default header height is a QUIRK, see +[NSTableHeaderView _defaultHeight].
    _headerView = [[NSTableHeaderView alloc]
            initWithFrame: NSMakeRect(0, 0, [self bounds].size.width, [NSTableHeaderView _defaultHeight])];
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
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    NSZoneFree(NULL, NS_EXTRA(NSTableView, self)->_rowHeights);
    [_headerView release];
    [_cornerView release];
    [_tableColumns release];
    [_backgroundColor release];
    [_gridColor release];
    [NS_EXTRA(NSTableView, self)->_selectedRowIndexes release];
    [NS_EXTRA(NSTableView, self)->_draggedRows release];
    [NS_EXTRA(NSTableView, self)->_selectedColumns release];
    [NS_EXTRA(NSTableView, self)->_sortDescriptors release];
    [NS_EXTRA(NSTableView, self)->_registeredNibs release];
    [NS_EXTRA(NSTableView, self)->_cellViews release];
    [NS_EXTRA(NSTableView, self)->_rowViews release];
    [NS_EXTRA(NSTableView, self)->_reuseQueues release];
    [NS_EXTRA(NSTableView, self)->_typeSelectString release];
    [NS_EXTRA(NSTableView, self)->_toolTipSignature release];
    [NS_EXTRA(NSTableView, self)->_indicatorImages release];
    [NS_EXTRA(NSTableView, self)->_autosaveName release];
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

// QUIRK: in a scroll view with overlay scrollers a table view has no corner
// view of its own: the default corner view comes back when the scroller style
// changes to legacy, and a corner view the application set is kept. Not
// documented. Evidence: black-box observation on macOS 10.14.4 and 26.7.3
// (tier 2), probes mac-probes/aqua-metric-followups.m and -2.m of the research
// notes. Test: appkit-table-default-metrics.m (test_quirk_corner_view_overlay)
- (NSView *) cornerView {
    if ([_cornerView isMemberOfClass: [NSTableCornerView class]] &&
        [[self enclosingScrollView] scrollerStyle] == NSScrollerStyleOverlay)
        return nil;
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
    return NS_EXTRA(NSTableView, self)->_autosaveName;
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

// The deprecated flag maps onto the style: YES is uniform autoresizing, NO the
// last-column-only style, and reading it reports YES for the uniform and the
// two sequential styles.
- (BOOL) autoresizesAllColumnsToFit {
    switch (NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle) {
    case NSTableViewUniformColumnAutoresizingStyle:
    case NSTableViewSequentialColumnAutoresizingStyle:
    case NSTableViewReverseSequentialColumnAutoresizingStyle:
        return YES;
    default:
        return NO;
    }
}

- (NSTableViewColumnAutoresizingStyle) columnAutoresizingStyle {
    return NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle;
}

- (void) setColumnAutoresizingStyle: (NSTableViewColumnAutoresizingStyle) style {
    // An out-of-range style is ignored
    if (style > NSTableViewFirstColumnOnlyAutoresizingStyle)
        return;
    NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle = style;
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
    return NS_EXTRA(NSTableView, self)->_autosaveTableColumns;
}

// row background and grid attributes for OS X >= 10.3
- (BOOL) usesAlternatingRowBackgroundColors {
    return NS_EXTRA(NSTableView, self)->_alternatingRowBackground;
}

- (NSTableViewGridLineStyle) gridStyleMask {
    return NS_EXTRA(NSTableView, self)->_gridStyleMask;
}

// The data source must answer numberOfRowsInTableView: unless the table gets
// its rows from a content binding. A data source that does not is reported
// once, when it is set, or, for one a nib sets, on the first -numberOfRows
// after the nib is loaded, by which time the nib's bindings are made.
// Observed on macOS 26.7.3 and Mac OS X 10.14.4 (tests/appkit-table-data-source-check.m).
- (void) _checkDataSource {
    NS_EXTRA(NSTableView, self)->_dataSourceCheckPending = NO;
    if (_dataSource == nil || [self _binderForBinding: @"content"] != nil ||
        [_dataSource respondsToSelector: @selector(numberOfRowsInTableView:)])
        return;
    NSLog(@"*** Illegal NSTableView data source (%@).  Must implement "
          @"numberOfRowsInTableView: and tableView:objectValueForTableColumn:row:",
          _dataSource);
}

- (void) awakeFromNib {
    [super awakeFromNib];
    NS_EXTRA(NSTableView, self)->_awaitingAwakeFromNib = NO;
}

- (NSInteger) numberOfRows {
    if (NS_EXTRA(NSTableView, self)->_dataSourceCheckPending && !NS_EXTRA(NSTableView, self)->_awaitingAwakeFromNib)
        [self _checkDataSource];

    if (NS_EXTRA(NSTableView, self)->_numberOfRows < 0) {
        id binding = [self _binderForBinding: @"content"];

        if (binding)
            NS_EXTRA(NSTableView, self)->_numberOfRows = [binding numberOfRows];

        if (NS_EXTRA(NSTableView, self)->_numberOfRows < 0) {
            if (_dataSource == nil)
                NS_EXTRA(NSTableView, self)->_numberOfRows = 0;
            else if ([_dataSource respondsToSelector: @selector(numberOfRowsInTableView:)])
                NS_EXTRA(NSTableView, self)->_numberOfRows = [_dataSource numberOfRowsInTableView: self];
            else
                NS_EXTRA(NSTableView, self)->_numberOfRows = 0;
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

// The width a column takes in the table and its header, with its share of the intercell spacing.
// Observed on macOS 26.7.3 (black-box test, pinned by tests/appkit-table-hidden-columns.m): a hidden column takes no width at all, spacing included; the documentation of isHidden says only
// that the column stays in tableColumns and in the count.
- (CGFloat) _spaceTakenByColumn: (NSTableColumn *) column {
    return [column isHidden] ? 0. : [column width] + _intercellSpacing.width;
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
        rect.size.width += [self _spaceTakenByColumn: [_tableColumns objectAtIndex: i]];
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

    // QUIRK: the rectangle of a hidden column is NSZeroRect, wherever the column is in the table: its y and
    // height are 0 as well, not the height of the shown columns; the documentation of isHidden and of
    // rectOfColumn: does not say. Observed on macOS 26.1 (arm64), 5 columns of 50 to 90 points: probe 657.R
    // "hidden=4 ... column 4 -> HIDDEN ; rectOfColumn:={{0,0},{0,0}}" (the same for the hidden columns 0, 2,
    // and 1 and 3), while a shown column gave "rectOfColumn:={{10,0},{65,172}}". The earlier observations (macOS
    // 26.7.3, 10.14.4, probe 657.1) printed x and width only. The header rect of a hidden column keeps the
    // header's height (probe 657.R "headerRectOfColumn:={{0,0},{0,28}}").
    // Test: tests/appkit-table-hidden-columns.m (test_rects_close_the_gap)
    if ([[_tableColumns objectAtIndex: column] isHidden])
        return NSZeroRect;

    rect.origin.x = 0.;
    for (i = 0; i < column; i++)
        rect.origin.x += [self _spaceTakenByColumn: [_tableColumns objectAtIndex: i]];
    rect.origin.y = 0.;

    rect.size.width = [self _spaceTakenByColumn: [_tableColumns objectAtIndex: column]];
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

// The columns that the rect touches, as one range: it starts at the first column that is not hidden and ends
// beyond the rect's right edge, and so may hold hidden columns between its ends.
// QUIRK: a rect that reaches past the last shown column gets a range that runs to the last column, hidden
// columns after the last shown one included; the documentation does not mention hidden columns. Observed on
// macOS 26.1 (arm64) with 5 columns, column 4 hidden and the rect covering the table: the range was 0..4
// (probe 657.1 "hidden=4 ... columnsInRect(full)=0..4"; "hidden=0,4 ... =1..4"; "hidden=all but 2 ... =2..4"),
// while a rect ending inside a shown column stopped at it (probe 657.2 "hidden=4 ... x120+150:1..3").
// Test: tests/appkit-table-hidden-columns.m (test_ranges_over_whole_rects)
- (NSRange) columnsInRect: (NSRect) rect {
    NSInteger numberOfColumns = [self numberOfColumns];
    NSInteger i, first = -1, last = -1;
    CGFloat right = 0.;

    for (i = 0; i < numberOfColumns; i++) {
        NSTableColumn *column = [_tableColumns objectAtIndex: i];

        right += [self _spaceTakenByColumn: column];
        if ([column isHidden])
            continue;
        if (first < 0) {
            if (right <= rect.origin.x)
                continue;
            first = i;
        }
        last = i;
        if (right > rect.origin.x + rect.size.width)
            break;
    }

    if (first < 0)
        return NSMakeRange(0, 0); // returns 0,0 if not found, not NSNotFound
    if (i == numberOfColumns)
        last = numberOfColumns - 1;
    return NSMakeRange(first, last - first + 1);
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

// The rectangle of the column and row, including the intercell spacing.
- (NSRect) _spacedFrameOfCellAtColumn: (NSInteger) column row: (NSInteger) row {
    NSRect frame;
    NSInteger i;

    if (column < 0 || column >= [self numberOfColumns] || row < 0 ||
        row >= [self numberOfRows])
        return NSZeroRect;

    // QUIRK: NSZeroRect for a hidden column, as in -rectOfColumn: (not x 0 and width 0 with the row's y and
    // height). Observed on macOS 26.1 (arm64): probe 657.R "hidden=2 ... column 2 -> HIDDEN ;
    // frameOfCellAtColumn:row:1={{0,0},{0,0}} ; frameOfCellAtColumn:row:0={{0,0},{0,0}}" while the shown
    // cells of the same table gave "row:1={{16,29},{50,24}}".
    if ([[_tableColumns objectAtIndex: column] isHidden])
        return NSZeroRect;

    frame.origin.x = 0.;
    for (i = 0; i < column; i++)
        frame.origin.x += [self _spaceTakenByColumn: [_tableColumns objectAtIndex: i]];

    frame.origin.y = 0.;
    for (i = 0; i < row; i++)
        frame.origin.y += rowHeightAtIndex(self, i) + _intercellSpacing.height;

    frame.size.width = [self _spaceTakenByColumn: [_tableColumns objectAtIndex: column]];
    frame.size.height = rowHeightAtIndex(self, row) + _intercellSpacing.height;

    return frame;
}

// What the cells draw and edit in: the rectangle of the column and row with the spacing, which is how the
// table view drew cells before frameOfCellAtColumn:row: followed the platform's frame, the cell's alone.
- (NSRect) _drawingFrameOfCellAtColumn: (NSInteger) column row: (NSInteger) row {
    return [self _spacedFrameOfCellAtColumn: column row: row];
}

// The frame of the cell without the intercell spacing: the column's width and the row's height, placed
// half the spacing (rounded down) in from the corner of the rectangle of the column and the row.
// Black-box observation of the frame on macOS 10.14.4 and 26.7.3, for the cells of table and outline views
// alike (with the default style on 10.14.4, which is the plain one on later systems).
// Test: tests/appkit-table-cell-frames.m
- (NSRect) frameOfCellAtColumn: (NSInteger) column row: (NSInteger) row {
    NSRect frame = [self _spacedFrameOfCellAtColumn: column row: row];

    if (NSIsEmptyRect(frame) || NSWidth(frame) <= 0)
        return frame; // also the empty frame of a hidden column
    CGFloat insetX = floor(_intercellSpacing.width / 2), insetY = floor(_intercellSpacing.height / 2);

    frame.origin.x += insetX;
    frame.origin.y += insetY;
    frame.size.width -= _intercellSpacing.width;
    frame.size.height -= _intercellSpacing.height;
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
    if (NS_EXTRA(NSTableView, self)->_awaitingAwakeFromNib)
        NS_EXTRA(NSTableView, self)->_dataSourceCheckPending = YES;
    else
        [self _checkDataSource];
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

// The name is kept and returned. Saving and restoring the columns under it is not done.
- (void) setAutosaveName: (NSString *) name {
    name = [name copy];
    [NS_EXTRA(NSTableView, self)->_autosaveName release];
    NS_EXTRA(NSTableView, self)->_autosaveName = name;
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
    [self setColumnAutoresizingStyle: flag ? NSTableViewUniformColumnAutoresizingStyle : NSTableViewLastColumnOnlyAutoresizingStyle];
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
    NS_EXTRA(NSTableView, self)->_autosaveTableColumns = flag;
}

// row background and grid attributes for OS X >= 10.3
- (void) setUsesAlternatingRowBackgroundColors: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_alternatingRowBackground = flag;
}

- (void) setGridStyleMask: (NSTableViewGridLineStyle) gridStyle {
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
    [self _moveColumn: columnIndex toColumn: newIndex notify: YES];
}

- (void) _moveColumn: (NSInteger) columnIndex toColumn: (NSInteger) newIndex notify: (BOOL) notify {
    NSInteger count = [_tableColumns count];

    if (columnIndex < 0 || columnIndex >= count || newIndex < 0 || newIndex >= count)
        [NSException raise: NSRangeException
                    format: @"moveColumn:toColumn: index out of range (valid are 0 to %ld)", (long) count - 1];
    if (columnIndex == newIndex)
        return;

    NSTableColumn *column = [[_tableColumns objectAtIndex: columnIndex] retain];

    [_tableColumns removeObjectAtIndex: columnIndex];
    [_tableColumns insertObject: column atIndex: newIndex];
    [column release];

    // The views of a view-based table sit at their columns' positions
    [self _recycleAllCellViews];
    [self setNeedsDisplay: YES];
    [_headerView setNeedsDisplay: YES];
    if (notify)
        [self _noteColumnDidMoveFrom: columnIndex to: newIndex];
}

- (void) _noteColumnDidMoveFrom: (NSInteger) oldIndex to: (NSInteger) newIndex {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSTableViewColumnDidMoveNotification
                          object: self
                        userInfo: [NSDictionary
                                          dictionaryWithObjectsAndKeys:
                                                  [NSNumber numberWithInteger: oldIndex], @"NSOldColumn",
                                                  [NSNumber numberWithInteger: newIndex], @"NSNewColumn", nil]];
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
    if ([self _delegateMakesCellViews])
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
        [self _finishEditingWithTextMovement: NSIllegalTextMovement];

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
    NS_EXTRA(NSTableView, self)->_editingFrame = NS_EXTRA(NSTableView, self)->_editingBorder = [self _drawingFrameOfCellAtColumn: column
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
        NSArray *old = [NS_EXTRA(NSTableView, self)->_sortDescriptors autorelease];
        NS_EXTRA(NSTableView, self)->_sortDescriptors = [value copy];
        // The data source hears of every change, whether the user clicked a
        // column header or the sort descriptors were set programmatically.
        if ([_dataSource respondsToSelector: @selector(tableView:sortDescriptorsDidChange:)])
            [_dataSource tableView: self sortDescriptorsDidChange: old != nil ? old : [NSArray array]];
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

    for (NSNumber *key in NS_EXTRA(NSTableView, self)->_rowViews)
        [[NS_EXTRA(NSTableView, self)->_rowViews objectForKey: key]
                setSelected: [NS_EXTRA(NSTableView, self)->_selectedRowIndexes containsIndex: [key integerValue]]];

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
                    [self _finishEditingWithTextMovement: NSIllegalTextMovement];

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

// Hidden columns are left out of the set: https://developer.apple.com/documentation/appkit/nstableview/columnindexes(in:)
// says columns that are hidden are not included, unlike the range columnsInRect: gives.
- (NSIndexSet *) columnIndexesInRect: (NSRect) rect {
    NSRange range = [self columnsInRect: rect];
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    NSUInteger i;

    for (i = range.location; i < NSMaxRange(range); i++)
        if (![[_tableColumns objectAtIndex: i] isHidden])
            [result addIndex: i];
    return result;
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

    [self _recycleCellViewsOutsideRows: NSMakeRange(0, numberOfRows)];

    // There isn't much point in trying to validate the heights of
    // visible rows only, as the often used -rectOfColumn: needs them all.
    [self noteHeightOfRowsWithIndexesChanged:
                    [NSIndexSet
                            indexSetWithIndexesInRange: NSMakeRange(
                                                                0,
                                                                numberOfRows)]];

    // if there's any editing going on, we'd better stop it.
    if (_editingCell != nil)
        [self _finishEditingWithTextMovement: NSIllegalTextMovement];

    if (numberOfRows > 0) {
        size.width = [self rectOfRow: 0].size.width;
    }
    // The height of the rows, as -rectOfColumn: gives it for a shown column; not read from the rectangle of
    // column 0, which is NSZeroRect when that column is hidden.
    if ([_tableColumns count] > 0)
        size.height = MAX(numberOfRows > 0 ? NSMaxY([self rectOfRow: numberOfRows - 1]) : 0.,
                          [[self superview] bounds].size.height);

    // The table is at least as wide and as tall as its clip view, whatever its columns and rows add up to: observed
    // on macOS 26.7.3, where after -reloadData a table of 4 rows and 296 points of columns in a 400 by 300 point
    // clip view is 400 by 300 points, so that a click beside the columns or below the rows still reaches the table.
    // Test: appkit-table-click-beside-columns.
    if ([[self superview] isKindOfClass: [NSClipView class]]) {
        NSSize clipSize = [[self superview] bounds].size;
        size.width = MAX(size.width, clipSize.width);
        size.height = MAX(size.height, clipSize.height);
    }

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
    [self _recycleAllCellViews];
    [self noteNumberOfRowsChanged];
    [self setNeedsDisplay: YES];
    [_headerView setNeedsDisplay: YES];
}

- (void) reloadDataForRowIndexes: (NSIndexSet *) rowIndexes
                   columnIndexes: (NSIndexSet *) columnIndexes
{
    // View-based tables ask for the views of the reloaded cells again
    NSMutableDictionary *views = NS_EXTRA(NSTableView, self)->_cellViews;

    for (NSNumber *key in [views allKeys]) {
        unsigned long long value = [key unsignedLongLongValue];
        NSInteger row = (NSInteger) (value >> 24);
        NSInteger column = (NSInteger) (value & 0xFFFFFF);

        if (![rowIndexes containsIndex: row])
            continue;
        // A group row's view spans the columns: any reloaded column reloads it
        if (column != 0xFFFFFF && ![columnIndexes containsIndex: column])
            continue;
        [self _recycleView: [views objectForKey: key]];
        [views removeObjectForKey: key];
    }
    [self setNeedsDisplay: YES];
}

- (void) tile {
    NSRect rect;

    // Laying the table out leaves the column widths alone, whatever the
    // autoresizing style; only a change of the clip view's width, or
    // sizeLastColumnToFit and sizeToFit, resize columns (macOS 10.14.4). The
    // table is at least as wide as its clip view.
    [self noteNumberOfRowsChanged];
    if ([[self superview] isKindOfClass: [NSClipView class]] &&
        NSWidth([self frame]) < NSWidth([[self superview] bounds]))
        [self setFrameSize: NSMakeSize(NSWidth([[self superview] bounds]), NSHeight([self frame]))];
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
        NSTableColumn *lastColumn = nil;
        CGFloat lastWidth = size.width;

        // Observed on macOS 26.7.3: the column that takes the slack is the last one that is not hidden
        for (i = 0; i < count; ++i) {
            NSTableColumn *column = [_tableColumns objectAtIndex: i];

            if ([column isHidden])
                continue;
            lastWidth -= [self _spaceTakenByColumn: column];
            lastColumn = column;
        }
        if (lastColumn == nil)
            return;

        // What the others leave goes to the last column, which stops at its minimum width.
        lastWidth += [lastColumn width];
        [lastColumn setWidth: MAX(lastWidth, [lastColumn minWidth])];

        [self setNeedsDisplay: YES];
    }
}

// The selection is emphasized (drawn with the alternate selected colours) while the table's
// window is the key window and the table is its first responder; otherwise it is drawn in
// the secondary, grey colours.
- (BOOL) _selectionIsEmphasized {
    NSWindow *window = [self window];
    id responder = [window firstResponder];

    if (![window isKeyWindow] || responder == nil)
        return NO;
    if (responder == self)
        return YES;
    // A field editor of this table (editing a cell) keeps the selection emphasized
    return [responder isKindOfClass: [NSText class]] && [(NSText *) responder delegate] == self;
}

- (NSColor *) _selectionHighlightColor {
    return [self _selectionIsEmphasized] ? [NSColor alternateSelectedControlColor]
                                         : [NSColor secondarySelectedControlColor];
}

- (void) _keyStateChanged: (NSNotification *) note {
    [self setNeedsDisplay: YES];
}

// A click makes the table the first responder (NSControl answers with the selectability of its cell, which a table
// does not have).
- (BOOL) needsPanelToBecomeKey {
    return YES;
}

- (BOOL) becomeFirstResponder {
    [self setNeedsDisplay: YES];
    return [super becomeFirstResponder];
}

// A table gives way to the field editor of the cell it edits. NSControl checks its selected cell while it has an
// editor; a table's editor belongs to the cell being edited (test: appkit-tableview-edit-column.m).
- (BOOL) resignFirstResponder {
    [self setNeedsDisplay: YES];
    if (NS_EXTRA(NSControl, self)->_currentEditor != nil)
        return _editingCell == nil || [_editingCell hasValidObjectValue];
    return [super resignFirstResponder];
}

- (void) drawHighlightedSelectionForColumn: (NSInteger) column
                                       row: (NSInteger) row
                                    inRect: (NSRect) rect
{
    [[self _selectionHighlightColor] setFill];
    NSRectFill(rect);
}

- (void) highlightSelectionInClipRect: (NSRect) rect {
    NSInteger row, column;
    NSInteger numberOfRows = [self numberOfRows];

    if ([self selectionHighlightStyle] == NSTableViewSelectionHighlightStyleNone)
        return;

    for (column = 0; column < [_tableColumns count]; ++column)
        for (row = 0; row < numberOfRows; ++row)
            if ([self isColumnSelected: column] || [self isRowSelected: row])
                if (!(row == _editedRow && column == _editedColumn))
                    [self drawHighlightedSelectionForColumn: column
                                                        row: row
                                                     inRect: [self _drawingFrameOfCellAtColumn:
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
        // A selected row keeps the normal text colour while its highlight is the grey, secondary one
        // (selectedTextColor is the colour of selected text in a text view, not of a selected row).
        if ([self isRowSelected: row] ||
            [self isColumnSelected: columnNumber]) {
            [(NSTextFieldCell *) dataCell
                    setDrawsBackground: NO]; // so the selection shows properly,
                                             // dont just set the color so
                                             // custom background works
            [(NSTextFieldCell *) dataCell
                    setTextColor: ([self selectionHighlightStyle] !=
                                           NSTableViewSelectionHighlightStyleNone &&
                                   [self _selectionIsEmphasized])
                                          ? [NSColor alternateSelectedControlTextColor]
                                          : [NSColor textColor]];
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
    if ([self _delegateMakesCellViews]) {
        NSRange visibleColumns = [self columnsInRect: clipRect];
        NSInteger drawThisColumn = visibleColumns.location;

        if ([self isRowSelected: row] &&
            [self selectionHighlightStyle] != NSTableViewSelectionHighlightStyleNone) {
            [[self _selectionHighlightColor] setFill];
            NSRectFill([self rectOfRow: row]);
        }

        if ([self _isGroupRow: row]) {
            // A group row is one view over the whole row, asked for without a column
            NSView *groupView = [self _cellViewAtColumn: 0 row: row make: YES];

            if (groupView != nil) {
                [groupView setHidden: NO];
                [groupView displayRectIgnoringOpacity: [groupView bounds]];
            }
            return;
        }

        for (; drawThisColumn < NSMaxRange(visibleColumns); drawThisColumn++) {
            if ([[_tableColumns objectAtIndex: drawThisColumn] isHidden])
                continue;

            NSView *cellView = [self _cellViewAtColumn: drawThisColumn row: row make: YES];

            if (cellView != nil) {
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
        if ([[_tableColumns objectAtIndex: drawThisColumn] isHidden])
            continue;

        if (row == _editedRow && drawThisColumn == _editedColumn &&
            _editingCell != nil) {
            [_backgroundColor setFill];
            NSRectFill(NS_EXTRA(NSTableView, self)->_editingBorder);
            [_editingCell setControlView: self];
            [_editingCell drawWithFrame: NS_EXTRA(NSTableView, self)->_editingFrame inView: self];
            if ([_editingCell focusRingType] != NSFocusRingTypeNone) {
                [NSGraphicsContext saveGraphicsState];
                NSSetFocusRingStyle(NSFocusRingOnly);
                NSRectFill(NS_EXTRA(NSTableView, self)->_editingBorder);
                [NSGraphicsContext restoreGraphicsState];
            }
        } else {
            NSCell *dataCell = [self preparedCellAtColumn: drawThisColumn
                                                      row: row];
            NSRect cellRect = [self
                    _adjustedFrame: [self _drawingFrameOfCellAtColumn: drawThisColumn
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
        NSInteger numberOfRows = [self numberOfRows];
        NSRange rangeOfRows = [self rowsInRect: clipRect];
        NSInteger i;

        for (i = rangeOfRows.location; i < NSMaxRange(rangeOfRows); i++) {
            NSRect rectToFill = [self rectOfRow: i];

            rectToFill.origin.x = clipRect.origin.x;
            rectToFill.size.width = clipRect.size.width;
            [(NSColor *) [rowColors objectAtIndex: i % colorCount] setFill];
            NSRectFill(NSIntersectionRect(rectToFill, clipRect));
        }

        // The stripes carry on below the last row at the height of a row, the colors
        // continuing in sequence with the rows
        CGFloat pitch = numberOfRows > 0 ? [self rectOfRow: 0].size.height
                                         : [self _effectiveRowHeight] + _intercellSpacing.height;
        if (pitch > 0.) {
            CGFloat y = numberOfRows > 0 ? NSMaxY([self rectOfRow: numberOfRows - 1]) : 0.;
            NSInteger index = numberOfRows;

            if (NSMinY(clipRect) > y) {
                NSInteger skipped = (NSInteger) floor((NSMinY(clipRect) - y) / pitch);
                y += skipped * pitch;
                index += skipped;
            }
            for (; y < NSMaxY(clipRect); y += pitch, index++) {
                NSRect rectToFill = NSMakeRect(clipRect.origin.x, y, clipRect.size.width, pitch);

                [(NSColor *) [rowColors objectAtIndex: index % colorCount] setFill];
                NSRectFill(NSIntersectionRect(rectToFill, clipRect));
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
            if ([[_tableColumns objectAtIndex: i] isHidden])
                continue;

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
        result += [self _spaceTakenByColumn: [_tableColumns objectAtIndex: i]];

    return result;
}

// The columns that take room in the table, in order. Observed on macOS 26.7.3: the autoresizing styles leave the hidden ones alone.
- (NSArray *) _shownTableColumns {
    NSMutableArray *shown = [NSMutableArray arrayWithCapacity: [_tableColumns count]];

    for (NSTableColumn *column in _tableColumns)
        if (![column isHidden])
            [shown addObject: column];
    return shown;
}

// Moves the width the columns miss (or exceed) relative to the clip view onto
// the columns the autoresizing style names. Columns stop at their minimum and
// maximum widths, and what a column cannot absorb passes to the next one.
- (void) _autoresizeColumnsToFitClipView {
    NSTableViewColumnAutoresizingStyle style = NS_EXTRA(NSTableView, self)->_columnAutoresizingStyle;
    NSArray *shown = [self _shownTableColumns];
    NSInteger count = [shown count];

    if (count == 0 || ![[self superview] isKindOfClass: [NSClipView class]])
        return;

    switch (style) {
    case NSTableViewNoColumnAutoresizing:
        return;

    case NSTableViewLastColumnOnlyAutoresizingStyle:
        [self sizeLastColumnToFit];
        return;

    default:
        break;
    }

    CGFloat delta = [[self superview] bounds].size.width - [self _displayWidthOfColumns];
    NSInteger i;

    if (style == NSTableViewUniformColumnAutoresizingStyle) {
        [self _resizeColumnsUniformlyBy: delta];
    } else {
        // Sequential runs from the last column towards the first, the reverse
        // style from the first towards the last, and the first-column style
        // touches the first column only.
        BOOL fromLast = style == NSTableViewSequentialColumnAutoresizingStyle;
        NSInteger visits = style == NSTableViewFirstColumnOnlyAutoresizingStyle ? 1 : count;

        for (i = 0; i < visits && fabs(delta) >= 0.5; ++i) {
            NSTableColumn *column = [shown objectAtIndex: fromLast ? count - 1 - i : i];
            CGFloat before = [column width];

            [column setWidth: before + delta];
            delta -= [column width] - before;
        }
    }
    [self setNeedsDisplay: YES];
}

// Spreads delta over the shown columns in whole points. A round gives each column in turn the share delta / count
// rounded to the nearest point (a column takes no more than what is left of delta), the last columns getting
// less, and a column that reaches its minimum or maximum width takes no more in the next rounds; the part it
// could not take is spread the same way over the columns that did take their share, until delta is used up, so
// the widths change by exactly delta as long as some column has room. When the share rounds to nothing the
// points left go one each to the first columns.
// QUIRK: the documentation of NSTableViewUniformColumnAutoresizingStyle gives the equal distribution of the
// space among all columns and nothing about limits or whole points. Evidence: black-box observation on macOS
// 26.7.3 and 10.14.4 (tier 2, x86_64 and i386, mac-probes p790; the contributor's probe on 26.1 gave the same
// structure): five columns of 50, 60, 70, 80 and 240 points (minimum width 20), the clip view 200 narrower:
// 20 20 26 37 197; 203 narrower: 20 20 25 36 196; 100 narrower: 30 40 50 60 220; 307 narrower: 20 20 20 20 113;
// five columns of 50 to 90 (maximum width 100) 103 wider: 75 84 94 100 100, with maximum width 1000:
// 71 81 91 101 109; 53 narrower: 39 49 59 69 81.
// Test: tests/appkit-table-column-autoresizing.m
- (void) _resizeColumnsUniformlyBy: (CGFloat) delta {
    NSMutableArray *columns = [[[self _shownTableColumns] mutableCopy] autorelease];

    while ([columns count] > 0 && fabs(delta) >= 1) {
        CGFloat sign = delta > 0 ? 1 : -1;
        CGFloat share = round(delta / [columns count]);
        NSMutableArray *remaining = [NSMutableArray arrayWithCapacity: [columns count]];

        if (share == 0)
            share = sign;
        for (NSTableColumn *column in columns) {
            if (fabs(delta) < 1)
                break;

            CGFloat before = [column width];
            CGFloat wanted = before + (fabs(share) < fabs(delta) ? share : delta);

            [column setWidth: wanted];
            delta -= [column width] - before;
            if ([column width] == wanted)
                [remaining addObject: column];
        }
        columns = remaining;
    }
}

// QUIRK: when the clip view changes width, the autoresizing style resizes the
// columns only if they did not fit the new width (it shrinks) or exactly
// filled the old width (it grows); columns narrower than the clip view keep
// their widths while it grows. Not documented. Evidence: black-box observation
// on macOS 10.14.4 (tier 2), probes mac-probes/aqua-metric-followups.m and -2.m
// of the research notes; macOS 26.7.3 also widens columns that leave space, we
// follow 10.14. Test: appkit-table-default-metrics.m
// (test_quirk_autoresizing_with_space_left)
- (void) resizeWithOldSuperviewSize: (NSSize) oldSize {
    NSSize size = [self frame].size;
    CGFloat newWidth = [[self superview] bounds].size.width;
    CGFloat columnsWidth = [self _displayWidthOfColumns];
    BOOL overflows = columnsWidth > newWidth + 0.5;
    BOOL filled = fabs(columnsWidth - oldSize.width) < 0.5;

    if (size.width < newWidth) {
        size.width = newWidth;
        [self setFrameSize: size];
    }

    if ((newWidth < oldSize.width && overflows) || (newWidth > oldSize.width && filled))
        [self _autoresizeColumnsToFitClipView];
    [self tile];
}

// The table extends at least over the visible height of its clip view, so that
// the alternating row backgrounds continue below the last row. The scroll view has
// laid out its clip view by the time the table reaches a window.
- (void) viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSWindowDidBecomeKeyNotification
                                                  object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: NSWindowDidResignKeyNotification
                                                  object: nil];
    if ([self window] != nil) {
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(_keyStateChanged:)
                                                     name: NSWindowDidBecomeKeyNotification
                                                   object: [self window]];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(_keyStateChanged:)
                                                     name: NSWindowDidResignKeyNotification
                                                   object: [self window]];
    }
    if ([self window] != nil && [[self superview] isKindOfClass: [NSClipView class]])
        [self noteNumberOfRowsChanged];
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
    [self _finishEditingWithTextMovement:
                  [[[note userInfo] objectForKey: @"NSTextMovement"] intValue]];
}

// Commits and ends the current cell edit. Internal callers that stop an edit
// (row changes, reloads, clicks outside the rows) use this directly instead of
// synthesizing a notification.
- (void) _finishEditingWithTextMovement: (NSInteger) textMovement {
    NSTableColumn *editedColumn = [_tableColumns objectAtIndex: _editedColumn];
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

    if ([self _delegateMakesCellViews]) {
        // Views of rows that are no longer visible leave the table for the reuse queue
        [self _recycleCellViewsOutsideRows: [self rowsInRect: [self visibleRect]]];
    } else if ([_delegate respondsToSelector: @selector(tableView:toolTipForCell:rect:tableColumn:row:mouseLocation:)]) {
        [self _updateToolTipAreas];
    }

    if ([self drawsGrid])
        [self drawGridInClipRect: clipRect];

    NSInteger dropRow = [self _dropIndicatorRow];
    if (NS_EXTRA(NSTableView, self)->_draggingTargetShown && [self _dropIndicatorIsOn]) {
        // GUESS: the highlight of a drop on a row, or on the whole table (row -1), is an outline
        NSRect target = dropRow < 0 ? [self visibleRect]
                      : NSIntersectionRect([self rectOfRow: dropRow], [self visibleRect]);
        [[NSColor blackColor] setStroke];
        [NSBezierPath strokeRect: NSInsetRect(target, 1.0, 1.0)];
    } else if (NS_EXTRA(NSTableView, self)->_draggingTargetShown && dropRow >= 0) {
        NSRect rowRect;
        [[NSColor blackColor] setStroke];
        if ([self numberOfRows] == 0)
            [NSBezierPath
                    strokeLineFromPoint: NSMakePoint(0, 0)
                                toPoint: NSMakePoint([self bounds].size.width,
                                                     0)];
        else {
            if (dropRow == [self numberOfRows]) {
                rowRect = NSIntersectionRect([self rectOfRow: dropRow - 1],
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
                rowRect = NSIntersectionRect([self rectOfRow: dropRow],
                                             [self visibleRect]);
                [NSBezierPath
                        strokeLineFromPoint: NSMakePoint(0, rowRect.origin.y)
                                    toPoint: NSMakePoint(rowRect.size.width,
                                                         rowRect.origin.y)];
            }
        }
    }
}

// Selection changes the user makes (clicks, arrow keys, type select) go through
// the delegate. tableView:selectionIndexesForProposedSelection: takes
// precedence; without it tableView:shouldSelectRow: is asked for each proposed
// row. Programmatic changes (selectRowIndexes:byExtendingSelection:) are not
// subject to the delegate.
- (NSIndexSet *) _delegateFilteredSelection: (NSIndexSet *) proposed {
    if ([_delegate respondsToSelector: @selector(tableView:selectionIndexesForProposedSelection:)]) {
        NSIndexSet *result = [_delegate tableView: self selectionIndexesForProposedSelection: proposed];

        return result != nil ? result : [NSIndexSet indexSet];
    }

    if ([_delegate respondsToSelector: @selector(tableView:shouldSelectRow:)]) {
        NSMutableIndexSet *allowed = [[proposed mutableCopy] autorelease];

        for (NSUInteger row = [proposed firstIndex]; row != NSNotFound; row = [proposed indexGreaterThanIndex: row]) {
            if (![_delegate tableView: self shouldSelectRow: row])
                [allowed removeIndex: row];
        }
        return allowed;
    }

    return proposed;
}

- (BOOL) _userSelectRowIndexes: (NSIndexSet *) indexes byExtendingSelection: (BOOL) extend {
    NSIndexSet *current = NS_EXTRA(NSTableView, self)->_selectedRowIndexes;
    NSMutableIndexSet *proposed = [[indexes mutableCopy] autorelease];

    if (extend)
        [proposed addIndexes: current];

    NSIndexSet *result = [self _delegateFilteredSelection: proposed];

    // A proposal the delegate rejected completely leaves the selection as it is
    if ([result count] == 0 && [proposed count] > 0)
        return NO;
    if ([result isEqualToIndexSet: current])
        return NO;
    [self selectRowIndexes: result byExtendingSelection: NO];
    return YES;
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

- (void) _noteColumn: (NSTableColumn *) column didResizeFromWidth: (CGFloat) oldWidth {
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSTableViewColumnDidResizeNotification
                          object: self
                        userInfo: [NSDictionary
                                          dictionaryWithObjectsAndKeys:
                                                  [NSNumber numberWithFloat: oldWidth], @"NSOldWidth",
                                                  column, @"NSTableColumn", nil]];
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
            [self _finishEditingWithTextMovement: NSIllegalTextMovement];
        [self selectRowIndexes: [NSIndexSet indexSet] byExtendingSelection: NO];
        [NS_EXTRA(NSTableView, self)->_selectedColumns removeAllObjects];
        forgetClickedCell(self);
        return;
    }

    // Where no column lies the documented clickedColumn is -1, which names no column object. The nil column
    // and its nil cell make the lookups below no-ops and leave nothing to track or edit.
    NSInteger clickedColumn = NS_EXTRA(NSTableView, self)->_clickedColumn;
    NSTableColumn *clickedColumnObject = clickedColumn >= 0 ? [_tableColumns objectAtIndex: clickedColumn] : nil;

    NSCell *clickedCell = [clickedColumnObject dataCellForRow: NS_EXTRA(NSTableView, self)->_clickedRow];

    [clickedCell setControlView: self];

    // Button cells track the mouse by default; the delegate can change that for any cell
    BOOL tracksCell = [clickedCell isKindOfClass: [NSButtonCell class]];

    if (clickedColumnObject != nil &&
        [_delegate respondsToSelector: @selector(tableView:shouldTrackCell:forTableColumn:row:)])
        tracksCell = [_delegate tableView: self
                          shouldTrackCell: clickedCell
                           forTableColumn: clickedColumnObject
                                      row: NS_EXTRA(NSTableView, self)->_clickedRow];

    // The delegate's YES only takes effect for button cells: on macOS (26.7.3 and 10.14.4,
    // black-box test appkit-table-delegate-selection) a click on a text cell still selects the
    // row when the delegate answers YES, so the click does not turn into a cell tracking
    // session that leaves the selection alone.
    if (![clickedCell isKindOfClass: [NSButtonCell class]])
        tracksCell = NO;

    if (tracksCell) {
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
            if ([clickedCell isKindOfClass: [NSButtonCell class]])
                [clickedCell setNextState];
            id value = nil;
            if ([clickedCell isKindOfClass: [NSPopUpButtonCell class]]) {
                value = [NSNumber
                        numberWithInt: [(NSPopUpButtonCell *) clickedCell
                                               indexOfSelectedItem]];
            } else if ([clickedCell isKindOfClass: [NSButtonCell class]]) {
                value = [NSNumber numberWithInt: [clickedCell state]];
            } else {
                value = [clickedCell objectValue];
            }
            [self dataSourceSetObjectValue: value
                            forTableColumn: clickedColumnObject
                                       row: NS_EXTRA(NSTableView, self)->_clickedRow];
            [self sendAction: [clickedCell action] to: [clickedCell target]];
        }

        [self setNeedsDisplay: YES];

        forgetClickedCell(self);
        return;
    }

    // NSLog(@"click in col %d row %d", _clickedColumn, _clickedRow);
    // single click behavior
    if ([event clickCount] < 2) {
        if ([self delegateSelectionShouldChange] ==
            NO) { // provide delegate opportunity
            forgetClickedCell(self);
            return;
        }

        if ([event modifierFlags] &
            NSAlternateKeyMask) {                    // extend/change selection
            if ([self isRowSelected: NS_EXTRA(NSTableView, self)->_clickedRow]) { // deselect previously
                                                     // selected?
                if ([self allowsEmptySelection] ||
                    [self numberOfSelectedColumns] > 1) {
                    NSMutableIndexSet *remaining = [[[self selectedRowIndexes] mutableCopy] autorelease];

                    [remaining removeIndex: NS_EXTRA(NSTableView, self)->_clickedRow];
                    [self _userSelectRowIndexes: remaining byExtendingSelection: NO];
                }
            } else if ([self allowsMultipleSelection]) {
                [self _userSelectRowIndexes: [NSIndexSet
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

                [self _userSelectRowIndexes:
                                      [NSIndexSet
                                              indexSetWithIndexesInRange:
                                                      NSMakeRange(startRow,
                                                                  endRow - startRow +
                                                                          1)]
                        byExtendingSelection: NO];
            } else
                [self _userSelectRowIndexes: [NSIndexSet
                                                     indexSetWithIndex: NS_EXTRA(NSTableView, self)->_clickedRow]
                        byExtendingSelection: NO];
        } else { // normal selection, allow for dragging
            BOOL dragging = NO;
            NSEvent *down = event;
            if ([self _dataSourceWritesRows]) {
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
                if ([self _dataSourceHasPasteboardWriters]) {
                    // The rows' writers are the dragging session's items; a row without one stays out
                    NSMutableArray *items = [NSMutableArray array];
                    NSMutableIndexSet *dragged = [NSMutableIndexSet indexSet];
                    NSUInteger row = [rowIndexes firstIndex];
                    for (; row != NSNotFound; row = [rowIndexes indexGreaterThanIndex: row]) {
                        id<NSPasteboardWriting> writer = [self _pasteboardWriterForRow: row];
                        if (writer == nil)
                            continue;
                        NSDraggingItem *item = [[[NSDraggingItem alloc] initWithPasteboardWriter: writer] autorelease];
                        [item setDraggingFrame: [self rectOfRow: row] contents: nil];
                        [items addObject: item];
                        [dragged addIndex: row];
                    }
                    if ([items count] == 0)
                        dragging = NO;
                    else {
                        [NS_EXTRA(NSTableView, self)->_draggedRows release];
                        NS_EXTRA(NSTableView, self)->_draggedRows = [dragged copy];
                        [self beginDraggingSessionWithItems: items event: down source: self];
                    }
                } else if ([_dataSource tableView: self
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

                [self _userSelectRowIndexes: [NSIndexSet
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
                            NSInteger startRow, endRow;

                            if (firstClickedRow > row) {
                                endRow = firstClickedRow;
                                startRow = row;
                            } else {
                                startRow = firstClickedRow;
                                endRow = row;
                            }

                            [self _userSelectRowIndexes:
                                          [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(startRow, endRow - startRow + 1)]
                                    byExtendingSelection: NO];
                        }

                        [self noteSelectionIsChanging];
                    } while ([event type] != NSLeftMouseUp);
                }
            }
        }

        [self sendAction: [self action] to: [self target]];
    } else if ([event clickCount] == 2) {
        // nb this logic was backwards previously

        id binder = [clickedColumnObject _binderForBinding: @"value"
                                                    create: NO];
        BOOL interpretedAsEdit = NO;
        if ([clickedColumnObject isEditable]) {
            if ([self dataSourceCanSetObjectValue] ||
                [binder allowsEditingForRow: NS_EXTRA(NSTableView, self)->_clickedRow]) {
                if (NS_EXTRA(NSTableView, self)->_clickedColumn != -1 && NS_EXTRA(NSTableView, self)->_clickedRow != -1) {
                    if ([self delegateShouldEditTableColumn: clickedColumnObject
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
    forgetClickedCell(self);
}

// The width a column needs for its header and the contents of its cells.
- (CGFloat) _naturalWidthOfColumn: (NSTableColumn *) column {
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
    return minWidth;
}

// Double-clicking the divider after a column: the delegate may name the width.
- (void) _sizeColumnToFit: (NSInteger) columnIndex {
    NSTableColumn *column = [_tableColumns objectAtIndex: columnIndex];
    CGFloat oldWidth = [column width], width;

    if ([_delegate respondsToSelector: @selector(tableView:sizeToFitWidthOfColumn:)])
        width = [_delegate tableView: self sizeToFitWidthOfColumn: columnIndex];
    else if ([self _delegateMakesCellViews])
        width = oldWidth; // views have no cell to measure
    else
        width = [self _naturalWidthOfColumn: column];

    [column setWidth: width];
    [self tile];
    [self _noteColumn: column didResizeFromWidth: oldWidth];
}

- (void) _tightenUpColumn: (NSTableColumn *) column {
    [column setMinWidth: [self _naturalWidthOfColumn: column]];
}

// Resizes the columns by the same amount so that they fit the clip view's
// width, as AppKit documents (macOS 10.14.4 gives the points left over to the
// first columns).
- (void) sizeToFit {
    if ([[self superview] isKindOfClass: [NSClipView class]])
        [self _resizeColumnsUniformlyBy: [[self superview] bounds].size.width - [self _displayWidthOfColumns]];
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

#pragma mark Dragging source

// The data source can give the rows to drag: as pasteboard writers, which come first, or onto a pasteboard
- (BOOL) _dataSourceHasPasteboardWriters {
    return [_dataSource respondsToSelector: @selector(tableView:pasteboardWriterForRow:)];
}

- (BOOL) _dataSourceWritesRows {
    return [self _dataSourceHasPasteboardWriters] ||
           [_dataSource respondsToSelector: @selector(tableView:writeRowsWithIndexes:toPasteboard:)];
}

- (id<NSPasteboardWriting>) _pasteboardWriterForRow: (NSInteger) row {
    return [_dataSource tableView: self pasteboardWriterForRow: row];
}

- (NSDragOperation) draggingSession: (NSDraggingSession *) session
    sourceOperationMaskForDraggingContext: (NSDraggingContext) context
{
    return [self draggingSourceOperationMaskForLocal: context == NSDraggingContextWithinApplication];
}

- (void) draggingSession: (NSDraggingSession *) session willBeginAtPoint: (NSPoint) screenPoint {
    NSIndexSet *rows = NS_EXTRA(NSTableView, self)->_draggedRows ?: [NSIndexSet indexSet];
    if ([_dataSource respondsToSelector: @selector(tableView:draggingSession:willBeginAtPoint:forRowIndexes:)])
        [_dataSource tableView: self draggingSession: session willBeginAtPoint: screenPoint forRowIndexes: rows];
}

- (void) draggingSession: (NSDraggingSession *) session
            endedAtPoint: (NSPoint) screenPoint
               operation: (NSDragOperation) operation
{
    if ([_dataSource respondsToSelector: @selector(tableView:draggingSession:endedAtPoint:operation:)])
        [_dataSource tableView: self draggingSession: session endedAtPoint: screenPoint operation: operation];
    [NS_EXTRA(NSTableView, self)->_draggedRows release];
    NS_EXTRA(NSTableView, self)->_draggedRows = nil;
}

#pragma mark Drop target

- (NSInteger) _getDraggedRowForPoint: (NSPoint) dragPoint {
    NSInteger draggedRow = [self rowAtPoint: dragPoint];
    if (-1 == draggedRow) {
        if (dragPoint.y >= [self rectOfRow: [self numberOfRows] - 1].origin.y) {
            draggedRow = [self numberOfRows];
        }
    }
    return draggedRow;
}

- (NSInteger) _getDraggedRow: (id<NSDraggingInfo>) info {
    return [self _getDraggedRowForPoint: [self convertPoint: [info draggingLocation]
                                                   fromView: nil]];
}

- (void) setDropRow: (NSInteger) row dropOperation: (NSTableViewDropOperation) operation {
    NS_EXTRA(NSTableView, self)->_draggingRow = row;
    NS_EXTRA(NSTableView, self)->_draggingOperation = operation;
}

// The table proposes the drop under the pointer: on the row when the pointer is in the middle of it, above
// the row or above the next one when it is near the top or bottom edge, above the end of the table when the
// pointer is below the last row. The data source may retarget it with -setDropRow:dropOperation: from
// validateDrop. The target left in the table afterwards is what acceptDrop receives.
// Observed by black-box test on macOS 26.7.3 and 10.14.4 (pointer at 2%, 10%, 25%, 40%..75%, 90% and 98% of a
// row's height: above, above, on, on, on, next row above, next row above); the edge zones are of a fifth of the
// row's height here, the observed boundaries lie between 10% and 25% and between 75% and 90%.
// Test: appkit-table-set-drop-row.m, appkit-tableview-drag.m
- (void) _proposeDropForPoint: (NSPoint) point {
    NSInteger row = [self rowAtPoint: point];
    NSTableViewDropOperation operation = NSTableViewDropAbove;

    if (row < 0) {
        row = [self _getDraggedRowForPoint: point];
    } else {
        NSRect rect = [self rectOfRow: row];
        CGFloat fraction = NSHeight(rect) > 0 ? (point.y - NSMinY(rect)) / NSHeight(rect) : 0.5;

        if (![self isFlipped])
            fraction = 1.0 - fraction;
        if (fraction > 0.8)
            row++;
        else if (fraction >= 0.2)
            operation = NSTableViewDropOn;
    }
    [self setDropRow: row dropOperation: operation];
}

// The data source's side of a drop. NSOutlineView overrides these to ask its data source about items.
- (BOOL) _dataSourceValidatesDrops {
    return [_dataSource respondsToSelector: @selector(tableView:validateDrop:proposedRow:proposedDropOperation:)];
}

- (NSDragOperation) _dataSourceValidateDrop: (id<NSDraggingInfo>) info {
    return [_dataSource tableView: self
                     validateDrop: info
                      proposedRow: NS_EXTRA(NSTableView, self)->_draggingRow
            proposedDropOperation: NS_EXTRA(NSTableView, self)->_draggingOperation];
}

- (BOOL) _dataSourceAcceptDrop: (id<NSDraggingInfo>) info {
    if (![_dataSource respondsToSelector: @selector(tableView:acceptDrop:row:dropOperation:)])
        return NO;
    return [_dataSource tableView: self
                       acceptDrop: info
                              row: NS_EXTRA(NSTableView, self)->_draggingRow
                    dropOperation: NS_EXTRA(NSTableView, self)->_draggingOperation];
}

// A drop forced on a table whose data source validates no drops
- (BOOL) _dataSourceAcceptUnvalidatedDrop: (id<NSDraggingInfo>) info {
    // QUIRK: a drop that reaches a table whose data source implements no validateDrop (the drag itself
    // was refused, so this is only a drop forced on the table) still goes to acceptDrop, with the
    // target row -2 and NSTableViewDropOn; a data source without acceptDrop is not asked.
    // Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2), identical on both.
    // Test: appkit-table-set-drop-row.m, test_quirk_drop_without_validate_drop
    if (![_dataSource respondsToSelector: @selector(tableView:acceptDrop:row:dropOperation:)])
        return NO;
    return [_dataSource tableView: self acceptDrop: info row: -2 dropOperation: NSTableViewDropOn];
}

// The row the drop feedback goes with (-1: the whole table), and whether the drop is on it rather than above it
- (NSInteger) _dropIndicatorRow {
    return NS_EXTRA(NSTableView, self)->_draggingRow;
}

- (BOOL) _dropIndicatorIsOn {
    return NS_EXTRA(NSTableView, self)->_draggingOperation == NSTableViewDropOn;
}

- (void) _showDropTarget: (BOOL) shown {
    NS_EXTRA(NSTableView, self)->_draggingTargetShown = shown;
    [self display];
}

- (NSDragOperation) _validateDraggedRow: (id<NSDraggingInfo>) info {
    NSDragOperation result = NSDragOperationNone;

    [self _proposeDropForPoint: [self convertPoint: [info draggingLocation] fromView: nil]];

    // A data source without validateDrop refuses the drag (nothing is proposed to it).
    if ([self _dataSourceValidatesDrops])
        result = [self _dataSourceValidateDrop: info];

    NS_EXTRA(NSTableView, self)->_draggingTargetKnown = result != NSDragOperationNone;
    [self _showDropTarget: result != NSDragOperationNone];
    return result;
}

- (BOOL) _draggingPasteboardHasDraggedType: (id<NSDraggingInfo>) sender {
    for (NSString *type in [self _draggedTypes])
        if ([[[sender draggingPasteboard] types] containsObject: type])
            return YES;
    return NO;
}

- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) sender {
    if ([self _draggingPasteboardHasDraggedType: sender])
        return [self _validateDraggedRow: sender];
    return NSDragOperationNone;
}

- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) sender {
    if ([self _draggingPasteboardHasDraggedType: sender])
        return [self _validateDraggedRow: sender];
    return NSDragOperationNone;
}

- (void) draggingExited: (id<NSDraggingInfo>) sender {
    NS_EXTRA(NSTableView, self)->_draggingTargetKnown = NO;
    [self _showDropTarget: NO];
}

- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) sender {
    [self _showDropTarget: NO];
    return YES;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender {
    if (![self _dataSourceValidatesDrops]) {
        NS_EXTRA(NSTableView, self)->_draggingTargetKnown = NO;
        return [self _dataSourceAcceptUnvalidatedDrop: sender];
    }

    if (!NS_EXTRA(NSTableView, self)->_draggingTargetKnown) {
        // Dropped without a preceding validation: validate now; the outline this draws is cleared again at once
        BOOL refused = [self _validateDraggedRow: sender] == NSDragOperationNone;

        [self _showDropTarget: NO];
        if (refused)
            return NO;
    }

    NS_EXTRA(NSTableView, self)->_draggingTargetKnown = NO;
    return [self _dataSourceAcceptDrop: sender];
}

- (void) draggingEnded: (id<NSDraggingInfo>) sender {
    NS_EXTRA(NSTableView, self)->_draggingTargetKnown = NO;
    if (NS_EXTRA(NSTableView, self)->_draggingTargetShown)
        [self _showDropTarget: NO];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ %0x08lx tableColumns: %@>",
                                       [self class], self, _tableColumns];
}

- (void) _moveUp: (BOOL) up extend: (BOOL) extend {
    NSIndexSet *selected = NS_EXTRA(NSTableView, self)->_selectedRowIndexes;
    NSInteger numberOfRows = [self numberOfRows];
    NSInteger rowToSelect = -1;

    if ([selected count] == 0)
        rowToSelect = 0;
    else if (up) {
        NSInteger first = [selected firstIndex];
        if (first > 0)
            rowToSelect = first - 1;
        else if (!extend)
            rowToSelect = first;
    } else {
        NSInteger last = [selected lastIndex];
        if (last < numberOfRows - 1)
            rowToSelect = last + 1;
        else if (!extend)
            rowToSelect = last;
    }

    // Rows the delegate refuses are stepped over when moving without extending
    while (rowToSelect >= 0 && rowToSelect < numberOfRows) {
        NSIndexSet *proposed;

        if (extend) {
            NSInteger startRow = [self selectedRow] >= 0 ? [self selectedRow] : rowToSelect, endRow = rowToSelect;

            if (startRow > endRow) {
                endRow = startRow;
                startRow = rowToSelect;
            }
            proposed = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(startRow, endRow - startRow + 1)];
        } else
            proposed = [NSIndexSet indexSetWithIndex: rowToSelect];

        if (![self delegateSelectionShouldChange])
            return;

        NSIndexSet *result = [self _delegateFilteredSelection: proposed];

        if ([result count] == 0 && !extend) {
            rowToSelect += up ? -1 : 1;
            continue;
        }
        if ([result count] > 0 && ![result isEqualToIndexSet: selected])
            [self selectRowIndexes: result byExtendingSelection: NO];
        if ([result count] > 0)
            [self scrollRowToVisible: rowToSelect];
        break;
    }
}

// Typing selects the next row whose text begins with what was typed. The
// text of the cells comes from tableView:typeSelectStringForTableColumn:row:,
// or, without it, from the values of cell-based columns. The documentation
// does not say how long a pause ends a search: one second is used.
#define NSTableViewTypeSelectPause 1.0
- (NSString *) _typeSelectStringForColumn: (NSTableColumn *) column row: (NSInteger) row {
    if ([_delegate respondsToSelector: @selector(tableView:typeSelectStringForTableColumn:row:)])
        return [_delegate tableView: self typeSelectStringForTableColumn: column row: row];

    id value = [self dataSourceObjectValueForTableColumn: column row: row];

    if ([value isKindOfClass: [NSAttributedString class]])
        return [value string];
    return [value isKindOfClass: [NSString class]] ? value : nil;
}

- (BOOL) _typeSelectEvent: (NSEvent *) event {
    NSInteger numberOfRows = [self numberOfRows];
    NSString *characters = [event characters];
    NSUInteger flags = [event modifierFlags];

    if (!NS_EXTRA(NSTableView, self)->_allowsTypeSelect || _editingCell != nil || numberOfRows == 0 || [characters length] == 0 ||
        (flags & (NSCommandKeyMask | NSControlKeyMask)))
        return NO;

    unichar first = [characters characterAtIndex: 0];

    // Control characters and the private-use function keys do not type
    if (first < 0x20 || first == 0x7F || (first >= 0xF700 && first <= 0xF8FF))
        return NO;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSString *current = NS_EXTRA(NSTableView, self)->_typeSelectString;

    if (current != nil && now - NS_EXTRA(NSTableView, self)->_typeSelectTime > NSTableViewTypeSelectPause)
        current = nil;

    if ([_delegate respondsToSelector: @selector(tableView:shouldTypeSelectForEvent:withCurrentSearchString:)] &&
        ![_delegate tableView: self shouldTypeSelectForEvent: event withCurrentSearchString: current])
        return NO;

    NSString *search = current != nil ? [current stringByAppendingString: characters] : characters;
    NSInteger selectedRow = [self selectedRow];
    NSInteger startRow = 0, endRow = 0;

    if (selectedRow >= 0) {
        // A search that goes on starts at the selected row; a new one after it
        startRow = current != nil ? selectedRow : (selectedRow + 1) % numberOfRows;
        endRow = current != nil ? 0 : selectedRow;
    }

    NSInteger match = -1;

    if ([_delegate respondsToSelector: @selector(tableView:nextTypeSelectMatchFromRow:toRow:forString:)]) {
        match = [_delegate tableView: self nextTypeSelectMatchFromRow: startRow toRow: endRow forString: search];
    } else {
        // The range includes the start row, excludes the end row and wraps; equal rows cover the table
        NSInteger count = (endRow - startRow + numberOfRows) % numberOfRows;
        NSInteger i;

        if (count == 0)
            count = numberOfRows;
        for (i = 0; i < count && match < 0; i++) {
            NSInteger row = (startRow + i) % numberOfRows;

            // Only rows that can be selected are candidates
            if ([[self _delegateFilteredSelection: [NSIndexSet indexSetWithIndex: row]] count] == 0)
                continue;
            for (NSTableColumn *column in _tableColumns) {
                NSString *text = [self _typeSelectStringForColumn: column row: row];

                if ([text length] > 0 &&
                    [text rangeOfString: search
                                options: NSAnchoredSearch | NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
                    match = row;
                    break;
                }
            }
        }
    }

    if (match >= 0 && match < numberOfRows) {
        [NS_EXTRA(NSTableView, self)->_typeSelectString release];
        NS_EXTRA(NSTableView, self)->_typeSelectString = [search copy];
        if ([self delegateSelectionShouldChange] &&
            [self _userSelectRowIndexes: [NSIndexSet indexSetWithIndex: match] byExtendingSelection: NO])
            [self scrollRowToVisible: match];
    }
    // A search that finds nothing keeps the text that last matched
    NS_EXTRA(NSTableView, self)->_typeSelectTime = now;
    return YES;
}

- (void) keyDown: (NSEvent *) event {
    if ([self _typeSelectEvent: event])
        return;

    NSString *characters = [event charactersIgnoringModifiers];

    if ([characters length] == 1) {
        unichar key = [characters characterAtIndex: 0];

        if (key == NSUpArrowFunctionKey || key == NSDownArrowFunctionKey) {
            [self interpretKeyEvents: [NSArray arrayWithObject: event]];
            return;
        }
    }
    [super keyDown: event];
}

// Cell tool tips: the delegate names the text for the cell under the pointer.
// Every visible cell of a cell-based table gets a tool tip area, which is
// rebuilt when the visible cells change.
- (void) _updateToolTipAreas {
    NSRect visible = [self visibleRect];
    NSRange rows = [self rowsInRect: visible], columns = [self columnsInRect: visible];
    CGFloat widths = 0;

    for (NSTableColumn *column in _tableColumns)
        widths += [column isHidden] ? 0 : [column width];

    NSString *signature = [NSString stringWithFormat: @"%@ %@ %ld %lu %g", NSStringFromRange(rows), NSStringFromRange(columns),
                                                      (long) [self numberOfRows], (unsigned long) [_tableColumns count], widths];

    if ([signature isEqualToString: NS_EXTRA(NSTableView, self)->_toolTipSignature])
        return;
    [NS_EXTRA(NSTableView, self)->_toolTipSignature release];
    NS_EXTRA(NSTableView, self)->_toolTipSignature = [signature copy];

    [self removeAllToolTips];
    for (NSInteger row = rows.location; row < (NSInteger) NSMaxRange(rows); row++)
        for (NSInteger column = columns.location; column < (NSInteger) NSMaxRange(columns); column++)
            [self addToolTipRect: [self frameOfCellAtColumn: column row: row] owner: self userData: NULL];
}

- (NSString *) view: (NSView *) view stringForToolTip: (NSToolTipTag) tag point: (NSPoint) point userData: (void *) data {
    NSInteger row = [self rowAtPoint: point], column = [self columnAtPoint: point];

    if (view != self || row < 0 || column < 0 ||
        ![_delegate respondsToSelector: @selector(tableView:toolTipForCell:rect:tableColumn:row:mouseLocation:)] ||
        [self _delegateMakesCellViews])
        return nil;

    NSRect rect = [self frameOfCellAtColumn: column row: row];
    NSTableColumn *tableColumn = [_tableColumns objectAtIndex: column];

    return [_delegate tableView: self
                 toolTipForCell: [self preparedCellAtColumn: column row: row]
                           rect: &rect
                    tableColumn: tableColumn
                            row: row
                  mouseLocation: point];
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

- (NSTableColumn *) highlightedTableColumn {
    return NS_EXTRA(NSTableView, self)->_highlightedTableColumn;
}

- (void) setHighlightedTableColumn: (NSTableColumn *) column {
    NS_EXTRA(NSTableView, self)->_highlightedTableColumn = column;
    [_headerView setNeedsDisplay: YES];
}

- (BOOL) verticalMotionCanBeginDrag {
    return !NS_EXTRA(NSTableView, self)->_verticalMotionCannotBeginDrag;
}

- (void) setVerticalMotionCanBeginDrag: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_verticalMotionCannotBeginDrag = !flag;
}

- (BOOL) rowActionsVisible {
    return NS_EXTRA(NSTableView, self)->_rowActionsVisible;
}

- (void) setRowActionsVisible: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_rowActionsVisible = flag;
}

- (BOOL) usesStaticContents {
    return NS_EXTRA(NSTableView, self)->_usesStaticContents;
}

- (void) setUsesStaticContents: (BOOL) flag {
    NS_EXTRA(NSTableView, self)->_usesStaticContents = flag;
}

- (NSTableViewDraggingDestinationFeedbackStyle) draggingDestinationFeedbackStyle {
    return NS_EXTRA(NSTableView, self)->_draggingDestinationFeedbackStyle;
}

- (void) setDraggingDestinationFeedbackStyle: (NSTableViewDraggingDestinationFeedbackStyle) style {
    NS_EXTRA(NSTableView, self)->_draggingDestinationFeedbackStyle = style;
}

// The style in effect: an automatic style resolves the way -style reports it.
- (NSTableViewStyle) effectiveStyle {
    return [self style];
}

// The indicator image is kept per column for the header to show.
- (void) setIndicatorImage: (NSImage *) image inTableColumn: (NSTableColumn *) tableColumn {
    NSValue *key = [NSValue valueWithNonretainedObject: tableColumn];

    if (NS_EXTRA(NSTableView, self)->_indicatorImages == nil)
        NS_EXTRA(NSTableView, self)->_indicatorImages = [[NSMutableDictionary alloc] init];
    if (image != nil)
        [NS_EXTRA(NSTableView, self)->_indicatorImages setObject: image forKey: key];
    else
        [NS_EXTRA(NSTableView, self)->_indicatorImages removeObjectForKey: key];
    [_headerView setNeedsDisplay: YES];
}

- (NSImage *) indicatorImageInTableColumn: (NSTableColumn *) tableColumn {
    return [NS_EXTRA(NSTableView, self)->_indicatorImages objectForKey: [NSValue valueWithNonretainedObject: tableColumn]];
}

// The row (column) of the cell a view belongs to: the view is looked up by
// climbing to the table's direct subview and finding what its frame centre lies in.
- (NSInteger) _cellIndexForView: (NSView *) view row: (BOOL) wantRow {
    // A cell view, or a view in one, is found by its key; a row view by its row
    for (NSView *ancestor = view; ancestor != nil && ancestor != self; ancestor = [ancestor superview]) {
        NSNumber *key = [[NS_EXTRA(NSTableView, self)->_cellViews allKeysForObject: ancestor] firstObject];

        if (key != nil) {
            unsigned long long value = [key unsignedLongLongValue];
            NSInteger column = (NSInteger) (value & 0xFFFFFF);

            if (wantRow)
                return (NSInteger) (value >> 24);
            return column == 0xFFFFFF ? -1 : column;
        }
        key = [[NS_EXTRA(NSTableView, self)->_rowViews allKeysForObject: ancestor] firstObject];
        if (key != nil)
            return wantRow ? [key integerValue] : -1;
    }

    while (view != nil && [view superview] != self)
        view = [view superview];
    if (view == nil)
        return -1;

    NSRect frame = [view frame];
    NSPoint centre = NSMakePoint(NSMidX(frame), NSMidY(frame));

    return wantRow ? [self rowAtPoint: centre] : [self columnAtPoint: centre];
}

- (NSInteger) rowForView: (NSView *) view {
    return [self _cellIndexForView: view row: YES];
}

- (NSInteger) columnForView: (NSView *) view {
    return [self _cellIndexForView: view row: NO];
}

// Group rows come from the delegate (tableView:isGroupRow:) and span all columns.
- (BOOL) _isGroupRow: (NSInteger) row {
    return [_delegate respondsToSelector: @selector(tableView:isGroupRow:)] &&
           [_delegate tableView: self isGroupRow: row];
}

// The key of a view in _cellViews: its row and column, a group row's view
// (which has no column) using the all-ones column.
static NSNumber *CellViewKey(NSInteger row, NSInteger column, BOOL group) {
    unsigned long long value = ((unsigned long long) row << 24) | (group ? 0xFFFFFF : ((unsigned long long) column & 0xFFFFFF));

    return [NSNumber numberWithUnsignedLongLong: value];
}

// More than this many waiting views per identifier are let go: a delegate that
// never asks for reused views would otherwise grow the queue on every reload.
#define NSTableViewReuseQueueLimit 128

// Takes a view out of the table. A view with an identifier waits for
// makeViewWithIdentifier:owner: to hand it out again.
- (void) _recycleView: (NSView *) view {
    NSString *identifier = [view identifier];

    [[view retain] autorelease];
    [view removeFromSuperview];
    if (identifier == nil)
        return;

    NSMutableArray *queue = [NS_EXTRA(NSTableView, self)->_reuseQueues objectForKey: identifier];

    if (queue == nil) {
        queue = [NSMutableArray array];
        [NS_EXTRA(NSTableView, self)->_reuseQueues setObject: queue forKey: identifier];
    }
    if ([queue count] < NSTableViewReuseQueueLimit && ![queue containsObject: view])
        [queue addObject: view];
}

- (void) _recycleAllCellViews {
    NSMutableDictionary *views = NS_EXTRA(NSTableView, self)->_cellViews;

    for (NSNumber *key in [views allKeys])
        [self _recycleView: [views objectForKey: key]];
    [views removeAllObjects];
    [self _removeRowViewsOutsideRows: NSMakeRange(0, 0)];
}

- (void) _recycleCellViewsOutsideRows: (NSRange) rows {
    NSMutableDictionary *views = NS_EXTRA(NSTableView, self)->_cellViews;

    for (NSNumber *key in [views allKeys]) {
        NSInteger row = (NSInteger) ([key unsignedLongLongValue] >> 24);

        if (!NSLocationInRange(row, rows)) {
            [self _recycleView: [views objectForKey: key]];
            [views removeObjectForKey: key];
        }
    }
    [self _removeRowViewsOutsideRows: rows];
}

// Row views of rows no longer shown leave the table; the delegate is told.
- (void) _removeRowViewsOutsideRows: (NSRange) rows {
    NSMutableDictionary *rowViews = NS_EXTRA(NSTableView, self)->_rowViews;

    for (NSNumber *key in [rowViews allKeys]) {
        NSInteger row = [key integerValue];

        if (NSLocationInRange(row, rows))
            continue;
        NSTableRowView *rowView = [[[rowViews objectForKey: key] retain] autorelease];

        [rowViews removeObjectForKey: key];
        [rowView removeFromSuperview];
        [self _delegateDidRemoveRowView: rowView forRow: row];
    }
}

- (NSTableRowView *) _delegateRowViewForRow: (NSInteger) row {
    if ([_delegate respondsToSelector: @selector(tableView:rowViewForRow:)])
        return [_delegate tableView: self rowViewForRow: row];
    return nil;
}

- (void) _delegateDidAddRowView: (NSTableRowView *) rowView forRow: (NSInteger) row {
    if ([_delegate respondsToSelector: @selector(tableView:didAddRowView:forRow:)])
        [_delegate tableView: self didAddRowView: rowView forRow: row];
}

- (void) _delegateDidRemoveRowView: (NSTableRowView *) rowView forRow: (NSInteger) row {
    if ([_delegate respondsToSelector: @selector(tableView:didRemoveRowView:forRow:)])
        [_delegate tableView: self didRemoveRowView: rowView forRow: row];
}

// The view of a row of a view-based table, a subview of the table holding the
// row's cell views. A new one comes from the delegate (a plain NSTableRowView
// when it gives none); its cell views are made and placed in it before the
// delegate is told it was added.
- (NSTableRowView *) _rowViewForRow: (NSInteger) row make: (BOOL) make {
    NSNumber *key = [NSNumber numberWithInteger: row];
    NSTableRowView *rowView = [NS_EXTRA(NSTableView, self)->_rowViews objectForKey: key];
    NSRect frame = [self rectOfRow: row];

    if (rowView != nil) {
        if (!NSEqualRects([rowView frame], frame))
            [rowView setFrame: frame];
        if ([rowView superview] != self)
            [self addSubview: rowView];
        return rowView;
    }
    if (!make)
        return nil;

    rowView = [self _delegateRowViewForRow: row];
    if (rowView == nil)
        rowView = [[[NSTableRowView alloc] initWithFrame: frame] autorelease];
    [rowView setFrame: frame];
    [rowView setGroupRowStyle: [self _isGroupRow: row]];
    [rowView setSelectionHighlightStyle: [self selectionHighlightStyle]];
    [rowView setSelected: [self isRowSelected: row]];
    [NS_EXTRA(NSTableView, self)->_rowViews setObject: rowView forKey: key];
    [self addSubview: rowView];

    if ([self _isGroupRow: row]) {
        [self _cellViewAtColumn: 0 row: row make: YES];
    } else {
        NSInteger column, count = [_tableColumns count];

        for (column = 0; column < count; column++)
            if (![[_tableColumns objectAtIndex: column] isHidden])
                [self _cellViewAtColumn: column row: row make: YES];
    }
    [self _delegateDidAddRowView: rowView forRow: row];
    return rowView;
}

// The view shown at a cell. It is asked of the delegate once, when the cell
// becomes visible or is reloaded, and kept in the table until then.
- (NSView *) _cellViewAtColumn: (NSInteger) column row: (NSInteger) row make: (BOOL) make {
    BOOL group = [self _isGroupRow: row];
    NSNumber *key = CellViewKey(row, column, group);
    NSView *view = [NS_EXTRA(NSTableView, self)->_cellViews objectForKey: key];
    NSTableRowView *rowView = [self _rowViewForRow: row make: make];

    // Making the row view made its cell views
    if (view == nil)
        view = [NS_EXTRA(NSTableView, self)->_cellViews objectForKey: key];
    // The frame is set once, in the coordinates of the view's superview: setting the table's
    // coordinates first and the row view's after would report two frame changes (and move a
    // layer-backed view through the table's coordinates) on every drawing pass.
    BOOL madeView = NO;

    if (view == nil && make) {
        view = group ? [self _delegateCellViewForTableColumn: nil row: row]
                     : [self _delegateCellViewForTableColumn: [_tableColumns objectAtIndex: column] row: row];
        madeView = view != nil;
    }
    if (view != nil) {
        NSRect frame = [self frameOfCellAtColumn: column row: row];

        if (group) {
            // A group row's view spans the whole row, less the spacing above and below it
            frame = [self rectOfRow: row];
            frame.origin.y += floor(_intercellSpacing.height / 2);
            frame.size.height -= _intercellSpacing.height;
        }

        if (rowView != nil) {
            // The row view holds the cell views, in its own coordinates
            NSRect rowRect = [rowView frame];

            frame.origin.x -= NSMinX(rowRect);
            frame.origin.y -= NSMinY(rowRect);
        }
        if (!NSEqualRects([view frame], frame))
            [view setFrame: frame];
        if (madeView) {
            [NS_EXTRA(NSTableView, self)->_cellViews setObject: view forKey: key];
            [self _setObjectValueOfCellView: view
                                     column: group ? nil : [_tableColumns objectAtIndex: column]
                                        row: row];
        }
        if (rowView != nil) {
            if ([view superview] != rowView)
                [rowView addSubview: view];
        } else if ([view superview] != self)
            [self addSubview: view];
    }
    return view;
}

// Whether the table is view-based: its delegate makes the cell views. An
// outline view asks its delegate with the outline view methods instead.
- (BOOL) _delegateMakesCellViews {
    return [_delegate respondsToSelector: @selector(tableView:viewForTableColumn:row:)];
}

- (NSView *) _delegateCellViewForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    return [_delegate tableView: self viewForTableColumn: column row: row];
}

// A view-based table gives a new cell view the object value the data source
// has for its cell, after the delegate made the view (a group row's view gets
// the value for no column), when the view takes one (NSTableCellView does) and
// the data source implements tableView:objectValueForTableColumn:row:.
// Bindings in the cell view, such as a text field bound to objectValue, show
// that value. Documented for NSTableViewDataSource; the order and the nil
// column of a group row are black-box observations on macOS 10.14.4 and
// 26.7.3. Test: tests/appkit-table-cell-view-object-value.m
- (void) _setObjectValueOfCellView: (NSView *) view column: (NSTableColumn *) column row: (NSInteger) row {
    if (![view respondsToSelector: @selector(setObjectValue:)] ||
        ![_dataSource respondsToSelector: @selector(tableView:objectValueForTableColumn:row:)])
        return;
    [(id) view setObjectValue: [_dataSource tableView: self objectValueForTableColumn: column row: row]];
}

- (NSView *) viewAtColumn: (NSInteger) column row: (NSInteger) row makeIfNecessary: (BOOL) makeIfNecessary {
    if (![self _delegateMakesCellViews])
        return nil;

    // Bad indexes raise as on macOS: a row beyond the table is an NSTableViewException, a
    // column beyond the columns an NSInternalInconsistencyException. A negative column
    // gives nil here (macOS returns a view for -1, apparently the row's own).
    if (row < 0 || row >= [self numberOfRows])
        [NSException raise: @"NSTableViewException"
                    format: @"Row index %ld out of row range (numberOfRows: %ld) for %@", (long) row, (long) [self numberOfRows], self];
    if (column >= (NSInteger) [_tableColumns count])
        [NSException raise: NSInternalInconsistencyException
                    format: @"Invalid parameter not satisfying: column >= 0 && column < _columnCount"];
    if (column < 0)
        return nil;

    // A group row has its view in the first column only
    if (column != 0 && [self _isGroupRow: row])
        return nil;
    return [self _cellViewAtColumn: column row: row make: makeIfNecessary];
}

// The view of a row of a view-based table: the one shown, else (makeIfNecessary)
// a new one with its cell views. A row beyond the table raises, as on macOS
// 10.14.4 and 26.7.3. Test: tests/appkit-table-row-views.m
- (NSTableRowView *) rowViewAtRow: (NSInteger) row makeIfNecessary: (BOOL) makeIfNecessary {
    if (row < 0 || row >= [self numberOfRows])
        [NSException raise: @"NSTableViewException"
                    format: @"Row index %ld out of row range (numberOfRows: %ld) for %@", (long) row, (long) [self numberOfRows], self];
    if (![self _delegateMakesCellViews])
        return nil;
    return [self _rowViewForRow: row make: makeIfNecessary];
}

- (void) enumerateAvailableRowViewsUsingBlock: (void (NS_NOESCAPE ^)(__kindof NSTableRowView *rowView, NSInteger row)) handler {
    NSMutableDictionary *rowViews = NS_EXTRA(NSTableView, self)->_rowViews;
    NSArray *keys = [[rowViews allKeys] sortedArrayUsingSelector: @selector(compare:)];

    for (NSNumber *key in keys) {
        NSTableRowView *rowView = [rowViews objectForKey: key];

        if (rowView != nil)
            handler(rowView, [key integerValue]);
    }
}

// Hands out a view for the identifier: one that left the table earlier, else
// one made from the nib registered for the identifier, else nil. The caller
// owns the placement; the table keeps track of the view once it is returned
// from tableView:viewForTableColumn:row:.
- (NSView *) makeViewWithIdentifier: (NSString *) identifier owner: (id) owner {
    if (identifier == nil)
        return nil;

    NSMutableArray *queue = [NS_EXTRA(NSTableView, self)->_reuseQueues objectForKey: identifier];

    if ([queue count] > 0) {
        NSView *view = [[[queue lastObject] retain] autorelease];

        [queue removeLastObject];
        return view;
    }

    NSNib *nib = [NS_EXTRA(NSTableView, self)->_registeredNibs objectForKey: identifier];
    NSArray *topLevelObjects = nil;

    if (nib == nil || ![nib instantiateWithOwner: owner topLevelObjects: &topLevelObjects])
        return nil;

    for (id object in topLevelObjects) {
        if ([object isKindOfClass: [NSView class]]) {
            if ([object identifier] == nil)
                [object setIdentifier: identifier];
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
