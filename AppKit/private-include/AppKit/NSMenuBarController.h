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

@class NSMenu, NSMainMenuView, NSMenuBarController;

// The window along the top of the screen that shows the main menu of the
// application when the desktop has no global menu. A display backend gives it
// the role of a panel that reserves its strip of the screen: a dock window on
// X11, a layer surface on Wayland. It is recognized by its class.
@interface NSMenuBarWindow : NSWindow {
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

// What a display backend adds to the menu bar policy of NSMenuBarController.
@protocol NSMenuBarControllerDelegate <NSObject>

// Whether the desktop shows the menu itself, so no bar is wanted.
- (BOOL) menuBarControllerDesktopShowsMenu: (NSMenuBarController *) controller;
// The bar was shown, hidden or redrawn: send it to the display server.
- (void) menuBarControllerDidUpdateBar: (NSMenuBarController *) controller;

@optional
// An item of the main menu was added, removed or changed.
- (void) menuBarControllerMenuDidChange: (NSMenuBarController *) controller;

@end

// Decides whether the application's main menu is shown in an NSMenuBarWindow,
// and keeps the bar current, for every display backend. The bar is shown for
// as long as the application is active and has a main menu, unless the desktop
// shows the menu itself or the application hides the menu bar (presentation
// options, or a window in full screen mode). When only the application's
// activity ends, the bar stays for a short while: the focus passes between the
// windows of an application, and while windows are replaced, through states in
// which no window has it, and hiding and showing the bar for each (a surface
// created and destroyed on the display server every time) shows as flicker.
@interface NSMenuBarController : NSObject {
    id<NSMenuBarControllerDelegate> _delegate;
    NSMenu *_menu;
    NSMenuBarWindow *_bar;
    BOOL _barShown;
    // The bar outlives the application being inactive for a moment (see -update).
    NSTimer *_hideTimer;
    // The bar is not among the application's windows, so nothing else redraws it.
    CFRunLoopObserverRef _displayObserver;
}

- (instancetype) initWithDelegate: (id<NSMenuBarControllerDelegate>) delegate;

- (void) setMainMenu: (NSMenu *) menu;
// Shows or hides the bar after something it depends on changed.
- (void) update;
- (BOOL) barShown;
- (NSMenuBarWindow *) bar;

@end
