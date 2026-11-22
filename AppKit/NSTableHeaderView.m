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

#import <AppKit/NSCell.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSTableHeaderCell.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSSortDescriptor.h>
#import <AppKit/NSLinkedOnOrAfter.h>

@interface NSTableView (NSTableView_private)
- (void) noteColumnDidResizeWithOldWidth: (CGFloat) oldWidth;
- (void) _noteColumn: (NSTableColumn *) column didResizeFromWidth: (CGFloat) oldWidth;
- (void) _sizeColumnToFit: (NSInteger) columnIndex;
- (void) _moveColumn: (NSInteger) columnIndex toColumn: (NSInteger) newIndex notify: (BOOL) notify;
- (void) _noteColumnDidMoveFrom: (NSInteger) oldIndex to: (NSInteger) newIndex;
- (CGFloat) _spaceTakenByColumn: (NSTableColumn *) column;
@end

@implementation NSTableHeaderView

// QUIRK: the default height of a table header is 25 points for a program built against the 10.11 SDK or later and
// 17 for one built against an older SDK; a header view made with -init has it too. Not documented. Evidence:
// black-box observation on macOS 10.14.4 (tier 2): the header of a new table, of one in a scroll view, and a view
// from -[[NSTableHeaderView alloc] init], in programs recording SDK 10.9 and 10.10 (17) and 10.11 and later (25).
// Test: tests/appkit-table-header-default-height.m
+ (CGFloat) _defaultHeight {
    return NSProgramLinkedOnOrAfterSDK(NS_SDK_VERSION_MACOSX_10_11) ? 25.0 : 17.0;
}

- init {
    return [self initWithFrame: NSMakeRect(0, 0, 0, [NSTableHeaderView _defaultHeight])];
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        // NSKeyedUnarchiver *keyed=(NSKeyedUnarchiver *)coder;
        // nothing
    } else {
        _tableView = [coder decodeObject];
    }
    return self;
}

- (NSTableView *) tableView {
    return _tableView;
}

- (NSInteger) resizedColumn {
    return _resizedColumn;
}

- (NSInteger) draggedColumn {
    NSUnimplementedMethod();
    return -1;
}

- (CGFloat) draggedDistance {
    NSUnimplementedMethod();
    return -1;
}

- (void) setTableView: (NSTableView *) tableView {
    _tableView = tableView;
}

- (NSRect) headerRectOfColumn: (NSInteger) column {
    NSArray *tableColumns = [_tableView tableColumns];
    NSRect headerRect = _bounds;

    if (column < 0 || column >= [[_tableView tableColumns] count]) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"headerRectOfColumn: invalid index %ld (valid {%d, "
                            @"%lu})",
                            (long) column, 0, (unsigned long) [tableColumns count]];
    }

    headerRect.size.width = [_tableView _spaceTakenByColumn: [tableColumns objectAtIndex: column--]];
    while (column >= 0)
        headerRect.origin.x += [_tableView _spaceTakenByColumn: [tableColumns objectAtIndex: column--]];

    return headerRect;
}

- (NSInteger) columnAtPoint: (NSPoint) point {
    NSInteger i, count = [[_tableView tableColumns] count];

    for (i = 0; i < count; ++i) {
        if (NSMouseInRect(point, [self headerRectOfColumn: i],
                          [self isFlipped]))
            return i;
    }

    return NSNotFound;
}

// The column the table is sorted by: the one whose sort descriptor prototype has the key of the table's first
// sort descriptor.
- (NSTableColumn *) _primarySortedColumn: (BOOL *) ascending {
    NSSortDescriptor *primary = [[_tableView sortDescriptors] firstObject];
    NSString *key = [primary key];

    if (key == nil)
        return nil;
    for (NSTableColumn *column in [_tableView tableColumns]) {
        if ([[[column sortDescriptorPrototype] key] isEqualToString: key]) {
            *ascending = [primary ascending];
            return column;
        }
    }
    return nil;
}

// QUIRK: the header shows the column the table is sorted by (see -_primarySortedColumn:) with a bold title and
// draws its indicator with -drawSortIndicatorWithFrame:inView:ascending:priority:, instead of an indicator image
// set for that column; the highlighted table column also has a bold title, without any other change. Evidence:
// black-box renders on macOS 10.14.4 (tier 2): after -setSortDescriptors: whose first key matches a column's
// prototype, that column's title is bold and a dark chevron is drawn although -indicatorImageInTableColumn: is nil,
// also when NSAscendingSortIndicator is set as its indicator image; a descriptor matching no column changes nothing;
// -setHighlightedTableColumn: makes only the title bold. Test: appkit-table-header-aqua.m (test_quirk_sorted_column)
- (void) drawRect: (NSRect) rect {
    NSArray *tableColumns = [_tableView tableColumns];
    NSInteger i, count = [tableColumns count];
    NSRect columnRect = _bounds;
    NSSize spacing = [_tableView intercellSpacing];
    BOOL ascending = YES;
    NSTableColumn *sorted = [self _primarySortedColumn: &ascending];

    for (i = 0; i < count; ++i) {
        NSTableColumn *column = [tableColumns objectAtIndex: i];
        NSTableHeaderCell *cell = [column headerCell];
        BOOL bold = column == sorted || column == [_tableView highlightedTableColumn];
        NSFont *font = nil;

        if ([column isHidden])
            continue;
        columnRect.size.width = [column width] + spacing.width;
        // A selected column shows highlighted
        [cell setHighlighted: [_tableView isColumnSelected: i]];
        [cell setControlView: self];
        if (bold) {
            font = [[cell font] retain];
            [cell setFont: [[NSFontManager sharedFontManager] convertFont: font toHaveTrait: NSBoldFontMask]];
        }
        [cell drawWithFrame: columnRect inView: self];
        if (bold) {
            [cell setFont: font];
            [font release];
        }

        if (column == sorted &&
            [cell respondsToSelector: @selector(drawSortIndicatorWithFrame:inView:ascending:priority:)]) {
            [cell drawSortIndicatorWithFrame: columnRect inView: self ascending: ascending priority: 0];
        } else {
            NSImage *indicator = [_tableView indicatorImageInTableColumn: column];

            if (indicator != nil && [cell respondsToSelector: @selector(sortIndicatorRectForBounds:)])
                [[self graphicsStyle] drawTableViewHeaderIndicatorImage: indicator
                                                                  inRect: [cell sortIndicatorRectForBounds: columnRect]];
        }
        columnRect.origin.x += [column width] + spacing.width;
    }

    // Right of the last column the header continues, with its lines but without a separator (macOS 10.14.4)
    if (NSMinX(columnRect) < NSMaxX(_bounds)) {
        columnRect.size.width = NSMaxX(_bounds) - NSMinX(columnRect);
        [[self graphicsStyle] drawTableViewCornerInRect: columnRect];
    }
}

- (NSRect) _resizeRectBeforeColumn: (int) column {
    NSRect rect = [self headerRectOfColumn: column];

    rect.origin.x -= 2;
    rect.size.width = 6;

    return rect;
}

- (void) mouseDown: (NSEvent *) theEvent {
    NSPoint location = [self convertPoint: [theEvent locationInWindow]
                                 fromView: nil];
    NSInteger clickedColumn = [self columnAtPoint: location];

    if (clickedColumn != NSNotFound &&
        [[_tableView delegate] respondsToSelector: @selector
                               (tableView:mouseDownInHeaderOfTableColumn:)])
        [[_tableView delegate] tableView: _tableView
                mouseDownInHeaderOfTableColumn:
                        [[_tableView tableColumns]
                                objectAtIndex: clickedColumn]];

    if ([_tableView allowsColumnResizing]) {
        NSInteger i, count = [[_tableView tableColumns] count];

        // if there is any editing going on, we have to end it. Apple ends
        // editing, sends the setObjectValue, but does NOT select any following
        // cells. sending nil to textDidEndEditing will cause a 0 or
        // NSIllegalTextMovement, so no editing chain stuff will happen.
        if ([_tableView editedColumn] != -1 || [_tableView editedRow] != -1)
            [[self window] endEditingFor: nil];

        for (i = 1; i < count; ++i) {
            // The edge before a column is the right edge of the one before it; a hidden one has none
            if ([[[_tableView tableColumns] objectAtIndex: i - 1] isHidden])
                continue;
            if (NSMouseInRect(location, [self _resizeRectBeforeColumn: i],
                              [self isFlipped])) {
                NSTableColumn *resizingColumn =
                        [[_tableView tableColumns] objectAtIndex: i - 1];
                CGFloat resizedColumnWidth = [resizingColumn width];

                if (![resizingColumn isResizable])
                    return;

                // Double-clicking the divider fits the column to its contents
                if ([theEvent clickCount] == 2) {
                    [_tableView _sizeColumnToFit: i - 1];
                    return;
                }

                _resizedColumn = i - 1;
                location = [self convertPoint: [theEvent locationInWindow]
                                     fromView: nil];
                do { // greatly simplified code...
                    NSPoint newPoint;
                    NSRect newRect;
                    NSInteger q;
                    CGFloat newWidth = newPoint.x;

                    theEvent = [[self window]
                            nextEventMatchingMask: NSLeftMouseUpMask |
                                                   NSLeftMouseDraggedMask];
                    newPoint = [self convertPoint: [theEvent locationInWindow]
                                         fromView: nil];

                    newWidth = newPoint.x;
                    for (q = 0; q < _resizedColumn; ++q)
                        newWidth -= [_tableView _spaceTakenByColumn: [[_tableView tableColumns] objectAtIndex: q]];

                    [resizingColumn setWidth: newWidth];

                    [_tableView tile];
                    newRect.origin = [_tableView convertPoint: newPoint
                                                     fromView: self];
                    newRect.size = NSMakeSize(10, 10);
                    [_tableView scrollRectToVisible: newRect];

                    location = newPoint;
                } while ([theEvent type] != NSLeftMouseUp);

                [[self window] invalidateCursorRectsForView: self];

                [_tableView _noteColumn: resizingColumn didResizeFromWidth: resizedColumnWidth];

                _resizedColumn = -1;
                return;
            }
        }
    }

    if (clickedColumn == NSNotFound)
        return;

    // Dragging a header cell moves its column when the table allows reordering
    if ([_tableView allowsColumnReordering]) {
        id delegate = [_tableView delegate];
        BOOL dragged = NO, mayMove = YES;
        NSInteger current = clickedColumn;
        NSPoint start = location;

        do {
            theEvent = [[self window] nextEventMatchingMask: NSLeftMouseUpMask | NSLeftMouseDraggedMask];
            NSPoint point = [self convertPoint: [theEvent locationInWindow] fromView: nil];

            if ([theEvent type] != NSLeftMouseDragged)
                break;
            if (!dragged) {
                if (fabs(point.x - start.x) < 3.0)
                    continue;
                dragged = YES;
                // The delegate is first asked about the column as a whole
                if ([delegate respondsToSelector: @selector(tableView:shouldReorderColumn:toColumn:)])
                    mayMove = [delegate tableView: _tableView shouldReorderColumn: clickedColumn toColumn: -1];
            }
            if (mayMove) {
                NSInteger target = [self columnAtPoint: point];

                if (target != NSNotFound && target != current &&
                    (![delegate respondsToSelector: @selector(tableView:shouldReorderColumn:toColumn:)] ||
                     [delegate tableView: _tableView shouldReorderColumn: current toColumn: target])) {
                    [_tableView _moveColumn: current toColumn: target notify: NO];
                    current = target;
                }
            }
        } while ([theEvent type] != NSLeftMouseUp);

        if (dragged) {
            if (current != clickedColumn)
                [_tableView _noteColumnDidMoveFrom: clickedColumn to: current];
            return;
        }
    }

    if ([_tableView allowsColumnSelection]) {
        if ([theEvent modifierFlags] &
            NSAlternateKeyMask) { // extend/change selection
            if ([_tableView
                        isColumnSelected: clickedColumn]) // deselect previously
                                                          // selected?
                [_tableView deselectColumn: clickedColumn];
            else if ([_tableView allowsMultipleSelection] == YES) {
                [_tableView selectColumn: clickedColumn
                        byExtendingSelection: YES]; // add to selection
            }
        } else if ([theEvent modifierFlags] & NSShiftKeyMask) {
            NSInteger startColumn = [_tableView selectedColumn];
            NSInteger endColumn = clickedColumn;

            if (startColumn == -1)
                startColumn = 0;
            if (startColumn > endColumn) {
                endColumn = startColumn;
                startColumn = clickedColumn;
            }

            [_tableView deselectAll: nil];
            while (startColumn <= endColumn)
                [_tableView selectColumn: startColumn++
                        byExtendingSelection: YES];
        } else
            [_tableView selectColumn: clickedColumn byExtendingSelection: NO];
    }

    if ([[_tableView delegate] respondsToSelector: @selector(tableView:didClickTableColumn:)])
        [[_tableView delegate] tableView: _tableView
                     didClickTableColumn: [[_tableView tableColumns] objectAtIndex: clickedColumn]];

    [[[_tableView tableColumns] objectAtIndex: clickedColumn] _sort];
}

- (void) resetCursorRects {
    NSInteger i;

    for (i = 1; i < [[_tableView tableColumns] count]; ++i)
        [self addCursorRect: [self _resizeRectBeforeColumn: i]
                     cursor: [NSCursor resizeLeftRightCursor]];
}

- (void) resizeWithOldSuperviewSize: (NSSize) size {
    [self resetCursorRects];
}

@end
