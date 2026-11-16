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

@class NSStatusItem, NSDBusMenu;

// What about an item changed (see -[NSStatusItemNotifier itemChanged:]).
enum {
    NSStatusItemNotifierTitle = 1 << 0,
    NSStatusItemNotifierIcon = 1 << 1,
    NSStatusItemNotifierToolTip = 1 << 2,
    NSStatusItemNotifierStatus = 1 << 3,
    NSStatusItemNotifierMenu = 1 << 4,
};

// Shows an NSStatusItem in the desktop's system tray over D-Bus, with the
// StatusNotifierItem protocol (org.kde.StatusNotifierItem, announced to
// org.kde.StatusNotifierWatcher), and its menu with com.canonical.dbusmenu
// through NSDBusMenu. D-Bus does not depend on the window server, so this works
// the same on X11 and Wayland. Without a session bus, or without a watcher, the
// item exists and nothing is shown. Everything runs on the main run loop.
@interface NSStatusItemNotifier : NSObject {
    NSStatusItem *_item; // not retained: the item owns the notifier
    NSDBusMenu *_bus;
    NSString *_serviceName;
    NSMutableArray *_pixmaps;
    NSUInteger _pending;
    CFRunLoopTimerRef _flushTimer;
}

// nil if there is no session bus.
- (instancetype) initWithStatusItem: (NSStatusItem *) item;

// The item's content, title, tool tip, menu or visibility changed.
- (void) itemChanged: (NSUInteger) aspects;

// Takes the item off the tray and ends the connection.
- (void) invalidate;

@end
