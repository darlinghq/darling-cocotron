// Copyright (C) 2026 Lubos Dolezel
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

// -[NSWindow toggleFullScreen:]: NSWindowWillEnterFullScreenNotification, then the
// window system's confirmation, then NSWindowDidEnterFullScreenNotification (and the
// same for exit). The style mask holds NSWindowStyleMaskFullScreen from the request
// on. When the window system does not take the window into full screen the delegate
// gets windowDidFailToEnterFullScreen:, no Did notification is posted and the style
// mask is back to its previous value.
//
// Observed on macOS 26.7.3 and Mojave 10.14.4 in a session where the transition
// fails (no window server session): the delegate's windowWillEnterFullScreen: runs
// before an observer's, the style mask still lacks the full screen bit inside the
// Will callback and has it when toggleFullScreen: returns, then
// windowDidFailToEnterFullScreen: arrives (no Did notification) and the mask clears.
// Under a window manager that does full screen (Darling on X11 with xfwm4, or on
// Wayland) run with --expect-enter: the transition must complete.

static NSMutableArray *log_;
static int failures;

static void expectTrue(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Recorder : NSObject <NSWindowDelegate> {
@public
    NSWindow *window;
    BOOL maskInsideWillEnter;
}
- (void) observe: (NSNotification *) note;
@end

@implementation Recorder
- (void) windowWillEnterFullScreen: (NSNotification *) note {
    maskInsideWillEnter = (window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    [log_ addObject: @"delegate:willEnter"];
}
- (void) windowDidEnterFullScreen: (NSNotification *) note { [log_ addObject: @"delegate:didEnter"]; }
- (void) windowWillExitFullScreen: (NSNotification *) note { [log_ addObject: @"delegate:willExit"]; }
- (void) windowDidExitFullScreen: (NSNotification *) note { [log_ addObject: @"delegate:didExit"]; }
- (void) windowDidFailToEnterFullScreen: (NSWindow *) w { [log_ addObject: @"delegate:failEnter"]; }
- (void) windowDidFailToExitFullScreen: (NSWindow *) w { [log_ addObject: @"delegate:failExit"]; }
- (void) observe: (NSNotification *) note {
    NSString *name = note.name;
    if ([name isEqualToString: NSWindowWillEnterFullScreenNotification])
        [log_ addObject: @"note:willEnter"];
    else if ([name isEqualToString: NSWindowDidEnterFullScreenNotification])
        [log_ addObject: @"note:didEnter"];
    else if ([name isEqualToString: NSWindowWillExitFullScreenNotification])
        [log_ addObject: @"note:willExit"];
    else if ([name isEqualToString: NSWindowDidExitFullScreenNotification])
        [log_ addObject: @"note:didExit"];
}
@end

static BOOL waitFor(NSString *first, NSString *second, NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0) {
        if ([log_ containsObject: first] || (second && [log_ containsObject: second]))
            return YES;
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    }
    return NO;
}

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static BOOL hasFullScreenMask(NSWindow *w) { return (w.styleMask & NSWindowStyleMaskFullScreen) != 0; }

static NSString *joined(void) { return [log_ componentsJoinedByString: @","]; }

int main(int argc, char **argv) {
    BOOL expectEnter = argc > 1 && strcmp(argv[1], "--expect-enter") == 0;
    @autoreleasepool {
        [NSApplication sharedApplication];
        log_ = [NSMutableArray array];

        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(100, 100, 400, 300)
                          styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable
                            backing: NSBackingStoreBuffered
                              defer: NO];
        window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        Recorder *recorder = [Recorder new];
        recorder->window = window;
        window.delegate = recorder;
        for (NSNotificationName name in @[NSWindowWillEnterFullScreenNotification, NSWindowDidEnterFullScreenNotification,
                                          NSWindowWillExitFullScreenNotification, NSWindowDidExitFullScreenNotification])
            [[NSNotificationCenter defaultCenter] addObserver: recorder selector: @selector(observe:) name: name object: window];
        [window makeKeyAndOrderFront: nil];
        spin(1.0);

        expectTrue(!hasFullScreenMask(window), "window starts without the full screen style");
        [window toggleFullScreen: nil];
        expectTrue([log_ count] >= 2 && [log_[0] isEqualToString: @"delegate:willEnter"] &&
                      [log_[1] isEqualToString: @"note:willEnter"],
              "Will enter reaches the delegate, then the observer, before toggleFullScreen: returns");
        expectTrue(!recorder->maskInsideWillEnter, "the style mask lacks the full screen bit inside the Will callback");
        expectTrue(hasFullScreenMask(window), "the style mask has the full screen bit once the request is made");
        expectTrue(![log_ containsObject: @"note:didEnter"], "no Did notification before the window system confirms");

        waitFor(@"note:didEnter", @"delegate:failEnter", 6.0);
        BOOL entered = [log_ containsObject: @"note:didEnter"];
        if (expectEnter)
            expectTrue(entered, "the window enters full screen under the window manager");
        if (entered) {
            expectTrue([log_ indexOfObject: @"delegate:didEnter"] < [log_ indexOfObject: @"note:didEnter"],
                  "Did enter reaches the delegate before the observer");
            expectTrue(![log_ containsObject: @"delegate:failEnter"], "no failure callback after entering");
            expectTrue(hasFullScreenMask(window), "the style mask keeps the full screen bit while full screen");

            [log_ removeAllObjects];
            [window toggleFullScreen: nil];
            expectTrue([log_ count] >= 2 && [log_[0] isEqualToString: @"delegate:willExit"] &&
                          [log_[1] isEqualToString: @"note:willExit"],
                  "Will exit reaches the delegate, then the observer");
            waitFor(@"note:didExit", @"delegate:failExit", 6.0);
            expectTrue([log_ containsObject: @"note:didExit"] && [log_ containsObject: @"delegate:didExit"],
                  "Did exit is posted once the window system leaves full screen");
            expectTrue(!hasFullScreenMask(window), "the style mask is back to windowed");
            printf("outcome=entered log=%s\n", [joined() UTF8String]);
        } else {
            expectTrue([log_ containsObject: @"delegate:failEnter"], "the delegate is told that entering failed");
            expectTrue(![log_ containsObject: @"note:didEnter"], "no Did notification after a failure");
            expectTrue(!hasFullScreenMask(window), "the style mask is restored after a failure");
            printf("outcome=failed log=%s\n", [joined() UTF8String]);
        }

        // A window that is not on screen cannot enter full screen: it fails and is restored.
        [log_ removeAllObjects];
        NSWindow *hidden = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(100, 100, 200, 200)
                          styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                            backing: NSBackingStoreBuffered
                              defer: NO];
        hidden.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
        Recorder *hiddenRecorder = [Recorder new];
        hiddenRecorder->window = hidden;
        hidden.delegate = hiddenRecorder;
        [hidden toggleFullScreen: nil];
        waitFor(@"delegate:failEnter", nil, 6.0);
        expectTrue([log_ containsObject: @"delegate:willEnter"] && [log_ containsObject: @"delegate:failEnter"] &&
                      ![log_ containsObject: @"delegate:didEnter"],
              "a window that is not on screen reports the failure to enter");
        expectTrue(!hasFullScreenMask(hidden), "the style mask of that window is restored");
        [hidden release];
        [window close];
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
