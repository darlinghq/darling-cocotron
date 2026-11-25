// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// The X11 backend gives the window manager the size limits of a resizable window (ICCCM
// WM_NORMAL_HINTS PMinSize and PMaxSize) from NSWindow's minSize, maxSize, contentMinSize and
// contentMaxSize, so that user resizing stops at them, and follows their changes. Run it under
// tests/appkit-x11-size-hints.sh, which reads the hints with xprop after each stage. Takes a
// directory as its argument: stage n runs when the file go<n> appears in it and prints "STAGE n"
// when done. Prints READY first.
//   0. minSize 200x150 and maxSize 800x600 are set before the window is shown
//   1. contentMinSize 250x180 is set after (one limit: the last set wins)
//   2. maxSize 100x100, below the minimum: the hinted maximum is not below the minimum
//   3. every limit removed (minSize 0, contentMinSize 0, maxSize FLT_MAX): no hints
//   4. the window is made not resizable: it is fixed at its size (min = max = the frame size)
#import <AppKit/AppKit.h>
#include <float.h>
#include <sys/stat.h>
#include <stdio.h>
#include <unistd.h>

static const char *directory;

@interface Driver : NSObject {
@public
    NSWindow *window;
}
- (void) step: (id) sender;
@end

@implementation Driver
- (void) step: (id) sender {
    static int stage = 0;
    char path[1024];
    struct stat info;
    snprintf(path, sizeof path, "%s/go%d", directory, stage + 1);
    if (stat(path, &info) != 0)
        return;
    stage++;
    switch (stage) {
    case 1:
        [window setContentMinSize: NSMakeSize(250, 180)];
        break;
    case 2:
        [window setMaxSize: NSMakeSize(100, 100)];
        break;
    case 3:
        [window setMinSize: NSZeroSize];
        [window setContentMinSize: NSZeroSize];
        [window setMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];
        break;
    case 4:
        [window setStyleMask: NSWindowStyleMaskTitled];
        break;
    default:
        exit(0);
    }
    printf("STAGE %d\n", stage);
    fflush(stdout);
}
@end

int main(int argc, char **argv) {
    if (argc < 2)
        return 2;
    directory = argv[1];
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        Driver *driver = [Driver new];
        driver->window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                     styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                       backing: NSBackingStoreBuffered
                                                         defer: NO];
        [driver->window setReleasedWhenClosed: NO];
        [driver->window setTitle: @"x11-size-hints"];
        [driver->window setMinSize: NSMakeSize(200, 150)];
        [driver->window setMaxSize: NSMakeSize(800, 600)];
        [driver->window makeKeyAndOrderFront: nil];
        // Stage 0 is the state before the first file appears.
        puts("READY");
        fflush(stdout);
        for (;;) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event != nil)
                [NSApp sendEvent: event];
            [driver step: nil];
        }
    }
}
