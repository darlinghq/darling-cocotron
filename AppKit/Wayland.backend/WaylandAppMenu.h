/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/

#import <Foundation/Foundation.h>

@class NSMenu, NSDBusMenu;

// Exports the application's main menu on the session bus (com.canonical.dbusmenu,
// through NSDBusMenu) for the desktop's global menu. The windows tell the
// compositor where it is with KDE's appmenu protocol (see -[WaylandWindow
// updateApplicationMenu]); the registrar's X11 window registration does not
// apply on Wayland.
@interface WaylandAppMenu : NSObject {
    NSMenu *_menu;
    NSDBusMenu *_exporter;
}

// Connects to the session bus. Without one the menu is not exported.
- (instancetype) init;

// YES while something on the session bus shows application menus: the
// registrar's name (com.canonical.AppMenu.Registrar) has an owner.
- (BOOL) globalMenuPresent;

- (void) setMainMenu: (NSMenu *) menu;

// Where the menu is exported; nil while there is no menu or no bus.
- (NSString *) serviceName;
- (NSString *) objectPath;

@end
