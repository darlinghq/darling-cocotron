/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

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

#import <AppKit/NSMenuToolbarItem.h>
#import <AppKit/NSMenu.h>

// Keeps the menu and indicator flag it is given; the menu is not yet shown by
// a click or press-and-hold on the item.
@implementation NSMenuToolbarItem
@synthesize menu = _menu;
@synthesize showsIndicator = _showsIndicator;

- (instancetype) initWithItemIdentifier: (NSToolbarItemIdentifier) identifier {
    self = [super initWithItemIdentifier: identifier];
    if (self != nil)
        _showsIndicator = YES;
    return self;
}

// An item loaded from a nib takes this path, not the one above; the documented
// default of showsIndicator applies to it too.
- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder]) != nil)
        _showsIndicator = YES;
    return self;
}

// NSToolbarItem copies with NSCopyObject, which shares _menu without retaining it.
- (id) copyWithZone: (NSZone *) zone {
    NSMenuToolbarItem *copy = [super copyWithZone: zone];
    copy->_menu = [_menu retain];
    return copy;
}

- (void) dealloc {
    [_menu release];
    [super dealloc];
}

@end
