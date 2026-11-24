// SPDX-License-Identifier: MIT
// Run with a window server and the in-window menu strip (DarlingInWindowMenuBar), like
// appkit-menu-border-selection.m. All input is posted to this test's windows.
// In the menu opened from a title of the menu bar, Right opens the menu of the next title and Left
// that of the previous one, wrapping around; the bar is never left tracking with no menu open.
// Escape then ends the tracking.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface NSView (MenuTrackingTest)
- (NSMenuItem *) trackForEvent: (NSEvent *) event;
@end

static NSView *menuView(NSView *view, NSMenu *menu) {
    if ([view menu] == menu)
        return view;
    for (NSView *child in [view subviews]) {
        NSView *found = menuView(child, menu);
        if (found != nil)
            return found;
    }
    return nil;
}

static NSEvent *mouseEvent(NSEventType type, NSWindow *window, NSPoint point) {
    return [NSEvent mouseEventWithType: type location: point modifierFlags: 0
                            timestamp: [NSDate timeIntervalSinceReferenceDate]
                         windowNumber: [window windowNumber] context: nil
                          eventNumber: 0 clickCount: 1 pressure: 0];
}

static NSEvent *keyEvent(NSWindow *window, unichar character, unsigned short keyCode) {
    NSString *string = [NSString stringWithCharacters: &character length: 1];
    return [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: 0
                           timestamp: [NSDate timeIntervalSinceReferenceDate]
                        windowNumber: [window windowNumber] context: nil characters: string
         charactersIgnoringModifiers: string isARepeat: NO keyCode: keyCode];
}

// The menus opened, in order, as "One Two ...".
static NSMutableString *opened;
static int openMenus;

@interface Input : NSObject <NSMenuDelegate> {
@public
    NSWindow *window;
    NSView *barView;
    NSUInteger step;
}
@end

@implementation Input
- (void) menuWillOpen: (NSMenu *) menu {
    [opened appendFormat: @"%@ ", [menu title]];
    openMenus++;
}
- (void) menuDidClose: (NSMenu *) menu {
    openMenus--;
}
- (void) timeout: (NSTimer *) timer {
    printf("FAIL: menu tracking did not finish (opened: %s)\n", [opened UTF8String]);
    exit(1);
}
- (void) tick: (NSTimer *) timer {
    switch (step++) {
    case 0: {
        // The release of the press that opened the first menu: the menu stays open.
        NSPoint point = [barView convertPoint: NSMakePoint(15, NSMidY([barView bounds])) toView: nil];
        [NSApp postEvent: mouseEvent(NSLeftMouseUp, window, point) atStart: NO];
        break;
    }
    case 1:
    case 2:
        [NSApp postEvent: keyEvent(window, NSRightArrowFunctionKey, 124) atStart: NO];
        break;
    case 3:
        [NSApp postEvent: keyEvent(window, NSLeftArrowFunctionKey, 123) atStart: NO];
        break;
    default:
        [NSApp postEvent: keyEvent(window, 033, 53) atStart: NO];
        [timer invalidate];
        break;
    }
}
@end

static NSMenu *makeMenu(NSString *title, Input *input) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle: title];
    [menu setDelegate: input];
    [menu addItemWithTitle: @"Item" action: @selector(description) keyEquivalent: @""];
    return menu;
}

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        Input *input = [[Input alloc] init];
        opened = [NSMutableString new];
        NSMenu *bar = [[NSMenu alloc] initWithTitle: @"Menu test"];
        for (NSString *title in @[ @"One", @"Two", @"Three" ])
            [[bar addItemWithTitle: title action: NULL keyEquivalent: @""] setSubmenu: makeMenu(title, input)];
        [NSApp setMainMenu: bar];
        input->window = [[NSWindow alloc] initWithContentRect: NSMakeRect(50, 50, 360, 200)
                styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
        [input->window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        input->barView = menuView([[input->window contentView] superview], bar);
        if (input->barView == nil) {
            printf("FAIL: window menu bar is missing\n");
            return 1;
        }

        NSTimer *events = [NSTimer timerWithTimeInterval: 0.2 target: input
                selector: @selector(tick:) userInfo: nil repeats: YES];
        NSTimer *deadline = [NSTimer timerWithTimeInterval: 5 target: input
                selector: @selector(timeout:) userInfo: nil repeats: NO];
        [[NSRunLoop currentRunLoop] addTimer: events forMode: NSEventTrackingRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer: deadline forMode: NSEventTrackingRunLoopMode];
        NSPoint point = [input->barView convertPoint: NSMakePoint(15, NSMidY([input->barView bounds]))
                                              toView: nil];
        NSMenuItem *chosen = [input->barView trackForEvent: mouseEvent(NSLeftMouseDown, input->window, point)];
        [events invalidate];
        [deadline invalidate];

        int failures = 0;
        BOOL order = [opened isEqualToString: @"One Two Three Two "];
        printf("%s: Right and Left move between the menus of the bar (opened: %s)\n",
               order ? "PASS" : "FAIL", [opened UTF8String]);
        failures += !order;
        BOOL ended = chosen == nil && openMenus == 0 && input->step == 5;
        printf("%s: one Escape then closes the menu and ends the tracking\n", ended ? "PASS" : "FAIL");
        failures += !ended;
        return failures ? 1 : 0;
    }
}
