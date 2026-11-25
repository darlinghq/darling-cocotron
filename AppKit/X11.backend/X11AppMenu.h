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

#import <AppKit/NSWindow.h>
#import "../private-include/AppKit/NSMenuBarController.h"
#import <X11/Xlib.h>

@class NSMenu, NSDBusMenu, NSMenuBarController;

// Shows the application's main menu outside its windows: in the desktop's
// global menu when the session has one, and otherwise in the bar of an
// NSMenuBarController (an NSMenuBarWindow shown as a dock window).
//
// With a session bus the menu is exported on it, and the top-level windows
// carry the properties that tell the desktop where to find it. A desktop that
// has registered com.canonical.AppMenu.Registrar shows it in its panel, and the
// application's own bar stays hidden.
@interface X11AppMenu : NSObject <NSMenuBarControllerDelegate> {
    Display *_display;
    NSMenu *_menu;
    NSDBusMenu *_exporter;
    BOOL _exporting;
    BOOL _connectionTried;
    NSMenuBarController *_bar;
    NSMutableSet *_windows;
}

// Without exporting the menu is only shown in the menu bar window (the windows
// carry it as strips); with it the session bus is used as well.
- (instancetype) initWithDisplay: (Display *) display exporting: (BOOL) exporting;

- (void) setMainMenu: (NSMenu *) menu;

// Whether the session has a desktop that shows application menus (an appmenu
// registrar owns its name on the session bus). Connects to the bus on first use.
- (BOOL) globalMenuPresent;

// A top-level window of the application was created or destroyed (not a popup
// or the bar).
- (void) windowCreated: (Window) window;
- (void) windowDestroyed: (Window) window;

@end
