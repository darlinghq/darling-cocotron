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

#import <AppKit/NSView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/AppKitIvarLayout.h>

NS_ASSUME_NONNULL_BEGIN

@class NSColor;

// The view of one row of a view-based table: the row's cell views are its
// subviews. It draws the row's background and selection.
@interface NSTableRowView : NSView {
    // Apple's footprint is 32 bytes over NSView's: the extras pointer and padding.
    NS_LEGACY_IVAR_PAD(_NSTableRowViewReserved, 28)
    NS_EXTRA_IVARS_BEGIN(NSTableRowView)
        NSColor *_backgroundColor;
        NSTableViewSelectionHighlightStyle _selectionHighlightStyle;
        NSTableViewDraggingDestinationFeedbackStyle _draggingDestinationFeedbackStyle;
        CGFloat _indentationForDropOperation;
        BOOL _selected;
        BOOL _emphasized;
        BOOL _groupRowStyle;
        BOOL _floating;
        BOOL _targetForDropOperation;
        BOOL _previousRowSelected;
        BOOL _nextRowSelected;
    NS_EXTRA_IVARS_END(NSTableRowView)
}

@property (copy) NSColor *backgroundColor;
@property NSTableViewSelectionHighlightStyle selectionHighlightStyle;
@property NSTableViewDraggingDestinationFeedbackStyle draggingDestinationFeedbackStyle;
@property CGFloat indentationForDropOperation;
@property (getter=isSelected) BOOL selected;
@property (getter=isEmphasized) BOOL emphasized;
@property (getter=isGroupRowStyle) BOOL groupRowStyle;
@property (getter=isFloating) BOOL floating;
@property (getter=isTargetForDropOperation) BOOL targetForDropOperation;
@property (getter=isPreviousRowSelected) BOOL previousRowSelected;
@property (getter=isNextRowSelected) BOOL nextRowSelected;
@property (readonly) NSBackgroundStyle interiorBackgroundStyle;
@property (readonly) NSInteger numberOfColumns;

- (void) drawBackgroundInRect: (NSRect) dirtyRect;
- (void) drawSelectionInRect: (NSRect) dirtyRect;
- (void) drawSeparatorInRect: (NSRect) dirtyRect;
- (void) drawDraggingDestinationFeedbackInRect: (NSRect) dirtyRect;
- (nullable __kindof NSView *) viewAtColumn: (NSInteger) column;

@end

NS_ASSUME_NONNULL_END
