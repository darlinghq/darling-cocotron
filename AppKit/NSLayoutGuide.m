/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

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

#import <AppKit/NSLayoutGuide.h>
#import <AppKit/NSView.h>

@implementation NSLayoutGuide

- (instancetype) init {
    self = [super init];
    if (self) {
        _frame = NSZeroRect;
        _owningView = nil;
        _identifier = nil;
    }
    return self;
}

- (void) dealloc {
    [_identifier release];
    [super dealloc];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self) {
        if ([coder allowsKeyedCoding]) {
            _frame = [coder decodeRectForKey: @"NSFrame"];
            _identifier = [[coder decodeObjectForKey: @"NSUserInterfaceItemIdentifier"] copy];
        } else {
            _frame = NSZeroRect;
            _identifier = nil;
        }
        _owningView = nil;
    }
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        [coder encodeRect: _frame forKey: @"NSFrame"];
        [coder encodeObject: _identifier forKey: @"NSUserInterfaceItemIdentifier"];
    }
}

- (NSView *) owningView {
    return _owningView;
}

- (void) setOwningView: (NSView *) view {
    _owningView = view;
}

- (NSString *) identifier {
    return _identifier;
}

- (void) setIdentifier: (NSString *) identifier {
    if (_identifier != identifier) {
        [_identifier release];
        _identifier = [identifier copy];
    }
}

- (NSRect) frame {
    return _frame;
}

- (void) setFrame: (NSRect) frame {
    _frame = frame;
}

@end
