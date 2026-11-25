// NSWindow's minSize, maxSize, contentMinSize and contentMaxSize limit user resizing, so the backend
// hands them to the compositor with xdg_toplevel.set_min_size and set_max_size (window geometry
// sizes, 0 for no limit). Needs DARLING_APPKIT_BACKEND=wayland and a compositor; run it with
// WAYLAND_DEBUG=client and give the log (stderr) to size-limits-check.py, which checks the requests on
// the wire. Prints CHECK PASS/FAIL lines and RESULT.
//
//   1. a resizable window with minSize 200x150 and maxSize 800x600 is shown
//   2. contentMinSize 250x180 is set: the minimum and the content minimum are one limit, the last set wins
//   3. maxSize 100x100 is set, below the minimum: the maximum sent is raised to the minimum (xdg-shell
//      makes a maximum below the minimum an error)
//   4. every limit is removed (minSize 0, contentMinSize 0, maxSize FLT_MAX)
#import <AppKit/AppKit.h>
#include <float.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSWindow (SizeLimitsFixture)
- (id) platformWindow;
@end
@interface NSObject (SizeLimitsPlatformFixture)
- (BOOL) isMapped;
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
    NSWindow *window;
}
- (void) step: (NSTimer *) timer;
@end

@implementation Driver
- (void) step: (NSTimer *) timer {
    static int stage;
    static NSTimeInterval since;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!since) since = now;
    switch (stage) {
    case 0:
        [window makeKeyAndOrderFront: nil];
        stage = 1; since = 0;
        break;
    case 1:
        if (![[window platformWindow] isMapped] && now - since < 15) return;
        expect([[window platformWindow] isMapped], "the window is shown");
        expect(NSEqualSizes([window minSize], NSMakeSize(200, 150)) &&
               NSEqualSizes([window maxSize], NSMakeSize(800, 600)), "minSize and maxSize are kept");
        [window setContentMinSize: NSMakeSize(250, 180)];
        expect(NSEqualSizes([window contentMinSize], NSMakeSize(250, 180)), "contentMinSize is kept");
        stage = 2; since = 0;
        break;
    case 2:
        if (now - since < 1) return;
        [window setMaxSize: NSMakeSize(100, 100)];
        stage = 3; since = 0;
        break;
    case 3:
        if (now - since < 1) return;
        [window setMinSize: NSZeroSize];
        [window setContentMinSize: NSZeroSize];
        [window setMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];
        stage = 4; since = 0;
        break;
    case 4:
        if (now - since < 1) return;
        // Still dispatching: a protocol error from a maximum below the minimum would have ended the connection.
        stage = 5;
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
        driver->window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                     styleMask: NSTitledWindowMask | NSResizableWindowMask
                                                       backing: NSBackingStoreBuffered
                                                         defer: NO];
        [driver->window setReleasedWhenClosed: NO];
        [driver->window setTitle: @"Size limits fixture"];
        [driver->window setMinSize: NSMakeSize(200, 150)];
        [driver->window setMaxSize: NSMakeSize(800, 600)];
        [NSTimer scheduledTimerWithTimeInterval: .1 target: driver selector: @selector(step:)
                                       userInfo: nil repeats: YES];
        puts("READY");
        fflush(stdout);
        [NSApp run];
    }
}
