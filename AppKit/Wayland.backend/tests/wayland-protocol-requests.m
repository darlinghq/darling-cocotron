// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// Guest side of wayland-protocol-requests.sh: an application that does what the staging Wayland
// protocols of the AppKit and CoreGraphics backends are used for, one thing after another, and prints
// a marker before each step so that the driver can find the requests that step caused in the
// WAYLAND_DEBUG log. Usage: wayland-protocol-requests <seconds to wait for the pointer>
//   STEP bell        NSBeep()
//   STEP title       a new title (the toplevel's description changes, its tag does not)
//   STEP sheet       a sheet on the window, closed again
//   STEP modal       a window in an application modal session, closed again
//   STEP pointer     [NSCursor set] and CGWarpMouseCursorPosition(), when the pointer entered the window
//   STEP idle        no power assertion is held: CGDisplayIsAsleep() is queried, the display is not asleep
//   STEP assert      kIOPMAssertPreventUserIdleDisplaySleep is taken, as an application that plays video does
//   STEP release     the assertion is released again
//   STEP alpha       NSWindow.alphaValue 0.5, then 0 (the window is unmapped), then 1
// Needs no compositor feature: every step must also work, and do nothing special, on a compositor
// without the protocol.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#include <stdio.h>
#include <unistd.h>

static void step(const char *name) {
    fprintf(stderr, "STEP %s\n", name);
    fflush(stderr);
}

static void runLoop(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static BOOL g_entered;

int main(int argc, char **argv) {
    @autoreleasepool {
        double pointerWait = argc > 1 ? atof(argv[1]) : 0;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 500, 400)
                                                       styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"Protocol probe"];
        [window setAcceptsMouseMovedEvents: YES];
        [NSApp finishLaunching];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        [NSEvent addLocalMonitorForEventsMatchingMask: NSEventMaskMouseEntered | NSEventMaskMouseMoved
                                              handler: ^NSEvent *(NSEvent *event) {
            g_entered = YES;
            return event;
        }];
        runLoop(1.5);
        fprintf(stderr, "READY\n");
        fflush(stderr);

        step("bell");
        NSBeep();
        runLoop(0.5);

        step("title");
        [window setTitle: @"Retitled probe"];
        runLoop(0.5);

        step("sheet");
        NSWindow *sheet = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 120)
                                                      styleMask: NSWindowStyleMaskTitled
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];
        [window beginSheet: sheet completionHandler: nil];
        runLoop(1);
        [window endSheet: sheet];
        [sheet orderOut: nil];
        runLoop(0.5);

        step("modal");
        NSWindow *modal = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 300, 120)
                                                      styleMask: NSWindowStyleMaskTitled
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];
        // A modal session runs the loop in its own mode, so the timer has to be in every mode.
        NSTimer *stopper = [NSTimer timerWithTimeInterval: 1 repeats: NO block: ^(NSTimer *timer) {
            [NSApp stopModal];
        }];
        [[NSRunLoop currentRunLoop] addTimer: stopper forMode: NSRunLoopCommonModes];
        [NSApp runModalForWindow: modal];
        [modal orderOut: nil];
        runLoop(0.5);

        step("pointer");
        // The pointer entered the window when events for it arrive or its location is not the start's.
        NSPoint start = [NSEvent mouseLocation];
        for (double waited = 0; !g_entered && waited < pointerWait; waited += 0.1) {
            runLoop(0.1);
            NSPoint now = [NSEvent mouseLocation];
            if (now.x != start.x || now.y != start.y)
                g_entered = YES;
        }
        fprintf(stderr, "POINTER entered=%d\n", g_entered);
        if (g_entered) {
            // The pointer keeps moving across the window, so ask repeatedly: a cursor is only applied
            // while the pointer is over the window, and a warp has to target a point of its surface.
            CGFloat screenHeight = [[[NSScreen screens] objectAtIndex: 0] frame].size.height;
            for (int i = 0; i < 8; i++) {
                [[NSCursor pointingHandCursor] set];
                runLoop(0.1);
                [[NSCursor IBeamCursor] set];
                runLoop(0.1);
                NSPoint here = [NSEvent mouseLocation];
                CGWarpMouseCursorPosition(CGPointMake(here.x + 5, screenHeight - here.y + 5));
                runLoop(0.1);
            }
        }

        step("idle");
        // The window is visible and nothing asks for the display to stay awake.
        fprintf(stderr, "ASLEEP %d\n", CGDisplayIsAsleep(CGMainDisplayID()) ? 1 : 0);
        runLoop(1);

        step("assert");
        IOPMAssertionID assertion = kIOPMNullAssertionID;
        IOReturn created = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep,
                                                       kIOPMAssertionLevelOn, CFSTR("Protocol probe"),
                                                       &assertion);
        fprintf(stderr, "ASSERTION created=%d\n", created == kIOReturnSuccess);
        // Power management tells the process, which asks the compositor, from other threads and queues.
        runLoop(2);

        step("release");
        fprintf(stderr, "ASSERTION released=%d\n", IOPMAssertionRelease(assertion) == kIOReturnSuccess);
        runLoop(2);

        step("alpha");
        [window setAlphaValue: 0.5];
        runLoop(0.5);
        [window setAlphaValue: 0];
        runLoop(0.5);
        [window setAlphaValue: 1];
        runLoop(0.5);
        fprintf(stderr, "PROBE done\n");
    }
    return 0;
}
