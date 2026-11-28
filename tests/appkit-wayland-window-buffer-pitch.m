/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A window whose rows are not a multiple of the pitch alignment of a GPU (width 661 pixels, so 2644 bytes) on the
// Wayland backend. The program shows the window, draws into it and keeps it up for a while; the driver
// appkit-wayland-window-buffer-pitch.sh reads the protocol trace and checks the stride of the dma-buf the
// window's pixels are shared in. Usage: appkit-wayland-window-buffer-pitch [hold-seconds]. Prints READY, then PASS
// (a compositor is needed: DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY; SKIP otherwise).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface PitchView : NSView
@end
@implementation PitchView
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.2 green: 0.4 blue: 0.8 alpha: 1] set];
    NSRectFill([self bounds]);
    [[NSColor whiteColor] set];
    NSFrameRect(NSInsetRect([self bounds], 10, 10));
}
@end

static void spin(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
}

int main(int argc, char **argv) {
    const char *backend = getenv("DARLING_APPKIT_BACKEND");
    if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
        printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
        return 0;
    }
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(40, 40, 661, 201)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"pitch-window"];
        [window setContentView: [[[PitchView alloc] initWithFrame: NSMakeRect(0, 0, 661, 201)] autorelease]];
        [window makeKeyAndOrderFront: nil];
        printf("READY\n");
        fflush(stdout);
        spin(argc > 1 ? atof(argv[1]) : 3);
        [window close];
    }
    printf("PASS\n");
    return 0;
}
