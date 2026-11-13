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

#import <Foundation/Foundation.h>

@class NSMenu;

// Exports an NSMenu on the desktop session bus with the com.canonical.dbusmenu
// protocol and announces it to the desktop's application menu registrar
// (com.canonical.AppMenu.Registrar), so that the desktop can show it in its
// global menu. Everything runs on the main run loop.
@interface X11DBusMenu : NSObject {
    void *_connection; // DBusConnection *
    CFSocketRef _socket;
    CFRunLoopSourceRef _source;
    NSMenu *_menu;
    NSString *_applicationName;
    NSString *_busName;
    BOOL _registrarPresent;
    unsigned _revision;
    NSDictionary *_servedLayout;
    NSMutableDictionary *_idsByItem;
    NSMutableDictionary *_itemsByID;
    int _nextID;
    NSMutableSet *_windows;
    CFRunLoopTimerRef _refreshTimer;
    id _delegate;
}

// The object path the menu is exported at.
+ (NSString *) menuObjectPath;

// Connects to the session bus named by DBUS_SESSION_BUS_ADDRESS (or the
// default socket of the user's runtime directory). Returns nil without a bus.
- (instancetype) initWithSessionBus;

- (NSString *) busName;
// YES while some process owns the registrar's name on the bus.
- (BOOL) registrarPresent;

// The delegate is told with -dbusMenuRegistrarChanged: when the registrar
// appears or goes away.
- (void) setDelegate: (id) delegate;

// The name shown for the first (application) menu.
- (void) setApplicationName: (NSString *) name;

// The menu exported, nil for none.
- (void) setMenu: (NSMenu *) menu;

// Something in the exported menu may have changed: send LayoutUpdated if it
// did.
- (void) menuChanged;

- (void) registerWindow: (unsigned long) window;
- (void) unregisterWindow: (unsigned long) window;

- (void) invalidate;

@end

@interface NSObject (X11DBusMenuDelegate)
- (void) dbusMenuRegistrarChanged: (X11DBusMenu *) menu;
@end
