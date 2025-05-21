/*
 * This file is part of Darling.
 *
 * Copyright (C) 2024 Darling Developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

 #import <AppKit/NSMenuItemCell.h>

 @implementation NSMenuItemCell

 @synthesize menuItem = _menuItem;

 - initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        _menuItem = [[coder decodeObjectForKey:@"NSMenuItem"] retain];
    } else {
        NSInteger version = [coder versionForClassName: @"NSMenuItemCell"];

        if (version >= 207) {
            id object;
            [coder decodeValuesOfObjCTypes:"@@", &_menuItem, &object];

            // Discard for now
            [object release];

            if (version <= 209) {
                [self setBordered: NO];
            }
        } else {
            [self setBordered: NO];
        }
    }

    return self;
 }

 - (void) dealloc {
    [_menuItem release];
    [super dealloc];
}

 @end
