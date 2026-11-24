/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// NSScreen is made from CoreGraphics' displays: one screen per active display, the main display's
// screen first, each with the display's ID as its NSScreenNumber, its frame the display's bounds in
// Cocoa's global space (origin at the main screen's bottom-left corner, y up) and its backing scale
// the pixels per point of the display's mode; the screens stay the same objects until the displays
// change; a change of the displays that CoreGraphics reports (a mode switch of this process here) makes
// AppKit post NSApplicationDidChangeScreenParametersNotification once and read the new bounds.
//
// Usage: appkit-screens-from-coregraphics                 identity checks
//        CG_TEST_MODE=WIDTHxHEIGHT appkit-screens-from-coregraphics    also switches the mode (the runners of
//                                                          coregraphics-display-mode-switch do)
//        appkit-screens-from-coregraphics external        for coregraphics-displays-external-change.sh
// Link with -framework AppKit -framework CoreGraphics.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

@interface Observer : NSObject {
@public
    int count;
}
@end
@implementation Observer
- (void) changed: (NSNotification *) note { count++; }
@end

static void spinFor(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static int identityChecks(void) {
    NSArray<NSScreen *> *screens = [NSScreen screens];
    uint32_t count = 0;
    CHECK(1, CGGetActiveDisplayList(0, NULL, &count) == kCGErrorSuccess && count >= 1);
    CHECK(2, [screens count] == count);
    CGDirectDisplayID ids[16];
    CHECK(3, CGGetActiveDisplayList(16, ids, &count) == kCGErrorSuccess);
    CGRect mainBounds = CGDisplayBounds(CGMainDisplayID());
    for (NSUInteger i = 0; i < [screens count] && i < 16; i++) {
        NSScreen *screen = screens[i];
        CGDirectDisplayID id = [[[screen deviceDescription] objectForKey: @"NSScreenNumber"] unsignedIntValue];
        CHECK(4, id == ids[i]);
        CGRect bounds = CGDisplayBounds(id);
        NSRect frame = [screen frame];
        // Cocoa's y points up from the main display's bottom edge.
        CHECK(5, frame.origin.x == bounds.origin.x && frame.size.width == bounds.size.width && frame.size.height == bounds.size.height);
        CHECK(6, frame.origin.y == mainBounds.size.height - bounds.origin.y - bounds.size.height);
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(id);
        CHECK(7, mode != NULL);
        double scale = [screen backingScaleFactor];
        CHECK(8, scale >= 1 && (double) CGDisplayModeGetPixelWidth(mode) / scale >= CGDisplayModeGetWidth(mode) - 1 &&
                         (double) CGDisplayModeGetPixelWidth(mode) / scale <= CGDisplayModeGetWidth(mode) + 1);
        CGDisplayModeRelease(mode);
        CHECK(9, [[screen localizedName] length] > 0);
        CHECK(10, [screen maximumFramesPerSecond] > 0);
    }
    CHECK(11, [screens[0] frame].origin.x == 0 && [screens[0] frame].origin.y == 0);
    // The same objects until the displays change.
    CHECK(12, [NSScreen screens][0] == screens[0]);
    return 0;
}

static int switchChecks(unsigned width, unsigned height) {
    CGDirectDisplayID display = CGMainDisplayID();
    size_t origWidth = CGDisplayPixelsWide(display);
    Observer *observer = [[Observer alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver: observer
                                             selector: @selector(changed:)
                                                 name: NSApplicationDidChangeScreenParametersNotification
                                               object: nil];
    NSScreen *before = [NSScreen screens][0];
    boolean_t exact = false;
    CFDictionaryRef target = CGDisplayBestModeForParameters(display, 32, width, height, &exact);
    CHECK(20, exact && target != NULL);
    CHECK(21, CGDisplaySwitchToMode(display, target) == kCGErrorSuccess);
    // The screens are read afresh at once, and the notification follows in the next run loop pass.
    NSScreen *after = [NSScreen mainScreen];
    CHECK(22, [after frame].size.width == width && [after frame].size.height == height);
    CHECK(23, [NSScreen screens][0] != before);
    spinFor(0.7);
    CHECK(24, observer->count == 1);
    // Putting the mode back is a change too.
    CHECK(25, CGDisplayRelease(display) == kCGErrorSuccess && CGDisplayPixelsWide(display) == origWidth);
    return 0;
}

static int externalChecks(unsigned width, unsigned height) {
    CGDirectDisplayID display = CGMainDisplayID();
    size_t origWidth = CGDisplayPixelsWide(display), origHeight = CGDisplayPixelsHigh(display);
    Observer *observer = [[Observer alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver: observer
                                             selector: @selector(changed:)
                                                 name: NSApplicationDidChangeScreenParametersNotification
                                               object: nil];
    [[NSScreen screens] count];
    printf("READY1\n");
    fflush(stdout);
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 20];
    while (observer->count < 1 && [end timeIntervalSinceNow] > 0)
        spinFor(0.1);
    CHECK(30, observer->count >= 1);
    CHECK(31, [[NSScreen mainScreen] frame].size.width == width && [[NSScreen mainScreen] frame].size.height == height);
    spinFor(0.7);
    int seen = observer->count;
    printf("READY2\n");
    fflush(stdout);
    end = [NSDate dateWithTimeIntervalSinceNow: 20];
    while (observer->count <= seen && [end timeIntervalSinceNow] > 0)
        spinFor(0.1);
    CHECK(32, observer->count > seen);
    CHECK(33, [[NSScreen mainScreen] frame].size.width == origWidth && [[NSScreen mainScreen] frame].size.height == origHeight);
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        int failed = identityChecks();
        if (failed)
            return failed;
        unsigned width = 0, height = 0;
        const char *spec = getenv("CG_TEST_MODE");
        BOOL haveMode = spec && sscanf(spec, "%ux%u", &width, &height) == 2;
        if (argc > 1 && strcmp(argv[1], "external") == 0 && haveMode)
            failed = externalChecks(width, height);
        else if (haveMode)
            failed = switchChecks(width, height);
        if (failed)
            return failed;
        printf("PASS\n");
    }
    return 0;
}
