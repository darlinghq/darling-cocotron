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

#import "X11AppMenu.h"
#import "../private-include/AppKit/NSDBusMenu.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenu.h>
#import <X11/Xatom.h>

// Atoms KDE reads to find the menu of a window; the registrar is told the same.
#define SERVICE_NAME_PROPERTY "_KDE_NET_WM_APPMENU_SERVICE_NAME"
#define OBJECT_PATH_PROPERTY "_KDE_NET_WM_APPMENU_OBJECT_PATH"

@implementation X11AppMenu

static NSString *applicationName(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *name = [bundle objectForInfoDictionaryKey: @"CFBundleDisplayName"];

    if ([name length] == 0)
        name = [bundle objectForInfoDictionaryKey: @"CFBundleName"];
    if ([name length] == 0)
        name = [[NSProcessInfo processInfo] processName];
    return name;
}

- (instancetype) initWithDisplay: (Display *) display {
    if ((self = [super init]) == nil)
        return nil;

    _display = display;
    _windows = [NSMutableSet new];

    _bar = [[NSMenuBarController alloc] initWithDelegate: self];
    return self;
}

- (void) dealloc {
    [_exporter invalidate];
    [_exporter release];
    [_bar release];
    [_menu release];
    [_windows release];
    [super dealloc];
}

// The session bus is only looked at once the application has a menu to show.
- (void) connectIfNeeded {
    if (_connectionTried)
        return;
    _connectionTried = YES;

    _exporter = [[NSDBusMenu alloc] initWithSessionBus];
    [_exporter setDelegate: self];
    [_exporter setApplicationName: applicationName()];
}

- (BOOL) globalMenuPresent {
    [self connectIfNeeded];
    return _exporter != nil && [_exporter registrarPresent];
}

#pragma mark - Windows

- (void) publishMenuOnWindow: (Window) window {
    NSString *service = [_exporter busName];
    NSString *path = [NSDBusMenu menuObjectPath];

    XChangeProperty(_display, window,
                    XInternAtom(_display, SERVICE_NAME_PROPERTY, False),
                    XA_STRING, 8, PropModeReplace,
                    (const unsigned char *) [service UTF8String],
                    (int) [service lengthOfBytesUsingEncoding: NSUTF8StringEncoding]);
    XChangeProperty(_display, window,
                    XInternAtom(_display, OBJECT_PATH_PROPERTY, False),
                    XA_STRING, 8, PropModeReplace,
                    (const unsigned char *) [path UTF8String],
                    (int) [path lengthOfBytesUsingEncoding: NSUTF8StringEncoding]);
    [_exporter registerWindow: window];
}

- (void) withdrawMenuFromWindow: (Window) window {
    XDeleteProperty(_display, window,
                    XInternAtom(_display, SERVICE_NAME_PROPERTY, False));
    XDeleteProperty(_display, window,
                    XInternAtom(_display, OBJECT_PATH_PROPERTY, False));
    [_exporter unregisterWindow: window];
}

- (void) windowCreated: (Window) window {
    [_windows addObject: [NSNumber numberWithUnsignedLong: window]];
    if (_exporter != nil && _menu != nil)
        [self publishMenuOnWindow: window];
}

- (void) windowDestroyed: (Window) window {
    NSNumber *key = [NSNumber numberWithUnsignedLong: window];

    if (![_windows containsObject: key])
        return;
    [_windows removeObject: key];
    [_exporter unregisterWindow: window];
}

#pragma mark - Menu

- (void) setMainMenu: (NSMenu *) menu {
    if (menu == _menu)
        return;

    BOOL hadMenu = _menu != nil;

    [_menu release];
    _menu = [menu retain];

    if (_menu != nil)
        [self connectIfNeeded];
    [_exporter setMenu: _menu];

    for (NSNumber *window in _windows) {
        if (_menu != nil)
            [self publishMenuOnWindow: [window unsignedLongValue]];
        else if (hadMenu)
            [self withdrawMenuFromWindow: [window unsignedLongValue]];
    }
    [_bar setMainMenu: _menu];
}

- (void) menuBarControllerMenuDidChange: (NSMenuBarController *) controller {
    [_exporter menuChanged];
}

// A desktop that shows the menu itself leaves the application's bar out.
- (BOOL) menuBarControllerDesktopShowsMenu: (NSMenuBarController *) controller {
    return _exporter != nil && [_exporter registrarPresent];
}

- (void) menuBarControllerDidUpdateBar: (NSMenuBarController *) controller {
    // This can run from a run loop observer with no event to flush it.
    XFlush(_display);
}

- (void) dbusMenuRegistrarChanged: (NSDBusMenu *) menu {
    [_bar update];
}

@end
