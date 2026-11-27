/*
  Copyright (C) 2026 Lubos Dolezel

  Licensed under the MIT license, the same as the rest of this project.
*/
// Guest side of wayland-tablet-session.sh: a borderless window that records the tablet events a Wayland
// compositor with a tablet delivers to it (the compositor in the test sends one pen stroke), then checks
// them against the stroke. Usage: tablet-session-probe <seconds>
// Prints PASS or FAIL lines, and PROBE done at the end. Prints SKIP and exits 77 when the display is neither
// the Wayland nor the X11 backend. The same stroke and the same expectations apply to both; the differences are what
// the window system can say: the X11 backend's tablets come from XInput2, where Xwayland (which x11-tablet-session.sh
// runs on the same private compositor) gives no vendor or product ids, and there is no proximity-out event, so the
// tool leaves proximity when its window goes away.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
static void expectThat(BOOL ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    fflush(stdout);
    if (!ok)
        failures++;
}

@interface TabletProbeView : NSView {
@public
    NSMutableArray *proximity, *points;
}
@end

@implementation TabletProbeView
- (BOOL) acceptsFirstResponder { return YES; }
- (void) tabletProximity: (NSEvent *) event {
    if (proximity == nil)
        proximity = [NSMutableArray new];
    [proximity addObject: event];
}
- (void) tabletPoint: (NSEvent *) event {
    if (points == nil)
        points = [NSMutableArray new];
    [points addObject: event];
}
@end

static BOOL near(double a, double b, double epsilon) { return fabs(a - b) <= epsilon; }

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 6;
        [NSApplication sharedApplication];
        id display = [NSClassFromString(@"NSDisplay") performSelector: @selector(currentDisplay)];
        BOOL x11 = [NSStringFromClass([display class]) hasPrefix: @"X11"];
        if (!x11 && ![NSStringFromClass([display class]) hasPrefix: @"Wayland"]) {
            printf("SKIP the display is %s, not the Wayland or the X11 backend\n",
                   [NSStringFromClass([display class]) UTF8String]);
            return 77;
        }
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 200)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        TabletProbeView *view = [[TabletProbeView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
        [window setContentView: view];
        if (x11) {
            // The stroke's coordinates are the root window's: the window covers them in its top left corner.
            NSRect screen = [[NSScreen mainScreen] frame];
            [window setFrameTopLeftPoint: NSMakePoint(0, NSMaxY(screen))];
        }
        [window makeKeyAndOrderFront: nil];
        printf("READY\n");
        fflush(stdout);
        // The application's event loop, by hand: queued events only reach the window from -sendEvent:.
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
        while ([end timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event != nil)
                [NSApp sendEvent: event];
        }

        if (x11) {
            // X has no proximity-out: the tool leaves with the window it was over.
            [window close];
            end = [NSDate dateWithTimeIntervalSinceNow: 1];
            while ([end timeIntervalSinceNow] > 0) {
                NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                                    untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                       inMode: NSDefaultRunLoopMode
                                                      dequeue: YES];
                if (event != nil)
                    [NSApp sendEvent: event];
            }
        }
        NSArray *prox = view->proximity, *points = view->points;
        expectThat([prox count] == 2, "two proximity events (in and out)");
        NSEvent *in = [prox count] > 0 ? [prox objectAtIndex: 0] : nil;
        NSEvent *out = [prox count] > 1 ? [prox objectAtIndex: 1] : nil;
        expectThat(in != nil && [in type] == NSEventTypeTabletProximity && [in isEnteringProximity],
              "the first proximity event is entering");
        expectThat(out != nil && ![out isEnteringProximity], "the second proximity event is leaving");
        expectThat(in != nil && [in pointingDeviceType] == NSPointingDeviceTypePen, "the tool is a pen");
        if (x11)
            printf("NOTE: the tablet's vendor and product ids are not checked on X11 (Xwayland has none to give)\n");
        else
            expectThat(in != nil && [in vendorID] == 0x1234 && [in tabletID] == 0x5678,
                       "the tablet's vendor and product ids");
        expectThat([points count] >= 4, "tablet point events arrive while the tool is in proximity");

        BOOL located = NO, half = NO, threeQuarters = NO, tilted = NO, buttonDown = NO, buttonUp = NO, hover = NO;
        for (NSEvent *e in points) {
            if (near([e locationInWindow].x, 100, 0.5) && near([e locationInWindow].y, 150, 0.5))
                located = YES;
            if (near([e pressure], 0.5, 0.01))
                half = YES;
            if (near([e pressure], 0.75, 0.01))
                threeQuarters = YES;
            if (near([e tilt].x, 30.0 / 90, 0.01) && near([e tilt].y, -20.0 / 90, 0.01))
                tilted = YES;
            if ([e buttonMask] & NSEventButtonMaskPenLowerSide)
                buttonDown = YES;
            else if ([e pressure] > 0 && [e buttonMask] == NSEventButtonMaskPenTip)
                buttonUp = YES;
            if ([e pressure] == 0)
                hover = YES;
        }
        expectThat(located, "a point at the stroke's first position in window coordinates");
        expectThat(half && threeQuarters, "pressure 0.5 and 0.75 as normalized");
        expectThat(tilted, "tilt of 30 and -20 degrees normalized to -1...1");
        expectThat(buttonDown, "the side button is in the button mask while pressed");
        expectThat(buttonUp, "the button mask has only the tip once the side button is released");
        expectThat(hover, "a point with zero pressure for the hovering tool");
        printf("PROBE done failures=%d\n", failures);
    }
    return failures ? 1 : 0;
}
