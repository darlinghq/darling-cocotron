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
#import "X11DBusMenu.h"
#import "../NSWindow-Private.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSMainMenuView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSScreen.h>
#import <X11/Xatom.h>

// Atoms KDE reads to find the menu of a window; the registrar is told the same.
#define SERVICE_NAME_PROPERTY "_KDE_NET_WM_APPMENU_SERVICE_NAME"
#define OBJECT_PATH_PROPERTY "_KDE_NET_WM_APPMENU_OBJECT_PATH"

@implementation X11MenuBarWindow

- (instancetype) initWithMenu: (NSMenu *) menu applicationName: (NSString *) name {
    NSRect screen = [[NSScreen mainScreen] frame];
    NSRect frame = NSMakeRect(NSMinX(screen), NSMaxY(screen), NSWidth(screen),
                              [NSMainMenuView menuHeight]);

    self = [super initWithContentRect: frame
                            styleMask: NSBorderlessWindowMask | NSAppKitPrivateWindow
                              backing: NSBackingStoreBuffered
                                defer: NO];
    if (self == nil)
        return nil;

    [self setLevel: NSMainMenuWindowLevel];
    [self setReleasedWhenClosed: NO];
    [self setHasShadow: NO];

    _barView = [[NSMainMenuView alloc]
            initWithFrame: NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))
                     menu: menu];
    [_barView setApplicationName: name];
    [_barView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [[self contentView] addSubview: _barView];
    [self placeAtTopOfScreen];
    return self;
}

- (void) dealloc {
    [_barView release];
    [super dealloc];
}

- (BOOL) canBecomeKeyWindow {
    return NO;
}

- (BOOL) canBecomeMainWindow {
    return NO;
}

- (void) setMainMenu: (NSMenu *) menu {
    [_barView setMenu: menu];
    [_barView setNeedsDisplay: YES];
}

- (void) setApplicationName: (NSString *) name {
    [_barView setApplicationName: name];
}

- (void) menuChanged {
    [_barView setNeedsDisplay: YES];
}

- (void) placeAtTopOfScreen {
    NSRect screen = [[NSScreen mainScreen] frame];
    CGFloat height = [NSMainMenuView menuHeight];

    [self setFrame: NSMakeRect(NSMinX(screen), NSMaxY(screen) - height,
                               NSWidth(screen), height)
           display: NO];
}

@end

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

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserver: self
               selector: @selector(applicationActivationChanged:)
                   name: NSApplicationDidBecomeActiveNotification
                 object: nil];
    [center addObserver: self
               selector: @selector(applicationActivationChanged:)
                   name: NSApplicationDidResignActiveNotification
                 object: nil];
    [center addObserver: self
               selector: @selector(menuStructureChanged:)
                   name: NSMenuDidAddItemNotification
                 object: nil];
    [center addObserver: self
               selector: @selector(menuStructureChanged:)
                   name: NSMenuDidRemoveItemNotification
                 object: nil];
    [center addObserver: self
               selector: @selector(menuStructureChanged:)
                   name: NSMenuDidChangeItemNotification
                 object: nil];
    return self;
}

- (void) dealloc {
    [self stopRedrawingBar];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_exporter invalidate];
    [_exporter release];
    [_bar close];
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

    _exporter = [[X11DBusMenu alloc] initWithSessionBus];
    [_exporter setDelegate: self];
    [_exporter setApplicationName: applicationName()];
}

#pragma mark - Windows

- (void) publishMenuOnWindow: (Window) window {
    NSString *service = [_exporter busName];
    NSString *path = [X11DBusMenu menuObjectPath];

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
    [_bar setMainMenu: _menu];

    for (NSNumber *window in _windows) {
        if (_menu != nil)
            [self publishMenuOnWindow: [window unsignedLongValue]];
        else if (hadMenu)
            [self withdrawMenuFromWindow: [window unsignedLongValue]];
    }
    [self updateBar];
}

// Whether a menu was changed that belongs to the main menu.
- (void) menuStructureChanged: (NSNotification *) notification {
    if (_menu == nil)
        return;

    NSMenu *menu = [notification object];

    while ([menu supermenu] != nil && menu != _menu)
        menu = [menu supermenu];
    if (menu != _menu)
        return;

    [_exporter menuChanged];
    [_bar menuChanged];
}

- (void) applicationActivationChanged: (NSNotification *) notification {
    [self updateBar];
}

- (void) dbusMenuRegistrarChanged: (X11DBusMenu *) menu {
    [self updateBar];
}

#pragma mark - Menu bar

// The bar is shown while the application is active, has a main menu and the
// desktop shows no global menu.
- (void) updateBar {
    BOOL globalMenu = _exporter != nil && [_exporter registrarPresent];
    BOOL wanted = _menu != nil && NSApp != nil && [NSApp isActive] && !globalMenu;

    if (!wanted) {
        [self stopRedrawingBar];
        [_bar orderOut: nil];
        return;
    }

    if (_bar == nil)
        _bar = [[X11MenuBarWindow alloc] initWithMenu: _menu
                                      applicationName: applicationName()];
    [_bar placeAtTopOfScreen];
    [_bar orderFront: nil];
    [self startRedrawingBar];
}

static void redrawBar(CFRunLoopObserverRef observer, CFRunLoopActivity activity,
                      void *info) {
    [[(X11AppMenu *) info bar] displayIfNeeded];
}

- (X11MenuBarWindow *) bar {
    return _bar;
}

// Before the run loop sleeps, which includes the waits of the loops that track
// the mouse in a menu.
- (void) startRedrawingBar {
    if (_displayObserver != NULL)
        return;

    CFRunLoopObserverContext context = {.version = 0, .info = self};

    _displayObserver = CFRunLoopObserverCreate(kCFAllocatorDefault,
                                               kCFRunLoopBeforeWaiting, true, 0,
                                               redrawBar, &context);
    CFRunLoopAddObserver(CFRunLoopGetMain(), _displayObserver,
                         kCFRunLoopCommonModes);
}

- (void) stopRedrawingBar {
    if (_displayObserver == NULL)
        return;
    CFRunLoopObserverInvalidate(_displayObserver);
    CFRelease(_displayObserver);
    _displayObserver = NULL;
}

@end
