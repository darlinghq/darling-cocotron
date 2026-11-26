// Copyright (C) 2026 Lubos Dolezel
//
// A pop-up menu and its submenu stay open without the application losing its active state. The documentation of
// NSApplicationDidResignActiveNotification
// (https://developer.apple.com/documentation/appkit/nsapplication/didresignactivenotification) says it is posted
// when the application stops being the active one; showing a menu, or a submenu of it, does not make another
// application active, so no such notification may arrive, and -[NSApplication isActive] stays YES while the
// menus are open. (On Wayland each menu is a pop-up surface that takes the keyboard from the previous one when it
// opens, and the window system says so with a focus loss and a focus gain; on X11 the menus are override-redirect
// windows.)
// A click on the window opens the menu "One", "More" (submenu "Sub A", "Sub B"), "Three" at its top left;
// the harness clicks "More", then outside the menus. The program prints
//   ITEM <index> <x> <y> <w> <h>        each item of the menu, relative to the window's top left corner (y down)
//   CLICK <x> <y>                        where the first click was, in the window (y down)
//   OPEN                                 the menu is on screen
//   SUBITEM <index> <x> <y> <w> <h>     each item of the submenu, in the same coordinates
//   SUBOPEN active=<0|1> resigns=<n>    the submenu is on screen, with the state then
//   RESULT YES|NO                        the pop-up call returned
//   FINAL active=<0|1> resigns=<n>      after the menus have closed
// Lines starting with FAIL report a check that failed. Run by appkit-menu-submenu-keeps-active-x11.sh and
// -wayland.sh; the argument is how long to run, in seconds.
#import <AppKit/AppKit.h>
#import "../AppKit/NSMenu.subproj/NSMenuView.h"
#import "../AppKit/NSMenu.subproj/NSMenuWindow.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSMenuView (ItemRect)
- (NSRect) rectForItemAtIndex: (NSUInteger) index;
@end

static NSMenu *menu;
static NSWindow *host;
static int resigns, opened, subOpened, finished;

@interface Target : NSObject
@end
@implementation Target
- (void) choose: (NSMenuItem *) sender {
    printf("ACTION %s\n", [[sender title] UTF8String]);
    fflush(stdout);
}
- (void) resigned: (NSNotification *) note {
    resigns++;
}
@end

static NSArray *menuWindows(void) {
    NSMutableArray *windows = [NSMutableArray array];
    for (NSWindow *window in [NSApp windows])
        if ([window isKindOfClass: [NSMenuWindow class]] && [window isVisible])
            [windows addObject: window];
    return windows;
}

static void printItems(const char *label, NSWindow *window, NSUInteger count) {
    NSMenuView *view = [(NSMenuWindow *) window menuView];
    NSRect hostFrame = [host frame];
    for (NSUInteger i = 0; i < count; i++) {
        NSRect rect = [view rectForItemAtIndex: i];
        NSPoint topLeft = [window convertBaseToScreen: [view convertPoint: rect.origin toView: nil]];
        printf("%s %lu %d %d %d %d\n", label, (unsigned long) i, (int) lround(topLeft.x - NSMinX(hostFrame)),
               (int) lround(NSMaxY(hostFrame) - topLeft.y), (int) rect.size.width, (int) rect.size.height);
    }
}

static void report(void) {
    NSArray *windows = menuWindows();
    if ([windows count] >= 1 && !opened) {
        opened = 1;
        printItems("ITEM", [windows objectAtIndex: 0], 3);
        printf("OPEN\n");
    }
    if ([windows count] >= 2 && !subOpened) {
        subOpened = 1;
        printItems("SUBITEM", [windows objectAtIndex: 1], 2);
        printf("SUBOPEN active=%d resigns=%d\n", (int) [NSApp isActive], resigns);
    }
    fflush(stdout);
}

@interface HostView : NSView
@end
@implementation HostView
- (BOOL) isFlipped { return YES; }
- (BOOL) acceptsFirstMouse: (NSEvent *) event { return YES; }
- (void) mouseDown: (NSEvent *) event {
    if (finished)
        return;
    NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
    printf("CLICK %d %d\n", (int) lround(p.x), (int) lround(p.y));
    fflush(stdout);
    BOOL result = [menu popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 40) inView: self];
    printf("RESULT %s\n", result ? "YES" : "NO");
    finished = 1;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 60;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

        Target *target = [Target new];
        [[NSNotificationCenter defaultCenter] addObserver: target selector: @selector(resigned:)
                                                     name: NSApplicationDidResignActiveNotification object: nil];
        menu = [[NSMenu alloc] initWithTitle: @"Pop-up"];
        [[menu addItemWithTitle: @"One" action: @selector(choose:) keyEquivalent: @""] setTarget: target];
        NSMenuItem *more = [menu addItemWithTitle: @"More" action: NULL keyEquivalent: @""];
        NSMenu *submenu = [[NSMenu alloc] initWithTitle: @"More"];
        [[submenu addItemWithTitle: @"Sub A" action: @selector(choose:) keyEquivalent: @""] setTarget: target];
        [[submenu addItemWithTitle: @"Sub B" action: @selector(choose:) keyEquivalent: @""] setTarget: target];
        [more setSubmenu: submenu];
        [[menu addItemWithTitle: @"Three" action: @selector(choose:) keyEquivalent: @""] setTarget: target];

        host = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 500, 400)
                                           styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                             backing: NSBackingStoreBuffered
                                               defer: NO];
        [host setTitle: @"menu-host"];
        [host setContentView: [[HostView alloc] initWithFrame: NSMakeRect(0, 0, 500, 400)]];
        [host makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];

        NSTimer *probe = [NSTimer timerWithTimeInterval: 0.1 repeats: YES block: ^(NSTimer *timer) { report(); }];
        [[NSRunLoop currentRunLoop] addTimer: probe forMode: NSRunLoopCommonModes];
        [[NSRunLoop currentRunLoop] addTimer: probe forMode: NSEventTrackingRunLoopMode];

        printf("READY\n");
        fflush(stdout);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
        while ([deadline timeIntervalSinceNow] > 0 && !finished) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event != nil)
                [NSApp sendEvent: event];
        }
        // Let the window system's late messages arrive before the final state is read.
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
        printf("FINAL active=%d resigns=%d\n", (int) [NSApp isActive], resigns);
        printf("DONE\n");
    }
    return 0;
}
