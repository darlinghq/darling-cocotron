// -miniaturize: asks the compositor with xdg_toplevel.set_minimized, which xdg-shell offers no way
// to undo or to read back, so the window keeps the state itself and -deminiaturize: asks for its
// activation (xdg-activation-v1). The state is kept only when the compositor advertised that it
// minimizes (xdg_toplevel wm_capabilities): one that did not ignores the request, and the window
// must not then be reported miniaturized while it stays on screen. Needs
// DARLING_APPKIT_BACKEND=wayland and a compositor with xdg-activation; run it with
// WAYLAND_DEBUG=client, and give the log (stderr) to minimize-restore-check.py with --advertised 1 or
// 0 as the line "MINIMIZE-ADVERTISED n" of the output says. Prints CHECK PASS/FAIL lines and RESULT.
// Whether the compositor restores the window is its decision, so this checks what the application
// sees and what is asked of the compositor, not the compositor's answer.
//
//   1. two windows are shown, the second is key; the first is not miniaturized
//   2. after -miniaturize: the first is miniaturized exactly when minimizing was advertised, and then
//      NSWindowDidMiniaturizeNotification arrives
//   3. after -deminiaturize: it is not miniaturized, an activation was asked for when it had been
//      (wire check, naming the other window as the requester), and it stays mapped
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSWindow (MinimizeRestoreFixture)
- (id) platformWindow;
@end
@interface NSObject (MinimizeRestorePlatformFixture)
- (BOOL) isMapped;
- (BOOL) compositorMinimizes;
@end

static unsigned checks, failures;
static void expect(BOOL ok, const char *label) {
    ++checks;
    if (!ok) ++failures;
    printf("CHECK %s %s\n", ok ? "PASS" : "FAIL", label);
    fflush(stdout);
}

@interface Driver : NSObject {
@public
    NSWindow *window, *other;
    BOOL didMiniaturize, advertised;
}
- (void) step: (NSTimer *) timer;
- (void) windowDidMiniaturize: (NSNotification *) note;
@end

@implementation Driver
- (void) windowDidMiniaturize: (NSNotification *) note {
    didMiniaturize = YES;
}
- (void) step: (NSTimer *) timer {
    static int stage;
    static NSTimeInterval since;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!since) since = now;
    BOOL timedOut = now - since > 15;
    switch (stage) {
    case 0:
        [window makeKeyAndOrderFront: nil];
        [other makeKeyAndOrderFront: nil];
        stage = 1; since = 0;
        break;
    case 1:
        if (!([[window platformWindow] isMapped] && [[other platformWindow] isMapped]) && !timedOut) return;
        expect([[window platformWindow] isMapped] && ![window isMiniaturized], "a shown window is not miniaturized");
        // The toplevel's capabilities arrive before its first configure, which the windows have had.
        advertised = [[window platformWindow] compositorMinimizes];
        printf("MINIMIZE-ADVERTISED %d\n", advertised ? 1 : 0);
        fflush(stdout);
        [window miniaturize: nil];
        expect([window isMiniaturized] == advertised,
               "after -miniaturize: miniaturized exactly when the compositor advertised minimizing");
        stage = 2; since = 0;
        break;
    case 2:
        if (advertised && !didMiniaturize && !timedOut) return;
        expect(didMiniaturize == advertised, "NSWindowDidMiniaturizeNotification is posted exactly then");
        [window deminiaturize: nil];
        expect(![window isMiniaturized], "after -deminiaturize: the window is not miniaturized");
        stage = 3; since = 0;
        break;
    case 3:
        if (now - since < 2) return;
        expect([[window platformWindow] isMapped], "the window is still mapped after -deminiaturize:");
        stage = 4;
        break;
    default:
        printf("RESULT checks=%u failures=%u\n", checks, failures);
        fflush(stdout);
        exit(failures ? 1 : 0);
    }
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Driver *driver = [Driver new];
        NSWindow *windows[2];
        for (int i = 0; i < 2; i++) {
            windows[i] = [[NSWindow alloc] initWithContentRect: NSMakeRect(100 + 340 * i, 100, 300, 300)
                                                     styleMask: NSTitledWindowMask | NSMiniaturizableWindowMask
                                                       backing: NSBackingStoreBuffered
                                                         defer: NO];
            [windows[i] setReleasedWhenClosed: NO];
            [windows[i] setTitle: i ? @"Minimize restore other" : @"Minimize restore fixture"];
        }
        driver->window = windows[0];
        driver->other = windows[1];
        [[NSNotificationCenter defaultCenter] addObserver: driver
                                                 selector: @selector(windowDidMiniaturize:)
                                                     name: NSWindowDidMiniaturizeNotification
                                                   object: driver->window];
        [NSTimer scheduledTimerWithTimeInterval: .1 target: driver selector: @selector(step:)
                                       userInfo: nil repeats: YES];
        puts("READY");
        fflush(stdout);
        [NSApp run];
    }
}
