/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/

#import "../private-include/AppKit/NSMenuBarController.h"

@class NSMenu, NSDBusMenu, WaylandDisplay;

// Exports the application's main menu on the session bus (com.canonical.dbusmenu,
// through NSDBusMenu) for the desktop's global menu. The windows tell the
// compositor where it is with KDE's appmenu protocol (see -[WaylandWindow
// updateApplicationMenu]); the registrar's X11 window registration does not
// apply on Wayland.
//
// Without a global menu, and with a compositor that has wlr-layer-shell, the
// menu is shown in the menu bar window (see NSMenuBarController), which
// WaylandWindow makes a layer surface along the top of the screen.
@interface WaylandAppMenu : NSObject <NSMenuBarControllerDelegate> {
    NSMenu *_menu;
    NSDBusMenu *_exporter;
    WaylandDisplay *_display;
    NSMenuBarController *_bar;
    BOOL _exporting;
}

// Connects to the session bus when exporting. Without one the menu is not
// exported. Without exporting (the windows carry the menu as strips) the menu
// is only shown in the bar. The bar is only made when the display has a layer
// shell.
- (instancetype) initWithDisplay: (WaylandDisplay *) display exporting: (BOOL) exporting;

// YES while something on the session bus shows application menus: the
// registrar's name (com.canonical.AppMenu.Registrar) has an owner.
- (BOOL) globalMenuPresent;

- (void) setMainMenu: (NSMenu *) menu;

// Where the menu is exported; nil while there is no menu or no bus.
- (NSString *) serviceName;
- (NSString *) objectPath;

@end
