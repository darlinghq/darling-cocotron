/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSTableRowView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>

@implementation NSTableRowView

NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, selectionHighlightStyle, _selectionHighlightStyle, NSTableViewSelectionHighlightStyle, selectionHighlightStyle, setSelectionHighlightStyle:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, draggingDestinationFeedbackStyle, _draggingDestinationFeedbackStyle, NSTableViewDraggingDestinationFeedbackStyle, draggingDestinationFeedbackStyle, setDraggingDestinationFeedbackStyle:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, indentationForDropOperation, _indentationForDropOperation, CGFloat, indentationForDropOperation, setIndentationForDropOperation:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, emphasized, _emphasized, BOOL, isEmphasized, setEmphasized:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, groupRowStyle, _groupRowStyle, BOOL, isGroupRowStyle, setGroupRowStyle:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, floating, _floating, BOOL, isFloating, setFloating:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, targetForDropOperation, _targetForDropOperation, BOOL, isTargetForDropOperation, setTargetForDropOperation:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, previousRowSelected, _previousRowSelected, BOOL, isPreviousRowSelected, setPreviousRowSelected:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSTableRowView, nextRowSelected, _nextRowSelected, BOOL, isNextRowSelected, setNextRowSelected:)
NS_EXTRA_SYNTHESIZE_COPY(NSTableRowView, backgroundColor, _backgroundColor, NSColor *, backgroundColor, setBackgroundColor:)

- (instancetype) initWithFrame: (NSRect) frame {
    if ((self = [super initWithFrame: frame])) {
        NS_EXTRA(NSTableRowView, self)->_selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
        NS_EXTRA(NSTableRowView, self)->_emphasized = YES;
    }
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSTableRowView, self)->_backgroundColor release];
    NS_EXTRA_FREE(NSTableRowView, self);
    [super dealloc];
}

// A row view is flipped and its cell views are not (as on macOS), so a cell
// view draws and places its content with the origin at the bottom left.
- (BOOL) isFlipped {
    return YES;
}

- (BOOL) isSelected {
    return NS_EXTRA(NSTableRowView, self)->_selected;
}

- (void) setSelected: (BOOL) selected {
    if (NS_EXTRA(NSTableRowView, self)->_selected != selected) {
        NS_EXTRA(NSTableRowView, self)->_selected = selected;
        [self setNeedsDisplay: YES];
    }
}

// The cell views draw on a dark background in a selected, emphasized row.
- (NSBackgroundStyle) interiorBackgroundStyle {
    if ([self isSelected] && [self isEmphasized] &&
        [self selectionHighlightStyle] != NSTableViewSelectionHighlightStyleNone)
        return NSBackgroundStyleEmphasized;
    return NSBackgroundStyleNormal;
}

- (NSInteger) numberOfColumns {
    NSView *table = [self superview];
    return [table isKindOfClass: [NSTableView class]] ? [(NSTableView *) table numberOfColumns] : 0;
}

// The cell view of a column: the subview the table placed at that column.
- (NSView *) viewAtColumn: (NSInteger) column {
    NSView *table = [self superview];
    if (![table isKindOfClass: [NSTableView class]])
        return nil;
    NSInteger row = [(NSTableView *) table rowForView: self];
    if (row < 0 || column < 0 || column >= [(NSTableView *) table numberOfColumns])
        return nil;
    NSView *view = [(NSTableView *) table viewAtColumn: column row: row makeIfNecessary: NO];
    return [view superview] == self ? view : nil;
}

- (void) drawBackgroundInRect: (NSRect) dirtyRect {
    NSColor *color = [self backgroundColor];
    if (color != nil) {
        [color setFill];
        NSRectFillUsingOperation(dirtyRect, NSCompositingOperationSourceOver);
    }
}

// The table draws the selection of its rows behind the row views; a subclass
// draws its own selection here.
- (void) drawSelectionInRect: (NSRect) dirtyRect {
}

- (void) drawSeparatorInRect: (NSRect) dirtyRect {
}

- (void) drawDraggingDestinationFeedbackInRect: (NSRect) dirtyRect {
}

- (void) drawRect: (NSRect) dirtyRect {
    [self drawBackgroundInRect: dirtyRect];
    if ([self isSelected] && [self selectionHighlightStyle] != NSTableViewSelectionHighlightStyleNone)
        [self drawSelectionInRect: dirtyRect];
    if ([self isTargetForDropOperation])
        [self drawDraggingDestinationFeedbackInRect: dirtyRect];
}

@end
