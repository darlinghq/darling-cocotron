/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSMenu popUpMenuPositioningItem:atLocation:inView:] shows the menu with the
// top left corner of the given item at the given location in the view's
// coordinates; with no item, the top left of the menu goes there; with no view,
// the location is in screen coordinates. It returns YES when an item was chosen
// (after sending its action) and NO when tracking was cancelled; an item that
// is not in the menu shows nothing and returns NO. A menu opened at the
// bottom right corner of the screen is moved to stay on it ("clamp", checked
// first and cancelled with Escape).
//
// Each click on the window opens the next case from the view's -mouseDown:, as
// a drop-down control does:
//   1. item "Two" at (60, 80) in the (flipped) view; the harness chooses "Two"
//   2. no item, no view, at the screen point of (200, 50) in the view; the
//      harness chooses "Three"
//   3. item "One" at (100, 100) in the view; the harness clicks outside the menu
// While a menu is open the program checks where it is and prints
//   ITEM <case> <index> <x> <y> <w> <h>
// for each item, relative to the window's top left corner (y downwards), then
//   OPEN <case>
// and when the call returns, "RESULT <case> YES|NO" after any "ACTION <title>".
// Lines starting with FAIL report a check that failed. Run by
// appkit-menu-popup-positioning-x11.sh and -wayland.sh; the argument is how
// long to run, in seconds.
#import <AppKit/AppKit.h>
#import "../AppKit/NSMenu.subproj/NSMenuView.h"
#import "../AppKit/NSMenu.subproj/NSMenuWindow.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSWindow (PlatformWindow)
- (id) platformWindow;
@end

// The view of a pop-up menu window lays its items out like this (NSSubmenuView).
@interface NSMenuView (ItemRect)
- (NSRect) rectForItemAtIndex: (NSUInteger) index;
@end

static NSMenu *menu;
static NSWindow *host;
static int currentCase, reportedCase;
static NSPoint expectedAnchor; // screen coordinates
static NSInteger expectedIndex; // NSNotFound: the menu's own top left

@interface Target : NSObject
@end

@implementation Target
- (void) choose: (NSMenuItem *) sender {
    printf("ACTION %s\n", [[sender title] UTF8String]);
    fflush(stdout);
}
@end

static NSMenuWindow *openMenuWindow(void) {
    for (NSWindow *window in [NSApp windows])
        if ([window isKindOfClass: [NSMenuWindow class]] && [window isVisible])
            return (NSMenuWindow *) window;
    return nil;
}

static void report(void) {
    NSMenuWindow *window = openMenuWindow();
    if (window == nil || reportedCase == currentCase)
        return;
    reportedCase = currentCase;

    NSMenuView *view = [window menuView];
    NSRect hostFrame = [host frame];
    NSPoint anchor;
    if (expectedIndex == NSNotFound) {
        anchor = NSMakePoint(NSMinX([window frame]), NSMaxY([window frame]));
    } else {
        NSRect rect = [view rectForItemAtIndex: expectedIndex];
        anchor = [window convertBaseToScreen: [view convertPoint: rect.origin toView: nil]];
    }
    if (fabs(anchor.x - expectedAnchor.x) > 0.5 || fabs(anchor.y - expectedAnchor.y) > 0.5)
        printf("FAIL case %d: anchor at %g,%g, expected %g,%g\n", currentCase, anchor.x, anchor.y,
               expectedAnchor.x, expectedAnchor.y);

    id platform = [window respondsToSelector: @selector(platformWindow)] ? [window platformWindow] : nil;
    if ([platform respondsToSelector: @selector(isPopup)])
        printf("POPUP %d %d\n", currentCase, (int) [platform isPopup]);

    for (NSInteger i = 0; i < [menu numberOfItems]; i++) {
        NSRect rect = [view rectForItemAtIndex: i];
        NSPoint topLeft = [window convertBaseToScreen: [view convertPoint: rect.origin toView: nil]];
        printf("ITEM %d %ld %d %d %d %d\n", currentCase, (long) i, (int) lround(topLeft.x - NSMinX(hostFrame)),
               (int) lround(NSMaxY(hostFrame) - topLeft.y), (int) rect.size.width, (int) rect.size.height);
    }
    printf("OPEN %d\n", currentCase);
    fflush(stdout);
}

@interface HostView : NSView
@end

@implementation HostView
- (BOOL) isFlipped {
    return YES;
}

- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

- (NSPoint) screenPointOf: (NSPoint) point {
    return [[self window] convertBaseToScreen: [self convertPoint: point toView: nil]];
}

- (void) mouseDown: (NSEvent *) event {
    BOOL result;

    currentCase++;
    switch (currentCase) {
    case 1:
        expectedIndex = 1;
        expectedAnchor = [self screenPointOf: NSMakePoint(60, 80)];
        result = [menu popUpMenuPositioningItem: [menu itemAtIndex: 1] atLocation: NSMakePoint(60, 80) inView: self];
        break;
    case 2:
        expectedIndex = NSNotFound;
        expectedAnchor = [self screenPointOf: NSMakePoint(200, 50)];
        result = [menu popUpMenuPositioningItem: nil atLocation: expectedAnchor inView: nil];
        break;
    case 3:
        expectedIndex = 0;
        expectedAnchor = [self screenPointOf: NSMakePoint(100, 100)];
        result = [menu popUpMenuPositioningItem: [menu itemAtIndex: 0] atLocation: NSMakePoint(100, 100) inView: self];
        break;
    default:
        return;
    }
    if (reportedCase != currentCase)
        printf("FAIL case %d: no menu window was seen while tracking\n", currentCase);
    printf("RESULT %d %s\n", currentCase, result ? "YES" : "NO");
    fflush(stdout);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 60;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

        Target *target = [Target new];
        menu = [[NSMenu alloc] initWithTitle: @"Pop-up"];
        for (NSString *title in @[@"One", @"Two", @"Three"])
            [[menu addItemWithTitle: title action: @selector(choose:) keyEquivalent: @""] setTarget: target];

        // An item from another menu is not positioned: nothing is shown.
        NSMenu *other = [[NSMenu alloc] initWithTitle: @"Other"];
        NSMenuItem *foreign = [other addItemWithTitle: @"Foreign" action: NULL keyEquivalent: @""];
        if ([menu popUpMenuPositioningItem: foreign atLocation: NSMakePoint(100, 100) inView: nil] ||
            openMenuWindow() != nil)
            printf("FAIL: an item of another menu was accepted\n");

        host = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 500, 400)
                                           styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                             backing: NSBackingStoreBuffered
                                               defer: NO];
        [host setTitle: @"menu-host"];
        [host setContentView: [[HostView alloc] initWithFrame: NSMakeRect(0, 0, 500, 400)]];
        [host makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];

        NSTimer *probe = [NSTimer timerWithTimeInterval: 0.2 repeats: YES block: ^(NSTimer *timer) {
          report();
        }];
        [[NSRunLoop currentRunLoop] addTimer: probe forMode: NSRunLoopCommonModes];
        [[NSRunLoop currentRunLoop] addTimer: probe forMode: NSEventTrackingRunLoopMode];

        // The menu stays on the screen: opened at the bottom right corner of
        // the screen's visible area, it is moved up and to the left to fit.
        // The probe checks it and cancels the tracking with -cancelTracking.
        NSRect visible = [([host screen] ?: [NSScreen mainScreen]) visibleFrame];
        __block BOOL clampSeen = NO;
        NSTimer *clamp = [NSTimer timerWithTimeInterval: 0.2 repeats: YES block: ^(NSTimer *timer) {
          NSMenuWindow *window = openMenuWindow();
          if (window == nil || clampSeen || currentCase != 0)
              return;
          clampSeen = YES;
          NSRect f = [window frame];
          if (NSContainsRect(visible, f))
              printf("PASS clamp: menu at %g,%g %gx%g inside the visible frame\n", f.origin.x, f.origin.y,
                     f.size.width, f.size.height);
          else
              printf("FAIL clamp: menu at %g,%g %gx%g, visible frame %g,%g %gx%g\n", f.origin.x, f.origin.y,
                     f.size.width, f.size.height, visible.origin.x, visible.origin.y, visible.size.width,
                     visible.size.height);
          [menu cancelTracking];
        }];
        [[NSRunLoop currentRunLoop] addTimer: clamp forMode: NSRunLoopCommonModes];
        [[NSRunLoop currentRunLoop] addTimer: clamp forMode: NSEventTrackingRunLoopMode];
        BOOL clampResult = [menu popUpMenuPositioningItem: nil
                                               atLocation: NSMakePoint(NSMaxX(visible) - 5, NSMinY(visible) + 5)
                                                   inView: nil];
        [clamp invalidate];
        if (!clampSeen)
            printf("FAIL clamp: no menu window was seen\n");
        if (clampResult)
            printf("FAIL clamp: cancelled tracking returned YES\n");
        fflush(stdout);

        printf("READY\n");
        fflush(stdout);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
        while ([deadline timeIntervalSinceNow] > 0 && currentCase < 3) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event != nil)
                [NSApp sendEvent: event];
        }
        printf("DONE\n");
    }
    return 0;
}
