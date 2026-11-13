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

#import <AppKit/NSDisplay.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSWindow.h>

// The interface between AppKit and a backend that shows the application's
// main menu outside its windows (in the desktop's global menu, or in a menu
// bar of its own).

@interface NSDisplay (NSGlobalMenu)

// Called when the application's main menu is set. A backend that shows the
// menu itself takes it from here; the default does nothing.
- (void) _mainMenuDidChange: (NSMenu *) menu;

@end

@interface NSWindow (NSInWindowMenuBar)

// YES if the main menu is drawn as a strip inside titled windows (the
// DarlingInWindowMenuBar preference) rather than shown globally.
+ (BOOL) _usesInWindowMenuBar;

@end
