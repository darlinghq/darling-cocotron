/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A windowed process for driver.m: shows one titled window, prints "READY <pid>" once it is
// on screen and "STATE <0|1>" whenever -[NSApplication isActive] changes, and exits by
// itself after a while in case the driver is gone.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface Poller : NSObject
- (void) poll: (NSTimer *) timer;
@end

static int lastState = -1;

@implementation Poller
- (void) poll: (NSTimer *) timer {
    int state = [NSApp isActive] ? 1 : 0;
    if (state != lastState) {
        lastState = state;
        printf("STATE %d\n", state);
    }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: helper <title> <x>\n");
            return 2;
        }
        setvbuf(stdout, NULL, _IOLBF, 0);
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(atoi(argv[2]), 200, 240, 140)
                          styleMask: NSWindowStyleMaskTitled
                            backing: NSBackingStoreBuffered
                              defer: NO];
        [window setTitle: [NSString stringWithUTF8String: argv[1]]];
        [window makeKeyAndOrderFront: nil];

        Poller *poller = [[Poller alloc] init];
        [NSTimer scheduledTimerWithTimeInterval: 0.1 target: poller
                                       selector: @selector(poll:) userInfo: nil repeats: YES];
        NSDate *start = [NSDate date];
        BOOL ready = NO;
        while ([start timeIntervalSinceNow] > -60) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event != nil)
                [NSApp sendEvent: event];
            if (!ready && [start timeIntervalSinceNow] < -1.5) {
                ready = YES;
                printf("READY %d\n", (int) getpid());
            }
        }
    }
    return 0;
}
