/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// CoreGraphics and AppKit agree on the displays at once when another client changes them: when
// NSApplicationDidChangeScreenParametersNotification is delivered, the main display's bounds and pixel
// size in CoreGraphics, the main NSScreen's frame and backing scale and the screen of a window show
// the same new layout, and a later look finds nothing different (no screen lags one event behind).
//
// Usage: appkit-displays-agree-on-change                         identity checks only
//        CG_TEST_MODE=WIDTHxHEIGHT appkit-displays-agree-on-change external
//   for coregraphics-displays-external-change.sh, which changes the main display's mode after READY1
//   and restores it after READY2 (xrandr on X11, swaymsg on Wayland).
// Link with -framework AppKit -framework CoreGraphics.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    CGRect cgBounds;
    size_t cgPixelWidth, cgPixelHeight;
    NSRect screenFrame;
    CGFloat screenScale;
    NSRect windowScreenFrame;
    CGFloat windowScale;
} Snapshot;

static NSWindow *window;

static Snapshot snapshot(void) {
    CGDirectDisplayID main = CGMainDisplayID();
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(main);
    Snapshot s;
    s.cgBounds = CGDisplayBounds(main);
    s.cgPixelWidth = mode ? CGDisplayModeGetPixelWidth(mode) : 0;
    s.cgPixelHeight = mode ? CGDisplayModeGetPixelHeight(mode) : 0;
    if (mode)
        CGDisplayModeRelease(mode);
    s.screenFrame = [[NSScreen mainScreen] frame];
    s.screenScale = [[NSScreen mainScreen] backingScaleFactor];
    s.windowScreenFrame = [[window screen] frame];
    s.windowScale = [window backingScaleFactor];
    return s;
}

// What must hold within one snapshot: the three views of the main display are one layout.
static const char *inconsistency(Snapshot s) {
    if (s.screenFrame.size.width != s.cgBounds.size.width || s.screenFrame.size.height != s.cgBounds.size.height)
        return "NSScreen frame size differs from CGDisplayBounds";
    if (s.screenScale < 1 || fabs((double) s.cgPixelWidth / s.screenScale - s.cgBounds.size.width) > 1)
        return "the backing scale does not turn the pixel width into the bounds' width";
    if (!NSEqualRects(s.windowScreenFrame, s.screenFrame))
        return "the window's screen is not the main screen";
    if (s.windowScale != s.screenScale)
        return "the window's backing scale differs from its screen's";
    return NULL;
}

static BOOL same(Snapshot a, Snapshot b) {
    return CGRectEqualToRect(a.cgBounds, b.cgBounds) && a.cgPixelWidth == b.cgPixelWidth &&
           a.cgPixelHeight == b.cgPixelHeight && NSEqualRects(a.screenFrame, b.screenFrame) &&
           a.screenScale == b.screenScale && NSEqualRects(a.windowScreenFrame, b.windowScreenFrame) &&
           a.windowScale == b.windowScale;
}

@interface Observer : NSObject {
@public
    int count;
    Snapshot last;
    const char *problem;
}
@end
@implementation Observer
- (void) changed: (NSNotification *) note {
    count++;
    last = snapshot();
    if (!problem)
        problem = inconsistency(last);
}
@end

static void spinFor(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

// Waits for a notification, then for the last one to be followed by nothing that changes the layout.
static int waitForChange(Observer *observer, int seen, int base) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 20];
    while (observer->count <= seen && [end timeIntervalSinceNow] > 0)
        spinFor(0.05);
    CHECK(base, observer->count > seen);
    if (observer->problem) {
        printf("FAIL: at the notification, %s\n", observer->problem);
        return base + 1;
    }
    Snapshot atNotification = observer->last;
    spinFor(0.7);
    Snapshot later = snapshot();
    if (!same(atNotification, later)) {
        printf("FAIL: the layout changed again after the notification (pixel width %zu then %zu)\n",
               atNotification.cgPixelWidth, later.cgPixelWidth);
        return base + 2;
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                             styleMask: NSTitledWindowMask
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        [window makeKeyAndOrderFront: nil];
        spinFor(0.5);
        Snapshot start = snapshot();
        CHECK(1, inconsistency(start) == NULL);

        unsigned width = 0, height = 0;
        const char *spec = getenv("CG_TEST_MODE");
        BOOL haveMode = spec && sscanf(spec, "%ux%u", &width, &height) == 2;
        if (argc > 1 && strcmp(argv[1], "external") == 0 && haveMode) {
            Observer *observer = [[Observer alloc] init];
            [[NSNotificationCenter defaultCenter] addObserver: observer
                                                     selector: @selector(changed:)
                                                         name: NSApplicationDidChangeScreenParametersNotification
                                                       object: nil];
            printf("READY1\n");
            fflush(stdout);
            int failed = waitForChange(observer, 0, 10);
            if (failed)
                return failed;
            CHECK(13, observer->last.cgBounds.size.width == width && observer->last.cgBounds.size.height == height);
            int seen = observer->count;
            printf("READY2\n");
            fflush(stdout);
            failed = waitForChange(observer, seen, 20);
            if (failed)
                return failed;
            CHECK(23, same(observer->last, start));
        }
        printf("PASS\n");
    }
    return 0;
}
