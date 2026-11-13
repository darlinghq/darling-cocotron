/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A launched application becomes active once it has finished launching, with
// or without a visible window, and the activation notifications and isActive
// follow window-driven activation and deactivation afterwards. Needs a window
// server (for example DARLING_APPKIT_BACKEND=x11 on Xvfb with a window
// manager).
//
//   appkit-application-activation panel    the only window is a floating panel
//                                          with hidesOnDeactivate, ordered in
//                                          by applicationDidBecomeActive:
//   appkit-application-activation window   an ordinary window ordered in by
//                                          applicationDidFinishLaunching:
//   appkit-application-activation none     no window at all
#import <AppKit/AppKit.h>
#include <objc/message.h>
#include <stdio.h>
#include <string.h>

// What the display backend tells a window when the input focus moves.
@interface NSWindow (BackendCallbacks)
- (void) platformWindowActivated: (id) window displayIfNeeded: (BOOL) displayIfNeeded;
- (void) platformWindowDeactivated: (id) window checkForAppDeactivation: (BOOL) check;
@end

static const char *mode;
static NSMutableArray *events;
static NSWindow *window;
static int failures;

static void expect(BOOL ok, NSString *what) {
    if (!ok) {
        failures++;
        printf("FAIL: %s\n", [what UTF8String]);
    }
}

static BOOL hiddenForDeactivation(NSWindow *w) {
    SEL sel = NSSelectorFromString(@"_isHiddenForDeactivation");
    if (![w respondsToSelector: sel])
        return NO;
    return ((BOOL(*)(id, SEL)) objc_msgSend)(w, sel);
}

static NSString *joined(void) {
    return [events componentsJoinedByString: @" "];
}

// Only the application-level events are recorded, each with isActive at the
// time of the notification.
@interface Recorder : NSObject <NSApplicationDelegate>
@end

@implementation Recorder
- (void) record: (NSString *) name {
    [events addObject: [NSString stringWithFormat: @"%@=%d", name, (int) [NSApp isActive]]];
}
- (void) note: (NSNotification *) n {
    NSString *name = [n name];
    if ([name isEqualToString: NSApplicationWillFinishLaunchingNotification])
        [self record: @"willFinish"];
    else if ([name isEqualToString: NSApplicationDidFinishLaunchingNotification])
        [self record: @"didFinish"];
    else if ([name isEqualToString: NSApplicationWillBecomeActiveNotification])
        [self record: @"willBecomeActive"];
    else if ([name isEqualToString: NSApplicationDidBecomeActiveNotification])
        [self record: @"didBecomeActive"];
    else if ([name isEqualToString: NSApplicationWillResignActiveNotification])
        [self record: @"willResignActive"];
    else if ([name isEqualToString: NSApplicationDidResignActiveNotification])
        [self record: @"didResignActive"];
}
- (void) applicationDidFinishLaunching: (NSNotification *) n {
    if (!strcmp(mode, "window"))
        [window makeKeyAndOrderFront: nil];
}
- (void) applicationDidBecomeActive: (NSNotification *) n {
    if (!strcmp(mode, "panel"))
        [window orderFront: nil];
}
- (void) spin: (NSTimeInterval) seconds {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask: NSAnyEventMask
                                        untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                           inMode: NSDefaultRunLoopMode
                                          dequeue: YES];
        if (e != nil)
            [NSApp sendEvent: e];
    }
}
- (void) verify: (NSTimer *) t {
    BOOL hasWindow = window != nil;
    NSString *launch = @"willFinish=0 didFinish=0 willBecomeActive=0 didBecomeActive=1";

    expect([joined() isEqualToString: launch],
          [NSString stringWithFormat: @"launch sequence is '%@', expected '%@'", joined(), launch]);
    expect([NSApp isActive], @"application is active after launch");

    if (hasWindow) {
        expect([window isVisible], @"the window is visible");
        expect(!hiddenForDeactivation(window), @"the window is not hidden for deactivation");
    }

    if (!strcmp(mode, "panel")) {
        // The backend reports the focus moving to another client.
        [events removeAllObjects];
        [window platformWindowDeactivated: nil checkForAppDeactivation: NO];
        // The decision to resign is taken when the run-loop pass ends, so
        // that the focus moving to another window of the application does
        // not resign it.
        expect([joined() length] == 0 && [NSApp isActive],
              [NSString stringWithFormat: @"resigned before the run-loop pass ended: '%@'", joined()]);
        [self spin: 0.05];
        expect([joined() isEqualToString: @"willResignActive=1 didResignActive=0"],
              [NSString stringWithFormat: @"deactivation sequence is '%@'", joined()]);
        expect(![NSApp isActive], @"application is inactive after the focus left");
        [self spin: 0.3];
        expect(hiddenForDeactivation(window), @"the hides-on-deactivate panel is hidden while inactive");

        // And back.
        [events removeAllObjects];
        [window platformWindowActivated: nil displayIfNeeded: NO];
        expect([joined() isEqualToString: @"willBecomeActive=0 didBecomeActive=1"],
              [NSString stringWithFormat: @"reactivation sequence is '%@'", joined()]);
        expect([NSApp isActive], @"application is active again");
        [self spin: 0.3];
        expect(!hiddenForDeactivation(window), @"the panel is shown again on activation");
    }

    if (failures == 0)
        printf("OK\n");
    exit(failures != 0);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        mode = argc > 1 ? argv[1] : "panel";
        events = [NSMutableArray array];
        NSApplication *app = [NSApplication sharedApplication];
        Recorder *recorder = [[Recorder alloc] init];
        [app setDelegate: recorder];
        for (NSString *name in @[
                 NSApplicationWillFinishLaunchingNotification,
                 NSApplicationDidFinishLaunchingNotification,
                 NSApplicationWillBecomeActiveNotification,
                 NSApplicationDidBecomeActiveNotification,
                 NSApplicationWillResignActiveNotification,
                 NSApplicationDidResignActiveNotification ])
            [[NSNotificationCenter defaultCenter] addObserver: recorder
                                                     selector: @selector(note:)
                                                         name: name
                                                       object: nil];
        expect(![app isActive], @"application is not active before launching");

        if (!strcmp(mode, "panel")) {
            NSPanel *panel = [[NSPanel alloc]
                    initWithContentRect: NSMakeRect(100, 100, 190, 40)
                              styleMask: NSWindowStyleMaskTitled
                                backing: NSBackingStoreBuffered
                                  defer: NO];
            [panel setFloatingPanel: YES];
            [panel setHidesOnDeactivate: YES];
            window = panel;
        } else if (!strcmp(mode, "window")) {
            window = [[NSWindow alloc]
                    initWithContentRect: NSMakeRect(100, 100, 300, 200)
                              styleMask: NSWindowStyleMaskTitled
                                backing: NSBackingStoreBuffered
                                  defer: NO];
        }
        [window setReleasedWhenClosed: NO];
        [NSTimer scheduledTimerWithTimeInterval: 1.5
                                         target: recorder
                                       selector: @selector(verify:)
                                       userInfo: nil
                                        repeats: NO];
        [app run];
    }
    return 1;
}
