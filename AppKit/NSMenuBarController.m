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
#import <AppKit/NSGlobalMenu+Private.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <notify.h>
#include <dispatch/dispatch.h>
#include <unistd.h>

@interface NSWindow (NSMenuBarControllerStrip)
- (BOOL) hasMainMenu;
@end

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

    NSRect frame = NSMakeRect(NSMinX(screen), NSMaxY(screen) - height,
                              NSWidth(screen), height);

    if (!NSEqualRects(frame, [self frame]))
        [self setFrame: frame display: NO];
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
    _ownerToken = -1;

    // Another process becoming the front application, or the owner of the menu bar, or the focus
    // leaving the Darling applications is posted under this name.
    // The block does not retain the controller (a __block variable is not retained by a copied
    // block under manual reference counting); -dealloc cancels the registration.
    __block NSMenuBarController *controller = self;

    notify_register_dispatch(kCGSFrontProcessNotificationName, &_ownerToken, dispatch_get_main_queue(),
                             ^(int unused) {
                                 [controller refreshOwnership];
                                 [controller update];
                             });
    [self refreshOwnership];

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
    if (_ownerToken >= 0)
        notify_cancel(_ownerToken);
    _delegate = nil;
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
    [self refreshOwnership];
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

// Whether a visible window of the application carries the menu strip, so the
// menu has a place inside the application's windows.
static BOOL visibleWindowCarriesMenuStrip(void) {
    if (![NSWindow _usesInWindowMenuBar])
        return NO;

    for (NSWindow *window in [NSApp windows]) {
        if ([window isKindOfClass: [NSMenuBarWindow class]])
            continue;
        if ([window isVisible] && [window hasMainMenu])
            return YES;
    }
    return NO;
}

- (void) refreshOwnership {
    pid_t owner = 0;

    _ownsMenuBar = _CGSGetMenuBarOwnerProcess(&owner) == kCGErrorSuccess && owner == getpid();
}

// The bar is shown while the application owns the menu bar, has a main menu and
// the menu is neither in the desktop's global menu nor in the strip of a window,
// unless the application hides the menu bar. The owner is the application that
// became active last, unless that one is an agent application (LSUIElement),
// which leaves the menu bar to the one before it.
- (BOOL) barWanted {
    return [self barWantedWhileActive] && NSApp != nil && _ownsMenuBar;
}

// How long the bar stays after the application stopped being active.
static const NSTimeInterval barHideDelay = 0.5;

// Whether the bar would be wanted if the application were active.
- (BOOL) barWantedWhileActive {
    return _menu != nil && NSApp != nil &&
           ![_delegate menuBarControllerDesktopShowsMenu: self] &&
           !visibleWindowCarriesMenuStrip() && !menuBarHiddenByApplication();
}

- (void) cancelHide {
    [_hideTimer invalidate];
    _hideTimer = nil;
}

// The moment is over: the application did not become active again.
- (void) hideTimerFired: (NSTimer *) timer {
    _hideTimer = nil;
    [self refreshOwnership];
    [self updateWaitingForHide: NO];
}

- (void) update {
    [self updateWaitingForHide: YES];
}

// With waiting, a bar that is only wanted while the application is active
// stays for barHideDelay after the application stopped being active, and is
// hidden then.
- (void) updateWaitingForHide: (BOOL) waiting {
    // Presentation options and window styles have no notification of their
    // own, so the observer below keeps checking while the application has a
    // main menu.
    if (_menu == nil)
        [self stopRedrawingBar];
    else
        [self startRedrawingBar];

    if (![self barWanted]) {
        if (waiting && _barShown && [self barWantedWhileActive]) {
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
    // The bar is updated on every pass of the run loop that finds its state
    // changed; a bar that is already shown stays where it is.
    if (![_bar isVisible])
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
