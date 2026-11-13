/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: while an application's windows hold the input focus one after the
// other (the display backend reports the focus leaving one window and then
// arriving in another), the application stays active: no resign/become
// notifications are posted and isActive does not turn NO for observers.
// When the focus leaves the application's windows for good, it resigns once.
// Prints PASS or FAIL. Needs a window server for the windows.
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSWindow (BackendCallbacks)
- (void) platformWindowActivated: (id) window displayIfNeeded: (BOOL) displayIfNeeded;
- (void) platformWindowDeactivated: (id) window checkForAppDeactivation: (BOOL) check;
@end

static NSMutableArray *events;
static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

@interface Recorder : NSObject
@end
@implementation Recorder
- (void) note: (NSNotification *) n {
    [events addObject: [NSString stringWithFormat: @"%@=%d", [n name], (int) [NSApp isActive]]];
}
@end

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        events = [NSMutableArray new];
        Recorder *recorder = [Recorder new];
        for (NSString *name in @[ NSApplicationWillResignActiveNotification,
                                  NSApplicationDidResignActiveNotification,
                                  NSApplicationWillBecomeActiveNotification,
                                  NSApplicationDidBecomeActiveNotification ])
            [[NSNotificationCenter defaultCenter] addObserver: recorder selector: @selector(note:) name: name object: NSApp];

        NSWindow *a = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 200, 100)
                                                  styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
        NSWindow *b = [[NSWindow alloc] initWithContentRect: NSMakeRect(400, 300, 200, 100)
                                                  styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
        [a orderFront: nil];
        [b orderFront: nil];
        [a platformWindowActivated: nil displayIfNeeded: NO];
        spin(0.2);
        CHECK([NSApp isActive], "application not active with a window holding the focus");

        // The focus moves from a to b.
        [events removeAllObjects];
        [a platformWindowDeactivated: nil checkForAppDeactivation: NO];
        [b platformWindowActivated: nil displayIfNeeded: NO];
        spin(0.3);
        CHECK([events count] == 0, "focus moved between own windows, notifications posted: %s", [[events componentsJoinedByString: @" "] UTF8String]);
        CHECK([NSApp isActive], "application inactive after the focus moved to another own window");

        // The focus leaves the application: one resign.
        [events removeAllObjects];
        [b platformWindowDeactivated: nil checkForAppDeactivation: NO];
        spin(0.3);
        CHECK([events count] == 2 && [events[0] hasPrefix: @"NSApplicationWillResignActiveNotification"] &&
                      [events[1] hasPrefix: @"NSApplicationDidResignActiveNotification"],
              "leaving the application: %s", [[events componentsJoinedByString: @" "] UTF8String]);
        CHECK(![NSApp isActive], "application still active after the focus left");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
