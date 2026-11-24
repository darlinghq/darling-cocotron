/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// CoreGraphics' displays do not come from AppKit. The program links only Foundation and CoreGraphics
// and never loads AppKit; it checks the documented CGDisplay* behaviour of the main display (bounds
// with the origin at the main display's top-left, pixel sizes, the current mode among the listed
// ones, the display lists, the pointer and cursor calls that need no windows) and that no AppKit image
// or class appears while it does.
//
// Usage: coregraphics-displays-without-appkit              basic checks, prints PASS
//        coregraphics-displays-without-appkit external     adds the display reconfiguration
//                                                          callbacks: another client of the window
//                                                          system changes the main display's mode
//                                                          (the runner,
//                                                          coregraphics-displays-external-change.sh,
//                                                          does it when READY1 is printed and
//                                                          restores it at READY2)
//        coregraphics-displays-without-appkit exit         with CG_TEST_MODE=WIDTHxHEIGHT: switches to
//                                                          that mode and exits without restoring it
//        CG_TEST_MODE=WIDTHxHEIGHT given without arguments also switches the display in this process,
//        checks the callbacks and puts the mode back (the runners of
//        coregraphics-display-mode-switch do so)
// Exit code 0 is success, otherwise the number of the failed check.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

static int gBegin, gSetMode, gShape;
static CGDirectDisplayID gCallbackDisplay;

static void reconfigured(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *info) {
    if (flags & kCGDisplayBeginConfigurationFlag)
        gBegin++;
    if (flags & kCGDisplaySetModeFlag)
        gSetMode++;
    if (flags & kCGDisplayDesktopShapeChangedFlag)
        gShape++;
    gCallbackDisplay = display;
}

static BOOL appKitLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "AppKit.framework"))
            return YES;
    }
    return NSClassFromString(@"NSScreen") != nil || NSClassFromString(@"NSDisplay") != nil;
}

static void spinFor(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

// Runs the run loop until the condition holds or the time is up.
static BOOL waitUntil(BOOL (^condition)(void), double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while (!condition() && [end timeIntervalSinceNow] > 0)
        spinFor(0.1);
    return condition();
}

static CFDictionaryRef findMode(CGDirectDisplayID display, size_t width, size_t height) {
    boolean_t exact = false;
    CFDictionaryRef mode = CGDisplayBestModeForParameters(display, 32, width, height, &exact);
    return exact ? mode : NULL;
}

static int basicChecks(void) {
    CGDirectDisplayID main = CGMainDisplayID();
    CHECK(1, main != kCGNullDirectDisplay);

    uint32_t count = 0;
    CHECK(2, CGGetActiveDisplayList(0, NULL, &count) == kCGErrorSuccess && count >= 1);
    CGDirectDisplayID ids[16];
    uint32_t listed = 0;
    CHECK(3, CGGetActiveDisplayList(16, ids, &listed) == kCGErrorSuccess && listed == (count > 16 ? 16 : count));
    // The main display is listed first, the same in the online list.
    CHECK(4, ids[0] == main);
    uint32_t online = 0;
    CGDirectDisplayID onlineIds[16];
    CHECK(5, CGGetOnlineDisplayList(16, onlineIds, &online) == kCGErrorSuccess && online == listed && onlineIds[0] == main);
    CHECK(6, CGDisplayIsMain(main));

    // The global space has its origin at the main display's top-left corner.
    CGRect bounds = CGDisplayBounds(main);
    CHECK(7, bounds.origin.x == 0 && bounds.origin.y == 0 && bounds.size.width > 0 && bounds.size.height > 0);
    CHECK(8, CGDisplayPixelsWide(main) == (size_t) bounds.size.width && CGDisplayPixelsHigh(main) == (size_t) bounds.size.height);
    for (uint32_t i = 1; i < listed; i++) {
        CGRect other = CGDisplayBounds(ids[i]);
        // Displays do not overlap (they may share an edge).
        BOOL apart = CGRectGetMaxX(other) <= CGRectGetMinX(bounds) || CGRectGetMinX(other) >= CGRectGetMaxX(bounds) ||
                     CGRectGetMaxY(other) <= CGRectGetMinY(bounds) || CGRectGetMinY(other) >= CGRectGetMaxY(bounds);
        CHECK(9, other.size.width > 0 && apart);
        // The displays that contain a point of a display are that display.
        uint32_t found = 0;
        CGDirectDisplayID at[4];
        CGPoint inside = CGPointMake(CGRectGetMidX(other), CGRectGetMidY(other));
        CHECK(10, CGGetDisplaysWithPoint(inside, 4, at, &found) == kCGErrorSuccess && found == 1 && at[0] == ids[i]);
    }
    uint32_t found = 0;
    CGDirectDisplayID at[4];
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CHECK(11, CGGetDisplaysWithPoint(center, 4, at, &found) == kCGErrorSuccess && found == 1 && at[0] == main);
    found = 0;
    CHECK(12, CGGetDisplaysWithRect(bounds, 4, at, &found) == kCGErrorSuccess && found >= 1 && at[0] == main);
    CHECK(13, CGDisplayBounds(0xdeadbeef).size.width == 0 && CGDisplayPixelsWide(0xdeadbeef) == 0);

    // The current mode is one of the listed modes, and agrees with the bounds (in points) and the
    // pixel size.
    CGDisplayModeRef current = CGDisplayCopyDisplayMode(main);
    CHECK(14, current != NULL);
    CHECK(15, CGDisplayModeGetWidth(current) == (size_t) bounds.size.width && CGDisplayModeGetHeight(current) == (size_t) bounds.size.height);
    CHECK(16, CGDisplayModeGetPixelWidth(current) >= CGDisplayModeGetWidth(current));
    CFArrayRef all = CGDisplayCopyAllDisplayModes(main, NULL);
    CHECK(17, all != NULL && CFArrayGetCount(all) >= 1);
    BOOL listedMode = NO;
    for (CFIndex i = 0; i < CFArrayGetCount(all); i++) {
        CGDisplayModeRef candidate = (CGDisplayModeRef) CFArrayGetValueAtIndex(all, i);
        if (CGDisplayModeGetPixelWidth(candidate) == CGDisplayModeGetPixelWidth(current) &&
            CGDisplayModeGetPixelHeight(candidate) == CGDisplayModeGetPixelHeight(current) &&
            CGDisplayModeGetRefreshRate(candidate) == CGDisplayModeGetRefreshRate(current))
            listedMode = YES;
    }
    CHECK(18, listedMode);
    CFRelease(all);
    CGDisplayModeRelease(current);
    CHECK(19, CGDisplayCopyDisplayMode(0xdeadbeef) == NULL && CGDisplayCopyAllDisplayModes(0xdeadbeef, NULL) == NULL);

    // The legacy calls describe the same mode.
    CFDictionaryRef legacy = CGDisplayCurrentMode(main);
    CHECK(20, legacy != NULL);
    CHECK(21, CGDisplayBitsPerPixel(main) == 32);

    // The screen size is the EDID's or an estimate from the bounds; never zero for a display.
    CGSize size = CGDisplayScreenSize(main);
    CHECK(22, size.width > 0 && size.height > 0);

    // The pointer and cursor calls that need no windows succeed; the cursor request has nothing to hide
    // here, and the pointer stays within the desktop whatever the point.
    CHECK(23, CGDisplayHideCursor(main) == kCGErrorSuccess && CGDisplayShowCursor(main) == kCGErrorSuccess);
    // A coordinate that is not a finite number is taken as 0 and the warp goes on (the QUIRK of
    // CGWarpMouseCursorPosition, pinned by coregraphics-warp-mouse-glue), not refused as an illegal argument.
    CGError warpError = CGWarpMouseCursorPosition(CGPointMake(NAN, 0));
    CHECK(24, warpError == kCGErrorSuccess || warpError == kCGErrorCannotComplete);
    int32_t dx = 7, dy = 7;
    CGGetLastMouseDelta(&dx, &dy);
    CHECK(25, dx == 0 && dy == 0);

    CHECK(26, !appKitLoaded());
    return 0;
}

// The mode the test switches to, from CG_TEST_MODE.
static BOOL parseMode(unsigned *width, unsigned *height) {
    const char *spec = getenv("CG_TEST_MODE");
    return spec && sscanf(spec, "%ux%u", width, height) == 2;
}

static int switchChecks(unsigned wantWidth, unsigned wantHeight) {
    CGDirectDisplayID display = CGMainDisplayID();
    size_t origWidth = CGDisplayPixelsWide(display), origHeight = CGDisplayPixelsHigh(display);
    CHECK(30, origWidth != wantWidth || origHeight != wantHeight);
    CFDictionaryRef target = findMode(display, wantWidth, wantHeight);
    CHECK(31, target != NULL);
    CHECK(32, CGDisplayRegisterReconfigurationCallback(reconfigured, NULL) == kCGErrorSuccess);

    CHECK(33, CGDisplayCapture(display) == kCGErrorSuccess);
    CHECK(34, CGDisplaySwitchToMode(display, target) == kCGErrorSuccess);
    CHECK(35, CGDisplayPixelsWide(display) == wantWidth && CGDisplayPixelsHigh(display) == wantHeight);
    CGRect bounds = CGDisplayBounds(display);
    CHECK(36, bounds.size.width == wantWidth && bounds.size.height == wantHeight);
    // One begin and one end notification for this change, whatever the window system sends meanwhile.
    CHECK(37, gBegin == 1 && gSetMode == 1 && gShape == 1 && gCallbackDisplay == display);
    spinFor(0.7);
    CHECK(38, gBegin == 1 && gSetMode == 1);
    CHECK(39, CGDisplayRelease(display) == kCGErrorSuccess);
    CHECK(40, CGDisplayPixelsWide(display) == origWidth && CGDisplayPixelsHigh(display) == origHeight);
    spinFor(0.7);
    CHECK(41, gBegin == 2 && gSetMode == 2);
    CHECK(42, CGDisplayRemoveReconfigurationCallback(reconfigured, NULL) == kCGErrorSuccess);
    CHECK(43, !appKitLoaded());
    return 0;
}

// Another client of the window system changes the mode of the main display: the callbacks are called,
// with begin and then the summary, and the bounds follow, with nothing but the connection's own events
// to learn it from.
static int externalChecks(void) {
    CGDirectDisplayID display = CGMainDisplayID();
    unsigned wantWidth = 0, wantHeight = 0;
    CHECK(50, parseMode(&wantWidth, &wantHeight));
    size_t origWidth = CGDisplayPixelsWide(display), origHeight = CGDisplayPixelsHigh(display);
    CHECK(51, CGDisplayRegisterReconfigurationCallback(reconfigured, NULL) == kCGErrorSuccess);

    printf("READY1\n");
    fflush(stdout);
    CHECK(52, waitUntil(^BOOL { return gSetMode >= 1; }, 20));
    CHECK(53, gBegin >= 1 && gShape >= 1 && gCallbackDisplay == display);
    CHECK(54, CGDisplayPixelsWide(display) == wantWidth && CGDisplayPixelsHigh(display) == wantHeight);
    CGRect bounds = CGDisplayBounds(display);
    CHECK(55, bounds.size.width == wantWidth && bounds.size.height == wantHeight && bounds.origin.x == 0 && bounds.origin.y == 0);
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
    CHECK(56, mode != NULL && CGDisplayModeGetPixelWidth(mode) == wantWidth);
    CGDisplayModeRelease(mode);
    // The event is not reported twice.
    int begins = gBegin;
    spinFor(0.7);
    CHECK(57, gBegin == begins);

    printf("READY2\n");
    fflush(stdout);
    CHECK(58, waitUntil(^BOOL { return gSetMode >= 2; }, 20));
    CHECK(59, CGDisplayPixelsWide(display) == origWidth && CGDisplayPixelsHigh(display) == origHeight);
    CHECK(60, !appKitLoaded());
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK(100, !appKitLoaded());
        int failed = 0;
        unsigned wantWidth = 0, wantHeight = 0;
        if (argc > 1 && strcmp(argv[1], "external") == 0) {
            // What another client does is checked first, on its own: the display is not otherwise looked at.
            failed = externalChecks();
            if (!failed)
                failed = basicChecks();
            if (failed)
                return failed;
            printf("PASS\n");
            return 0;
        }
        failed = basicChecks();
        if (failed)
            return failed;

        if (argc > 1 && strcmp(argv[1], "exit") == 0) {
            CHECK(101, parseMode(&wantWidth, &wantHeight));
            CFDictionaryRef target = findMode(CGMainDisplayID(), wantWidth, wantHeight);
            CHECK(102, target != NULL);
            CHECK(103, CGDisplaySwitchToMode(CGMainDisplayID(), target) == kCGErrorSuccess);
            printf("switched\n");
            fflush(stdout);
            exit(0); // the mode goes back as the process exits
        } else if (parseMode(&wantWidth, &wantHeight)) {
            failed = switchChecks(wantWidth, wantHeight);
        }
        if (failed)
            return failed;
        printf("PASS\n");
    }
    return 0;
}
