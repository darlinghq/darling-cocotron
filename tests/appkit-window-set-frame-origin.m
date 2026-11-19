// Copyright (C) 2026 Lubos Dolezel
//
// -setFrameOrigin: on a shown window puts the window's frame at that point, whatever the window
// system adds around it. Shows a titled window and a borderless one, moves each with
// -setFrameOrigin:, and prints "win <title> <x> <y> <width> <height>" (the frame AppKit reports,
// Cocoa screen coordinates) for each, then "moved", then holds the windows for <seconds> (the first
// argument). The harness appkit-window-set-frame-origin-x11.sh compares the window system's view.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static void spin(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUInteger titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
        NSWindow *a = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200) styleMask: titled
                                                    backing: NSBackingStoreBuffered defer: NO];
        NSWindow *b = [[NSWindow alloc] initWithContentRect: NSMakeRect(500, 100, 300, 200)
                                                  styleMask: NSWindowStyleMaskBorderless
                                                    backing: NSBackingStoreBuffered defer: NO];
        a.title = @"titled";
        b.title = @"borderless";
        [a orderFront: nil];
        [b orderFront: nil];
        spin(2);
        [a setFrameOrigin: NSMakePoint(400, 300)];
        [b setFrameOrigin: NSMakePoint(900, 300)];
        spin(2);
        for (NSWindow *w in @[ a, b ])
            printf("win %s %.0f %.0f %.0f %.0f\n", [w.title UTF8String], w.frame.origin.x, w.frame.origin.y,
                   w.frame.size.width, w.frame.size.height);
        printf("moved\n");
        fflush(stdout);
        spin(argc > 1 ? atof(argv[1]) : 0);
    }
    return 0;
}
