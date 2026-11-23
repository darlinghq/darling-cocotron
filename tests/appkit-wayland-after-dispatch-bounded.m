/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The Wayland backend's work queued for after the event dispatch must not keep
// the main thread out of the run loop: a pass runs the blocks that were queued
// before it, and blocks queued by those wait for the next run loop iteration
// (a view whose frame alternates keeps queueing more work; a pass that ran
// until the queue is empty never returned). Checks that a chain of blocks, each
// queueing the next, is spread over many run loop iterations, that one pass
// runs all blocks queued before it and none queued during it, and that timers
// keep firing while the chain runs.
// Needs a compositor: run with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY
// set to the compositor's socket (a host path). Prints SKIP when the backend is
// not selected.
#import <AppKit/AppKit.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

@interface NSObject (WaylandAfterDispatchProbe)
+ (id) currentDisplay;
- (void) performAfterDispatch: (void (^)(void)) block;
- (void) processPendingEvents;
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static void on_alarm(int sig) {
    (void) sig;
    printf("FAIL: timed out (the run loop was starved)\n");
    fflush(stdout);
    _exit(1);
}

enum { kChain = 300 };
static unsigned long iterations;
static unsigned long stepIteration[kChain];
static int steps;
static int timerTicks;
static id display;

static void queueStep(void) {
    [display performAfterDispatch: ^{
        if (steps < kChain) {
            stepIteration[steps++] = iterations;
            queueStep();
        }
    }];
}

int main(void) {
    @autoreleasepool {
        const char *backend = getenv("DARLING_APPKIT_BACKEND");
        if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
            printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
            return 0;
        }
        signal(SIGALRM, on_alarm);
        alarm(60);
        [NSApplication sharedApplication];
        display = [NSClassFromString(@"NSDisplay") currentDisplay];
        expect([NSStringFromClass([display class]) isEqualToString: @"WaylandDisplay"],
               "the Wayland display is the one in use");

        // One pass: the blocks queued before it run, the ones they queue do not.
        __block int ran = 0, queuedByBlock = 0, queuedRan = 0;
        for (int i = 0; i < 3; i++) {
            [display performAfterDispatch: ^{
                ran++;
                if (i == 0) {
                    queuedByBlock++;
                    [display performAfterDispatch: ^{ queuedRan++; }];
                }
            }];
        }
        [display processPendingEvents];
        expect(ran == 3, "a pass runs every block queued before it");
        expect(queuedByBlock == 1 && queuedRan == 0, "a block queued during a pass waits for the next one");

        // The deferred block does run, from the run loop.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow: 2];
        while (queuedRan == 0 && [until timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                     beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
        expect(queuedRan == 1, "a deferred block runs in a later run loop iteration");

        // A chain of blocks, each queueing the next, while the run loop is serviced.
        CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(
            NULL, kCFRunLoopBeforeSources, true, 0,
            ^(CFRunLoopObserverRef o, CFRunLoopActivity a) { iterations++; });
        CFRunLoopAddObserver(CFRunLoopGetCurrent(), observer, kCFRunLoopCommonModes);
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: 0.001 repeats: YES
                                                          block: ^(NSTimer *t) { timerTicks++; }];
        steps = 0;
        queueStep();
        until = [NSDate dateWithTimeIntervalSinceNow: 20];
        while (steps < kChain && [until timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event)
                [NSApp sendEvent: event];
        }
        [timer invalidate];
        CFRunLoopRemoveObserver(CFRunLoopGetCurrent(), observer, kCFRunLoopCommonModes);
        expect(steps == kChain, "the whole chain ran");
        int distinct = 0;
        for (int i = 0; i < steps; i++)
            if (i == 0 || stepIteration[i] != stepIteration[i - 1])
                distinct++;
        fprintf(stderr, "chain of %d steps over %d run loop iterations, %d timer ticks\n", steps, distinct, timerTicks);
        expect(distinct >= kChain / 2, "a chain of queued blocks is spread over run loop iterations");
        expect(timerTicks > 0, "timers fire while the chain runs");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
