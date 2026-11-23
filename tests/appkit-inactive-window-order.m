/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Two processes for appkit-inactive-window-order-{x11,wayland}.sh: an application that is the active
// one, and another application that is not active and orders a borderless window of its own in and
// out again and again.
//
//   a <seconds>          the active application: a titled window, "wmh-a-main", made key. Prints
//                        READY, then keeps running.
//   b <w> <h> <cycles> [<behavior> [<later behavior>]]   ("ba" instead of "b": an accessory application,
//                        like one whose Info.plist says LSUIElement; its windows are listed all the same)
//                        the inactive application: one borderless window "wmh-b-win" of that size
//                        that can become key and main, no parent, with that collection behavior
//                        (default 0x248: full-screen none, ignores the cycle, transient), ordered in with
//                        -makeKeyAndOrderFront: and out with -orderOut: <cycles> times. With a later behavior the window is ordered in once and given
//                        that behavior while it is on screen (WARM follows). Prints
//                        "B <n> active=<-[NSApp isActive]>" per cycle, WARM after the first cycle
//                        (the application counts as active until another one has the focus) and DONE
//                        at the end. It never activates itself.
//
// On macOS ordering a window in does not make an application the active one, so the active
// application keeps the keyboard focus, and a window whose collection behavior says it is transient or
// ignores the window cycle is left out of the Dock's window list, Mission Control and Cmd-`. With
// behavior 0 the window is a normal window of a regular application, which they list.
#import <AppKit/AppKit.h>
#import "test-argument-words.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface WMHWindow : NSWindow
@end
@implementation WMHWindow
- (BOOL) canBecomeKeyWindow { return YES; }
- (BOOL) canBecomeMainWindow { return YES; }
@end

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s a <seconds> | b <w> <h> <cycles>\n", argv[0]);
            return 2;
        }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: strcmp(argv[1], "ba") == 0 ? NSApplicationActivationPolicyAccessory
                                                                : NSApplicationActivationPolicyRegular];
        if (strcmp(argv[1], "a") == 0) {
            NSWindow *main = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 500, 500, 350)
                                                         styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable
                                                           backing: NSBackingStoreBuffered
                                                             defer: NO];
            [main setTitle: @"wmh-a-main"];
            [main setReleasedWhenClosed: NO];
            [main makeKeyAndOrderFront: nil];
            [NSApp activateIgnoringOtherApps: YES];
            spin(1.5);
            printf("READY\n");
            fflush(stdout);
            spin(argc > 2 ? atof(argv[2]) : 30);
            return 0;
        }
        double w = argc > 2 ? atof(argv[2]) : 90, h = argc > 3 ? atof(argv[3]) : 70;
        int cycles = argc > 4 ? atoi(argv[4]) : 12;
        WMHWindow *win = [[WMHWindow alloc] initWithContentRect: NSMakeRect(700, 400, w, h)
                                                      styleMask: NSWindowStyleMaskBorderless
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];
        [win setTitle: @"wmh-b-win"];
        [win setReleasedWhenClosed: NO];
        [win setCollectionBehavior: argc > 5 ? (NSWindowCollectionBehavior) strtol(argv[5], NULL, 0) : 0x248];
        // A launched application counts as active until another application has the focus, so the
        // first cycle is a warm-up (WARM follows it); the checks start after it.
        TestIgnoreArgumentWords();
        [NSApp finishLaunching];
        if (argc > 6) {
            // The collection behavior changes after the window is on screen (argv[6]): the window must
            // tell the window system. The window stays ordered in; WARM follows the change.
            [win makeKeyAndOrderFront: nil];
            spin(1.5);
            [win setCollectionBehavior: (NSWindowCollectionBehavior) strtol(argv[6], NULL, 0)];
            printf("WARM\n");
            fflush(stdout);
            spin(cycles * 0.7);
            printf("DONE\n");
            return 0;
        }
        for (int i = 0; i < cycles; i++) {
            if (i == 1) {
                printf("WARM\n");
                fflush(stdout);
            }
            [win makeKeyAndOrderFront: nil];
            spin(0.4);
            printf("B %d active=%d\n", i, [NSApp isActive]);
            fflush(stdout);
            [win orderOut: nil];
            spin(0.3);
        }
        printf("DONE\n");
        fflush(stdout);
    }
    return 0;
}
