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

// Whether the backend can show the main menu outside the application's windows
// (in the desktop's global menu or in a menu bar window of its own). When it
// cannot, the windows draw the menu themselves. Asked once, before the first
// window frame is computed. The default is YES.
- (BOOL) _showsMainMenuOutsideWindows;

// Whether the desktop itself shows application menus (a global menu, which
// the application exports its menu to). Asked once, before the first window
// frame is computed. The default is NO.
- (BOOL) _desktopShowsMainMenu;

@end

@interface NSWindow (NSInWindowMenuBar)

// YES if the main menu is drawn as a strip inside the windows that can carry
// one (by default whenever the desktop has no global menu; the
// DarlingMenuBarStyle and DarlingInWindowMenuBar preferences, or a backend that
// has nowhere else to show it) rather than shown globally.
+ (BOOL) _usesInWindowMenuBar;

@end
