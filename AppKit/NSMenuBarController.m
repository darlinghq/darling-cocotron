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

#import "private-include/AppKit/NSMenuBarController.h"
#import "NSWindow-Private.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSMainMenuView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSScreen.h>

@implementation NSMenuBarWindow

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

@implementation NSMenuBarController

static NSString *applicationName(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *name = [bundle objectForInfoDictionaryKey: @"CFBundleDisplayName"];

    if ([name length] == 0)
        name = [bundle objectForInfoDictionaryKey: @"CFBundleName"];
    if ([name length] == 0)
        name = [[NSProcessInfo processInfo] processName];
    return name;
}

- (instancetype) initWithDelegate: (id<NSMenuBarControllerDelegate>) delegate {
    if ((self = [super init]) == nil)
        return nil;

    _delegate = delegate;

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
    [self cancelHide];
    [self stopRedrawingBar];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_bar close];
    [_bar release];
    [_menu release];
    [super dealloc];
}

- (void) setMainMenu: (NSMenu *) menu {
    if (menu == _menu)
        return;

    [_menu release];
    _menu = [menu retain];
    [_bar setMainMenu: _menu];
    [self update];
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

    if ([_delegate respondsToSelector: @selector(menuBarControllerMenuDidChange:)])
        [_delegate menuBarControllerMenuDidChange: self];
    [_bar menuChanged];
}

- (void) applicationActivationChanged: (NSNotification *) notification {
    [self update];
}

// Whether the application asks for the menu bar to be out of the way: through
// its presentation options, or because a window of it is in full screen mode
// (it has the full screen style), where the menu bar is hidden as well.
static BOOL menuBarHiddenByApplication(void) {
    NSApplicationPresentationOptions options = [NSApp presentationOptions];

    if (options & (NSApplicationPresentationHideMenuBar |
                   NSApplicationPresentationAutoHideMenuBar))
        return YES;

    return ([[NSApp keyWindow] styleMask] & NSWindowStyleMaskFullScreen) != 0 ||
           ([[NSApp mainWindow] styleMask] & NSWindowStyleMaskFullScreen) != 0;
}

// The bar is shown while the application is active, has a main menu and the
// desktop shows no global menu, unless the application hides the menu bar.
- (BOOL) barWanted {
    return _menu != nil && NSApp != nil && [NSApp isActive] &&
           ![_delegate menuBarControllerDesktopShowsMenu: self] &&
           !menuBarHiddenByApplication();
}

// How long the bar stays after the application stopped being active.
static const NSTimeInterval barHideDelay = 0.5;

// Whether the bar would be wanted if the application were active.
- (BOOL) barWantedWhileActive {
    return _menu != nil && NSApp != nil &&
           ![_delegate menuBarControllerDesktopShowsMenu: self] &&
           !menuBarHiddenByApplication();
}

- (void) cancelHide {
    [_hideTimer invalidate];
    _hideTimer = nil;
}

- (void) hideTimerFired: (NSTimer *) timer {
    _hideTimer = nil;
    [self update];
}

- (void) update {
    // Presentation options and window styles have no notification of their
    // own, so the observer below keeps checking while the application has a
    // main menu.
    if (_menu == nil)
        [self stopRedrawingBar];
    else
        [self startRedrawingBar];

    if (![self barWanted]) {
        if (_barShown && [self barWantedWhileActive]) {
            // Inactive, which may be a moment between two windows: wait before hiding.
            if (_hideTimer == nil) {
                _hideTimer = [NSTimer timerWithTimeInterval: barHideDelay
                                                     target: self
                                                   selector: @selector(hideTimerFired:)
                                                   userInfo: nil
                                                    repeats: NO];
                [[NSRunLoop currentRunLoop] addTimer: _hideTimer forMode: NSRunLoopCommonModes];
            }
            return;
        }
        [self cancelHide];
        [_bar orderOut: nil];
        _barShown = NO;
        // This can run from the run loop observer with no event to flush it.
        [_delegate menuBarControllerDidUpdateBar: self];
        return;
    }

    [self cancelHide];
    if (_bar == nil)
        _bar = [[NSMenuBarWindow alloc] initWithMenu: _menu
                                     applicationName: applicationName()];
    [_bar placeAtTopOfScreen];
    [_bar orderFront: nil];
    _barShown = YES;
    [_delegate menuBarControllerDidUpdateBar: self];
}

static void redrawBar(CFRunLoopObserverRef observer, CFRunLoopActivity activity,
                      void *info) {
    NSMenuBarController *controller = info;

    if ([controller barWanted] != [controller barShown])
        [controller update];
    [[controller bar] displayIfNeeded];
}

- (BOOL) barShown {
    return _barShown;
}

- (NSMenuBarWindow *) bar {
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
