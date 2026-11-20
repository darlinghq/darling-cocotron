/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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

#import <AppKit/NSWindowTabGroup.h>

@interface NSWindowTabGroup (Private)

// A group for one window, named by the window's tabbing identifier. The
// window owns the group; the group does not retain the window.
- (instancetype) _initWithWindow: (NSWindow *) window;

// Called by the window as it goes away.
- (void) _windowWillDeallocate;

@end
