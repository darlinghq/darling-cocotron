/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// Display mode switching: CGDisplaySwitchToMode / CGDisplaySetDisplayMode,
// CGDisplayCapture / CGDisplayRelease / CGReleaseAllDisplays, the reconfiguration
// callbacks and NSScreen's reaction. Needs a display with a second mode: on
// X11 the runner (coregraphics-display-mode-switch.sh) adds one to Xvfb; on a
// wlroots compositor (headless sway) the runner configures several modes.
// The mode to switch to is the one given by CG_TEST_MODE as WIDTHxHEIGHT.
//
// Usage: coregraphics-display-mode-switch              full test, prints PASS
//        coregraphics-display-mode-switch exit         switches to that mode
//                                                      and exits without releasing;
//                                                      the runner checks the display
//                                                      went back to its mode
// Exit code 0 is success, otherwise the number of the failed check.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
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

@interface Observer : NSObject {
@public
    int count;
}
@end
@implementation Observer
- (void) changed: (NSNotification *) note { count++; }
@end

static void spin(void) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
}

static CFDictionaryRef findMode(CGDirectDisplayID display, size_t width, size_t height) {
    boolean_t exact = false;
    CFDictionaryRef mode = CGDisplayBestModeForParameters(display, 32, width, height, &exact);
    return exact ? mode : NULL;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        CGDirectDisplayID display = CGMainDisplayID();
        CHECK(1, display != kCGNullDirectDisplay);

        const char *spec = getenv("CG_TEST_MODE");
        unsigned wantWidth = 0, wantHeight = 0;
        CHECK(2, spec && sscanf(spec, "%ux%u", &wantWidth, &wantHeight) == 2);

        size_t origWidth = CGDisplayPixelsWide(display), origHeight = CGDisplayPixelsHigh(display);
        CHECK(3, origWidth != wantWidth || origHeight != wantHeight);
        CFDictionaryRef target = findMode(display, wantWidth, wantHeight);
        CHECK(4, target != NULL);

        if (argc > 1 && strcmp(argv[1], "exit") == 0) {
            CHECK(5, CGDisplaySwitchToMode(display, target) == kCGErrorSuccess);
            CHECK(6, CGDisplayPixelsWide(display) == wantWidth);
            printf("switched\n");
            fflush(stdout);
            exit(0); // the mode goes back as the process exits
        }

        // Every mode of the display is listed by both the legacy and the CGDisplayMode calls.
        CFArrayRef newModes = CGDisplayCopyAllDisplayModes(display, NULL);
        CHECK(7, newModes != NULL && CFArrayGetCount(newModes) >= CFArrayGetCount(CGDisplayAvailableModes(display)));
        CFRelease(newModes);

        Observer *observer = [[Observer alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver: observer
                                                 selector: @selector(changed:)
                                                     name: NSApplicationDidChangeScreenParametersNotification
                                                   object: nil];
        CHECK(8, CGDisplayRegisterReconfigurationCallback(reconfigured, NULL) == kCGErrorSuccess);
        [[NSScreen screens] count]; // screens are built before the change

        // Bad arguments.
        CHECK(9, CGDisplaySwitchToMode(display, NULL) == kCGErrorIllegalArgument);
        CFDictionaryRef bogus = (__bridge CFDictionaryRef) @{ @"Width" : @7, @"Height" : @3 };
        CHECK(10, CGDisplaySwitchToMode(display, bogus) == kCGErrorIllegalArgument);
        CHECK(11, CGDisplaySwitchToMode(0xdeadbeef, target) != kCGErrorSuccess);
        CHECK(12, gBegin == 0 && gSetMode == 0);

        // Switching to the current mode changes nothing and succeeds.
        CFDictionaryRef current = CGDisplayCurrentMode(display);
        CHECK(13, CGDisplaySwitchToMode(display, current) == kCGErrorSuccess);
        CHECK(14, gBegin == 0);

        // Capture, switch, observe.
        CHECK(15, CGDisplayCapture(display) == kCGErrorSuccess);
        CHECK(16, CGDisplayIsCaptured(display));
        CHECK(17, CGDisplaySwitchToMode(display, target) == kCGErrorSuccess);
        CHECK(18, CGDisplayPixelsWide(display) == wantWidth && CGDisplayPixelsHigh(display) == wantHeight);
        CGRect bounds = CGDisplayBounds(display);
        CHECK(19, bounds.size.width == wantWidth && bounds.size.height == wantHeight);
        NSRect frame = [[NSScreen mainScreen] frame];
        CHECK(20, frame.size.width == wantWidth && frame.size.height == wantHeight);
        CFDictionaryRef now = CGDisplayCurrentMode(display);
        CHECK(21, [[(__bridge NSDictionary *) now objectForKey: (__bridge id) kCGDisplayWidth] unsignedIntValue] == wantWidth);
        CHECK(22, gBegin == 1 && gSetMode == 1 && gShape == 1 && gCallbackDisplay == display);
        spin();
        CHECK(23, observer->count == 1);

        // The same mode again is a no-op.
        CHECK(24, CGDisplaySwitchToMode(display, target) == kCGErrorSuccess);
        CHECK(25, gBegin == 1);

        // Release puts the original mode back.
        CHECK(26, CGDisplayRelease(display) == kCGErrorSuccess);
        CHECK(27, !CGDisplayIsCaptured(display));
        CHECK(28, CGDisplayPixelsWide(display) == origWidth && CGDisplayPixelsHigh(display) == origHeight);
        CHECK(29, [[NSScreen mainScreen] frame].size.width == origWidth);
        CHECK(30, gSetMode == 2);
        spin();
        CHECK(31, observer->count == 2);

        // CGDisplaySetDisplayMode with a CGDisplayModeRef, restored by CGReleaseAllDisplays.
        CHECK(32, CGCaptureAllDisplays() == kCGErrorSuccess);
        CFArrayRef all = CGDisplayCopyAllDisplayModes(display, NULL);
        CGDisplayModeRef chosen = NULL;
        for (CFIndex i = 0; i < CFArrayGetCount(all); i++) {
            CGDisplayModeRef candidate = (CGDisplayModeRef) CFArrayGetValueAtIndex(all, i);
            if (CGDisplayModeGetWidth(candidate) == wantWidth && CGDisplayModeGetHeight(candidate) == wantHeight)
                chosen = candidate;
        }
        CHECK(33, chosen != NULL);
        CHECK(34, CGDisplaySetDisplayMode(display, chosen, NULL) == kCGErrorSuccess);
        CHECK(35, CGDisplayPixelsWide(display) == wantWidth);
        CFRelease(all);
        CHECK(36, CGReleaseAllDisplays() == kCGErrorSuccess);
        CHECK(37, CGDisplayPixelsWide(display) == origWidth && CGDisplayPixelsHigh(display) == origHeight);
        CHECK(38, !CGDisplayIsCaptured(display));

        // After removing the callback it is not called again.
        CHECK(39, CGDisplayRemoveReconfigurationCallback(reconfigured, NULL) == kCGErrorSuccess);
        CHECK(40, CGDisplayRemoveReconfigurationCallback(reconfigured, NULL) != kCGErrorSuccess);
        int before = gBegin;
        CHECK(41, CGDisplaySwitchToMode(display, target) == kCGErrorSuccess);
        CHECK(42, gBegin == before);
        CHECK(43, CGDisplayRelease(display) == kCGErrorSuccess);
        CHECK(44, CGDisplayPixelsWide(display) == origWidth);

        printf("PASS\n");
    }
    return 0;
}
