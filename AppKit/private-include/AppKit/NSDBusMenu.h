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
#import <dbus/dbus.h>

@class NSMenu;

// Exports an NSMenu on the desktop session bus with the com.canonical.dbusmenu
// protocol and announces it to the desktop's application menu registrar
// (com.canonical.AppMenu.Registrar), so that the desktop can show it in its
// global menu. Everything runs on the main run loop. The window server
// backends use it for the application menu, and NSStatusItem for the menu of a
// status item (with another object path); both go through libdbus the same way.
@interface NSDBusMenu : NSObject {
    void *_connection; // DBusConnection *
    CFSocketRef _socket;
    CFRunLoopSourceRef _source;
    NSMenu *_menu;
    NSString *_applicationName;
    NSString *_busName;
    NSString *_path;
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

// The object path the menu is exported at unless -setObjectPath: gives another.
+ (NSString *) menuObjectPath;
- (NSString *) objectPath;
- (void) setObjectPath: (NSString *) path;

// The DBusConnection, for a delegate that serves more objects on it. nil
// after -invalidate.
- (void *) connection;
// Sends a message on the connection and flushes it. Does not consume it.
- (void) send: (DBusMessage *) message;

// Connects to the session bus named by DBUS_SESSION_BUS_ADDRESS (or the
// default socket of the user's runtime directory). Returns nil without a bus.
- (instancetype) initWithSessionBus;

- (NSString *) busName;
// YES while some process owns the registrar's name on the bus.
- (BOOL) registrarPresent;

// The delegate is told with -dbusMenuRegistrarChanged: when the registrar
// appears or goes away, and is offered with -dbusMenu:handleMessage: the method
// calls to objects other than the menu and the signals the exporter does not
// consume itself (the ones a delegate asked for with dbus_bus_add_match()).
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

@interface NSObject (NSDBusMenuDelegate)
- (void) dbusMenuRegistrarChanged: (NSDBusMenu *) menu;
// Returns YES if the message was dealt with (a method call must then be
// answered by the delegate).
- (BOOL) dbusMenu: (NSDBusMenu *) menu handleMessage: (DBusMessage *) message;
@end

// Appends one basic-typed argument to a message / reads the leading basic
// arguments of a message. They use the message iterators because the variadic
// libdbus functions cannot be called through the wrapper library (see
// NSDBusMenu.m). Values are addresses of variables of the matching C type.
__attribute__((visibility("hidden"))) BOOL NSDBusAppendArgument(DBusMessage *message, int type, const void *value);
__attribute__((visibility("hidden"))) BOOL NSDBusReadArguments(DBusMessage *message, const int *types, unsigned count, void **values);
