/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// X11 backend: restacking a window that AppKit is not showing must not map it.
// -[NSWindow isVisible] and the X window's map state have to agree, and
// -[NSWindow makeKeyWindow] is not -orderFront. Run by x11-window-state/run.sh
// (DARLING_APPKIT_BACKEND=x11 on Xvfb with a window manager), which checks
// the map state of each window with the host helper while this program idles.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

// Private: the window system object the NSWindow drives.
@interface NSWindow (Probe)
- (id) platformWindow;
@end
@interface NSObject (RestackProbe)
- (void) placeAboveWindow: (NSInteger) otherNumber;
- (void) placeBelowWindow: (NSInteger) otherNumber;
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static NSWindow *makeWindow(NSString *title, CGFloat x) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(x, 200, 200, 120)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: title];
    return window;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *visible = makeWindow(@"restack-visible", 50);
        [visible makeKeyAndOrderFront: nil];
        spin(1);
        NSInteger visibleNumber = [visible windowNumber];

        // Windows that were never ordered in, restacked through the window
        // system object the way -orderWindow:relativeTo: restacks.
        NSWindow *above = makeWindow(@"restack-hidden-above", 300);
        NSWindow *below = makeWindow(@"restack-hidden-below", 550);
        NSWindow *key = makeWindow(@"restack-hidden-key", 800);
        [[above platformWindow] placeAboveWindow: visibleNumber];
        [[below platformWindow] placeBelowWindow: visibleNumber];
        [[above platformWindow] placeAboveWindow: 0];
        [[below platformWindow] placeBelowWindow: 0];
        [key makeKeyWindow];

        // A window ordered out stays out when restacked.
        NSWindow *out = makeWindow(@"restack-ordered-out", 1050);
        [out orderFront: nil];
        spin(1);
        [out orderOut: nil];
        spin(1);
        [[out platformWindow] placeAboveWindow: visibleNumber];
        [[out platformWindow] placeBelowWindow: visibleNumber];

        // Positive control: ordering a window in still maps it.
        NSWindow *in = makeWindow(@"restack-ordered-in", 1300);
        [in orderWindow: NSWindowAbove relativeTo: visibleNumber];
        spin(1);

        expect(![above isVisible] && ![below isVisible] && ![key isVisible] && ![out isVisible],
               "restacking does not make a window visible");
        expect([visible isVisible] && [in isVisible], "ordered-in windows are visible");

        printf("READY\n");
        fflush(stdout);
        spin(12);
        printf("DONE failures=%d\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
