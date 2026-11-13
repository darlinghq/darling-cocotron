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
#import <X11/Xlib.h>

@class NSMenu, NSMainMenuView, X11DBusMenu;

// The window along the top of the screen that shows the main menu of the
// active application when the desktop has no global menu. It is a dock window
// (_NET_WM_WINDOW_TYPE_DOCK) that reserves its strip of the screen
// (_NET_WM_STRUT_PARTIAL), so window managers keep other windows out of it and
// lay it over no decoration; see -[X11Window publishDockHints].
@interface X11MenuBarWindow : NSWindow {
    NSMainMenuView *_barView;
}

- (instancetype) initWithMenu: (NSMenu *) menu applicationName: (NSString *) name;
- (void) setMainMenu: (NSMenu *) menu;
- (void) setApplicationName: (NSString *) name;
// Redraws after the items of the menu changed.
- (void) menuChanged;
// Puts the bar along the top edge of the main screen, across its width.
- (void) placeAtTopOfScreen;

@end

// Shows the application's main menu outside its windows: in the desktop's
// global menu when the session has one, and otherwise in an X11MenuBarWindow
// for as long as the application is active.
//
// With a session bus the menu is exported on it, and the top-level windows
// carry the properties that tell the desktop where to find it. A desktop that
// has registered com.canonical.AppMenu.Registrar shows it in its panel, and the
// application's own bar stays hidden.
@interface X11AppMenu : NSObject {
    Display *_display;
    NSMenu *_menu;
    X11DBusMenu *_exporter;
    BOOL _connectionTried;
    X11MenuBarWindow *_bar;
    // The bar is not among the application's windows, so nothing else redraws it.
    CFRunLoopObserverRef _displayObserver;
    NSMutableSet *_windows;
}

- (instancetype) initWithDisplay: (Display *) display;

- (void) setMainMenu: (NSMenu *) menu;

// A top-level window of the application was created or destroyed (not a popup
// or the bar).
- (void) windowCreated: (Window) window;
- (void) windowDestroyed: (Window) window;

@end
