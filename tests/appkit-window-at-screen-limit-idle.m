/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A visible borderless window placed exactly at the limit of what the window-on-screen check tolerates (a
// 1x1 window whose far edges are 20 points inside the main screen's bottom-left corner) must be left where it
// is. The check, which runs on every pass of the application's event loop, used to set the frame it had
// computed even when it equalled the current frame; -setFrame:display: asks for another check, and the
// platform window reconfigured itself each time (a window system that reports a reconfiguration, even an
// unchanged one, then wakes the loop again): an idle application spun at about 140 passes per second. The test
// counts the platform window's -setFrame: calls over 30 reports of an unchanged frame followed by a loop pass. Prints PASS on success. Build without ARC.
#import <AppKit/AppKit.h>
#include <objc/runtime.h>
#include <stdio.h>

@interface NSWindow (PlatformReports)
- (void) platformWindow: (id) window frameChanged: (NSRect) frame didSize: (BOOL) didSize;
@end

static int platformSetFrameCalls;
static IMP originalSetFrame;

static void countedSetFrame(id self, SEL _cmd, CGRect rect) {
    platformSetFrameCalls++;
    ((void (*)(id, SEL, CGRect)) originalSetFrame)(self, _cmd, rect);
}

static void pump(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: end
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

int main(void) {
    int failures = 0;
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect screen = [[NSScreen mainScreen] frame];
        NSRect frame = NSMakeRect(NSMinX(screen) + 19, NSMinY(screen) + 19, 1, 1);
        NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window orderFront: nil];
        pump(1.0);

        Method method = class_getInstanceMethod([[window platformWindow] class], @selector(setFrame:));
        if (method == NULL) {
            printf("FAIL: the platform window has no -setFrame:\n");
            return 1;
        }
        originalSetFrame = method_setImplementation(method, (IMP) countedSetFrame);

        for (int i = 0; i < 30; i++) {
            // What the window system does after every reconfiguration request: reports the frame.
            [window platformWindow: [window platformWindow] frameChanged: [window frame] didSize: NO];
            pump(0.02);
        }
        printf("platform -setFrame: calls over 30 reports: %d\n", platformSetFrameCalls);
        if (platformSetFrameCalls > 1) {
            printf("FAIL: an unchanged frame was set again %d times\n", platformSetFrameCalls);
            failures++;
        }
        NSRect now = [window frame];
        if (!NSEqualRects(now, frame)) {
            printf("FAIL: the window moved to %s\n", [NSStringFromRect(now) UTF8String]);
            failures++;
        }
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    fflush(stdout);
    return failures != 0;
}
