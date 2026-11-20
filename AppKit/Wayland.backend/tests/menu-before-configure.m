// Copyright (C) 2026 Lubos Dolezel
//
// A menu opened right after its window was ordered in, before the compositor's first configure for
// that window, is still an xdg_popup of the window: a client cannot position a toplevel, so a menu
// that became one would be placed (and sized) by the compositor. Needs DARLING_APPKIT_BACKEND=wayland
// and WAYLAND_DEBUG=1 (the client log goes to stderr); menu-before-configure-check.py reads that log
// and checks it. Exits by itself after a short time.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface Driver : NSObject <NSApplicationDelegate> {
    NSWindow *window;
}
@end

@implementation Driver
- (void) quit: (NSTimer *) timer {
    printf("DONE\n");
    fflush(stdout);
    exit(0);
}

- (void) applicationDidFinishLaunching: (NSNotification *) note {
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 300)
                                         styleMask: NSTitledWindowMask
                                           backing: NSBackingStoreBuffered
                                             defer: NO];
    [window makeKeyAndOrderFront: nil];

    NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Test"];
    [menu addItemWithTitle: @"First" action: NULL keyEquivalent: @""];
    [menu addItemWithTitle: @"Second" action: NULL keyEquivalent: @""];
    [menu addItemWithTitle: @"Third" action: NULL keyEquivalent: @""];

    // The menu opens in the same run loop pass, before any event of the compositor was read.
    NSTimer *timer = [NSTimer timerWithTimeInterval: 2.0 target: self selector: @selector(quit:) userInfo: nil repeats: NO];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
    NSEvent *event = [NSEvent mouseEventWithType: NSLeftMouseDown
                                        location: NSMakePoint(60, 200)
                                   modifierFlags: 0
                                       timestamp: 0
                                    windowNumber: [window windowNumber]
                                         context: nil
                                     eventNumber: 0
                                      clickCount: 1
                                        pressure: 1];
    [NSMenu popUpContextMenu: menu withEvent: event forView: [window contentView]];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // The application's delegate is a weak reference under ARC.
        Driver *driver = [[Driver alloc] init];
        [NSApp setDelegate: driver];
        [NSApp run];
    }
    return 0;
}
