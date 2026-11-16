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

#import <AppKit/NSButtonCell.h>

#import <AppKit/AppKitIvarLayout.h>
@class NSMenuItem;

// Legacy ObjC ABI (i386): instance size must stay 0x74, Apple's; an
// application's subclass is laid out right after it. New state goes to a
// side structure, never to a larger ivar block.
@interface NSMenuItemCell : NSButtonCell  {
    // In Apple's AppKit this is stored in _extraData (NSExtraMICData)
    NSMenuItem *_menuItem;
    NS_LEGACY_IVAR_PAD(_NSMenuItemCellReserved1, 44)
 }

@property(retain) NSMenuItem *menuItem;

@end
