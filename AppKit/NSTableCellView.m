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
#import <AppKit/NSTextField.h>
#import <AppKit/NSImageView.h>

@implementation NSTableCellView

@synthesize textField = _textField;
@synthesize secondTextField = _secondTextField;
@synthesize imageView = _imageView;
@synthesize objectValue = _objectValue;
@synthesize backgroundStyle = _backgroundStyle;
@synthesize rowSizeStyle = _rowSizeStyle;

- (void) dealloc {
    [_objectValue release];
    [super dealloc];
}

- (BOOL) isFlipped {
    return YES;
}

- (NSView *) hitTest: (NSPoint) aPoint {
    NSView *hit = [super hitTest: aPoint];
    if (hit == self || [hit isKindOfClass: [NSTextField class]] || [hit isKindOfClass: [NSImageView class]]) {
        return nil;
    }
    return hit;
}

@end
