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

#import <AppKit/NSTableCellView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSImageView.h>

@implementation NSTableCellView

@synthesize textField = _textField;
@synthesize imageView = _imageView;
@synthesize objectValue = _objectValue;
@synthesize rowSizeStyle = _rowSizeStyle;

- (NSBackgroundStyle) backgroundStyle {
    return _backgroundStyle;
}

// The controls in the view draw for the background the cell view says it is on (their text turns light on a
// dark one). The search stops at the cell views and tables nested in it, which have their own.
- (void) _applyBackgroundStyle: (NSBackgroundStyle) style toViewTree: (NSView *) view {
    if (view != self && ([view isKindOfClass: [NSTableCellView class]] || [view isKindOfClass: [NSTableView class]]))
        return;
    if ([view isKindOfClass: [NSControl class]])
        [[(NSControl *) view cell] setBackgroundStyle: style];
    for (NSView *subview in [view subviews])
        [self _applyBackgroundStyle: style toViewTree: subview];
}

- (void) setBackgroundStyle: (NSBackgroundStyle) style {
    if (_backgroundStyle == style)
        return;
    _backgroundStyle = style;
    [self _applyBackgroundStyle: style toViewTree: self];
    [self setNeedsDisplay: YES];
}

- (void) didAddSubview: (NSView *) subview {
    [super didAddSubview: subview];
    [self _applyBackgroundStyle: _backgroundStyle toViewTree: subview];
}

- (void) setTextField: (NSTextField *) textField {
    _textField = textField;
    [[_textField cell] setBackgroundStyle: _backgroundStyle];
}

- (void) dealloc {
    [_objectValue release];
    [super dealloc];
}

- (NSView *) hitTest: (NSPoint) aPoint {
    NSView *hit = [super hitTest: aPoint];
    if (hit == self || [hit isKindOfClass: [NSTextField class]] || [hit isKindOfClass: [NSImageView class]]) {
        return nil;
    }
    return hit;
}

@end
