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
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSImageView.h>

@implementation NSTableCellView

@synthesize objectValue = _objectValue;
@synthesize rowSizeStyle = _rowSizeStyle;

- (NSTextField *) textField {
    return _textField;
}

- (void) setTextField: (NSTextField *) textField {
    if (_textField == textField)
        return;
    if (_textField != nil) {
        [[_textField cell] setBackgroundStyle: NSBackgroundStyleNormal];
        if (_backgroundStyle != NSBackgroundStyleNormal)
            [_textField setNeedsDisplay: YES];
    }
    _textField = textField;
    if (_textField != nil) {
        [[_textField cell] setBackgroundStyle: _backgroundStyle];
        if (_backgroundStyle != NSBackgroundStyleNormal)
            [_textField setNeedsDisplay: YES];
    }
}

- (NSImageView *) imageView {
    return _imageView;
}

- (void) setImageView: (NSImageView *) imageView {
    _imageView = imageView;
}

- (NSBackgroundStyle) backgroundStyle {
    return _backgroundStyle;
}

- (void) _applyBackgroundStyle: (NSBackgroundStyle) backgroundStyle toViewTree: (NSView *) view {
    if (view != self && ([view isKindOfClass: [NSTableCellView class]] ||
                         [view isKindOfClass: [NSTableView class]]))
        return;
    if ([view isKindOfClass: [NSControl class]])
        [[(NSControl *)view cell] setBackgroundStyle: backgroundStyle];
    for (NSView *subview in [view subviews])
        [self _applyBackgroundStyle: backgroundStyle toViewTree: subview];
}

- (void) didAddSubview: (NSView *) subview {
    [super didAddSubview: subview];
    [self _applyBackgroundStyle: _backgroundStyle toViewTree: subview];
}

- (void) setBackgroundStyle: (NSBackgroundStyle) backgroundStyle {
    if (_backgroundStyle == backgroundStyle)
        return;
    _backgroundStyle = backgroundStyle;
    [self _applyBackgroundStyle: backgroundStyle toViewTree: self];
    if ([NSGraphicsContext currentContext] == nil)
        [self setNeedsDisplay: YES];
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
