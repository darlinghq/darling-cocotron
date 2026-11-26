// CFLAGS: -framework Foundation -framework AppKit -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// Benchmark of AppKit's event path: 100000 events in batches of 100, posted and then taken with
// -nextEventMatchingMask:untilDate:inMode:dequeue:. "posted" are application-defined events from
// -[NSApplication postEvent:atStart:]; "input" are key events of the window system, posted as
// CGEvents (CGEventPost) as the window system backends do, and "input-moved" mouse moves posted
// the same way with coalescing off. Prints the time per event; checks only that every event
// arrived.
//
// Needs a window system (DISPLAY, or WAYLAND_DISPLAY with DARLING_APPKIT_BACKEND=wayland).
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int run(const char *name, int total, NSEventMask mask, void (^post)(int)) {
    const int batch = 100;
    int received = 0;
    double start = now();
    for (int done = 0; done < total; done += batch) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        for (int i = 0; i < batch; i++)
            post(done + i);
        for (int i = 0; i < batch; i++) {
            NSEvent *event = [NSApp nextEventMatchingMask: mask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event == nil)
                break;
            received++;
        }
        [pool release];
    }
    double elapsed = now() - start;
    printf("%s: %d events, %.3f s, %.2f us/event\n", name, received, elapsed, elapsed * 1e6 / total);
    return received == total;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    int total = 100000;
    [NSApplication sharedApplication];
    [NSApp finishLaunching];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 200)
                                                   styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window makeKeyAndOrderFront: nil];
    // Whatever the window system has to say first
    while ([NSApp nextEventMatchingMask: NSEventMaskAny untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]
                                 inMode: NSDefaultRunLoopMode dequeue: YES] != nil)
        ;

    int ok = run("posted", total, NSEventMaskApplicationDefined, ^(int i) {
        [NSApp postEvent: [NSEvent otherEventWithType: NSEventTypeApplicationDefined
                                             location: NSZeroPoint
                                        modifierFlags: 0
                                            timestamp: 0
                                         windowNumber: 0
                                              context: nil
                                              subtype: 0
                                                data1: i
                                                data2: 0]
                 atStart: NO];
    });

    ok &= run("input", total, NSEventMaskKeyDown, ^(int i) {
        CGEventRef event = CGEventCreateKeyboardEvent(NULL, 0, true);
        CGEventPost(kCGSessionEventTap, event);
        CFRelease(event);
    });
    // Moves without coalescing, so that every one arrives
    [NSEvent setMouseCoalescingEnabled: NO];
    ok &= run("input-moved", total, NSEventMaskMouseMoved, ^(int i) {
        CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(100 + i % 100, 150),
                                                   kCGMouseButtonLeft);
        CGEventPost(kCGSessionEventTap, event);
        CFRelease(event);
    });
    [NSEvent setMouseCoalescingEnabled: YES];

    printf(ok ? "ALL PASSED\n" : "FAILED 1\n");
    [pool release];
    return ok ? 0 : 1;
}
