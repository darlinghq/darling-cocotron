// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// A scroll wheel event from a finger on a touchpad (wl_pointer axis events with the finger source, ended by an
// axis_stop) reaches a view as a precise scrolling event with a gesture phase, through a real compositor. Run it
// under tests/appkit-wayland-finger-scroll.sh with DARLING_APPKIT_BACKEND=wayland: it shows a window titled
// "finger-scroll", prints READY, and prints one "EVENT precise=<0|1> phase=<n> dx=<n> dy=<n>" line for each
// scroll event the window's content view gets (phase: NSEventPhase raw value). Runs for the number of seconds
// in its first argument.
//   documentation: https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas
//                  https://developer.apple.com/documentation/appkit/nsevent/phase-swift.property
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface ScrollView : NSView
@end

@implementation ScrollView
- (void) scrollWheel: (NSEvent *) event {
    printf("EVENT precise=%d phase=%lu dx=%.1f dy=%.1f\n", [event hasPreciseScrollingDeltas] ? 1 : 0,
           (unsigned long) [event phase], [event scrollingDeltaX], [event scrollingDeltaY]);
    fflush(stdout);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setReleasedWhenClosed: NO];
        [window setTitle: @"finger-scroll"];
        [window setContentView: [[ScrollView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)]];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        puts("READY");
        fflush(stdout);
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow: argc > 1 ? atof(argv[1]) : 30];
        while ([end timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event != nil)
                [NSApp sendEvent: event];
        }
    }
    return 0;
}
