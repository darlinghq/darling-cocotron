// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The scrolling of the Wayland compositor reaches AppKit as scroll wheel CGEvents: the event taps of the process
// see what CoreGraphics decodes from the wl_pointer axis events (line deltas, pixel deltas, the continuous flag,
// the scroll phases of a finger on a touchpad), and the NSEvents AppKit makes are made from them. Driven by
// appkit-scroll-cgevents-wayland.sh (a virtual pointer on a headless compositor): the program prints READY, then
// reads events until it sees the key "q" come up or 60 seconds have passed. The harness does, in this order, over
// the window:
//   a wheel turned one notch down, one notch to the right, two notches up (axis_discrete, wheel source)
//   a finger scroll: 12, then 6 axis units down, then the axis stops
//   five finger frames of 0.4 units and a stop (the fractions are carried)
//   a scroll of the continuous source (a pixel scroll without a finger: no phases)
//   a finger scroll that is cut short by the pointer leaving the window (the cancelled phase)
//   with Shift held (a virtual keyboard): a wheel notch down, and a finger scroll of 12 units, then stop
// The wheel notches give the same line, fixed-point and point deltas, and so the same NSEvents, as the X11 wheel
// (appkit-scroll-cgevents-x11): the wayland axis value of a notch (15 on the compositors used here) does not show.
// Usage: appkit-scroll-cgevents-wayland (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int seq;
    int64_t lines1, lines2, points1, points2, phase, momentum;
    double fixed1, fixed2;
    int continuous;
    double x, y;
    uint64_t flags;
    int64_t window;
    // NSEvent: deltaX/Y, scrolling deltas, precise, phase
    double dx, dy, sdx, sdy;
    int precise;
    unsigned long nsPhase;
} Seen;

#define MAX 256
static Seen tapSeen[MAX], nsSeen[MAX];
static int tapCount, nsCount, sequence;
static BOOL quit;
static NSWindow *window;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type != kCGEventScrollWheel || tapCount >= MAX)
        return event;
    Seen *s = &tapSeen[tapCount++];
    CGPoint location = CGEventGetLocation(event);
    s->seq = ++sequence;
    s->lines1 = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
    s->lines2 = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2);
    s->points1 = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
    s->points2 = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2);
    s->fixed1 = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
    s->fixed2 = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2);
    s->continuous = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous);
    s->phase = CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
    s->momentum = CGEventGetIntegerValueField(event, kCGScrollWheelEventMomentumPhase);
    s->x = location.x;
    s->y = location.y;
    s->flags = CGEventGetFlags(event);
    return event;
}

@interface ScrollApplication : NSApplication
@end

@implementation ScrollApplication
- (void) sendEvent: (NSEvent *) event {
    NSEventType type = [event type];
    if (type == NSEventTypeKeyUp && [[event characters] isEqualToString: @"q"])
        quit = YES;
    if (type == NSEventTypeScrollWheel && nsCount < MAX) {
        Seen *s = &nsSeen[nsCount++];
        s->seq = ++sequence;
        s->dx = [event deltaX];
        s->dy = [event deltaY];
        s->sdx = [event scrollingDeltaX];
        s->sdy = [event scrollingDeltaY];
        s->precise = [event hasPreciseScrollingDeltas];
        s->nsPhase = (unsigned long) [event phase];
        s->window = [event window] == window;
        NSPoint location = [event locationInWindow];
        s->x = location.x;
        s->y = location.y;
    }
    [super sendEvent: event];
}
@end

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

int main(void) {
    @autoreleasepool {
        ScrollApplication *app = (ScrollApplication *) [ScrollApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventScrollWheel), tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 500, 400)
                                             styleMask: NSTitledWindowMask
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        [window setTitle: @"scroll-cgevents-wayland"];
        [window makeKeyAndOrderFront: nil];
        [app finishLaunching];
        printf("READY\n");
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 60];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
        }
        printf("tap events %d, NSEvents %d\n", tapCount, nsCount);
        for (int i = 0; i < tapCount; i++) {
            Seen *s = &tapSeen[i];
            printf("  tap %2d: lines %lld,%lld points %lld,%lld fixed %.4f,%.4f continuous %d phase %lld momentum %lld at %.1f,%.1f flags %#llx\n",
                   s->seq, (long long) s->lines1, (long long) s->lines2, (long long) s->points1, (long long) s->points2,
                   s->fixed1, s->fixed2, s->continuous, (long long) s->phase, (long long) s->momentum, s->x, s->y,
                   (unsigned long long) s->flags);
        }
        for (int i = 0; i < nsCount; i++) {
            Seen *s = &nsSeen[i];
            printf("  ns  %2d: delta %.4f,%.4f scrolling %.2f,%.2f precise %d phase %lu inwindow %lld at %.1f,%.1f\n", s->seq, s->dx,
                   s->dy, s->sdx, s->sdy, s->precise, s->nsPhase, (long long) s->window, s->x, s->y);
        }

        // 1 to 3 the wheel, 4 to 6 the finger, 7 to 12 the fractions and their end, 13 continuous source, 14 and 15 cut short,
        // 16 the wheel notch with Shift, 17 and 18 the finger with Shift
        expect(tapCount == nsCount && tapCount >= 18,
               [NSString stringWithFormat: @"every scroll event reached both the tap and the application (%d, %d of 18 or more)", tapCount, nsCount]);
        if (tapCount < 18 || nsCount < 18) {
            printf("FAILED %d\n", failures);
            return 1;
        }

        // The wheel: lines, no pixel precision, no phase
        Seen *w1 = &tapSeen[0], *w2 = &tapSeen[1], *w3 = &tapSeen[2];
        expect(!w1->continuous && w1->lines1 == -1 && w1->lines2 == 0 && w1->phase == 0 && w1->momentum == 0,
               @"a wheel notch down: not continuous, one line down (-1), no phase");
        expect(fabs(w1->fixed1 + 1.0) < 0.01 && w1->points1 == -10 && w1->points2 == 0,
               @"a notch is one line whatever its axis value (15 here): fixed -1.0 lines, 10 points, as on X11");
        expect(!w2->continuous && w2->lines2 == -1 && w2->lines1 == 0 && fabs(w2->fixed2 + 1.0) < 0.01, @"a notch to the right: horizontal, -1");
        expect(!w3->continuous && w3->lines1 == 2 && fabs(w3->fixed1 - 2.0) < 0.01 && w3->points1 == 20, @"two notches up: two lines up (2), 2.0 lines, 20 points");
        Seen *n1 = &nsSeen[0];
        expect(!n1->precise && fabs(n1->dy + 1.0) < 0.01 && n1->nsPhase == 0 && n1->window && n1->dx == 0,
               @"AppKit: a wheel event with deltaY -1, not precise, no phase, for the window (the X11 wheel's event)");

        // A finger scroll: continuous, phases began, changed, ended; the points are the axis units
        Seen *f1 = &tapSeen[3], *f2 = &tapSeen[4], *f3 = &tapSeen[5];
        expect(f1->continuous && f1->phase == kCGScrollPhaseBegan && f1->points1 == -12 && f1->momentum == 0,
               @"a finger: continuous, began, 12 points down");
        expect(f2->continuous && f2->phase == kCGScrollPhaseChanged && f2->points1 == -6, @"then changed, 6 points down");
        expect(f3->continuous && f3->phase == kCGScrollPhaseEnded && f3->points1 == 0 && f3->lines1 == 0, @"then ended with no motion for the axis stop");
        expect(nsSeen[3].precise && nsSeen[3].nsPhase == NSEventPhaseBegan && nsSeen[3].sdy == -12 && fabs(nsSeen[3].dy + 1.2) < 0.01 &&
                       nsSeen[4].nsPhase == NSEventPhaseChanged && nsSeen[5].nsPhase == NSEventPhaseEnded,
               @"AppKit: precise events with the phases, scrollingDeltaY -12 and deltaY -1.2 lines");

        // The fractions: five frames of about 0.4 units make whole points that add up
        double fixedSum = 0;
        int64_t pointSum = 0;
        int ends = 0;
        for (int i = 6; i < 12; i++) {
            fixedSum += tapSeen[i].fixed1;
            pointSum += tapSeen[i].points1;
            ends += tapSeen[i].phase == kCGScrollPhaseEnded;
        }
        // 0.4 is 0.3984375 as a wl_fixed: five of them are 1.99 units, 0.199 lines
        expect(fabs(fixedSum + 0.1992) < 0.002 && llabs(pointSum) <= 2 && ends == 1 && tapSeen[6].phase == kCGScrollPhaseBegan,
               [NSString stringWithFormat: @"five frames of 0.4 units: %.4f lines, %lld whole points in all (the fractions are carried), one end", fixedSum, (long long) pointSum]);
        expect(llabs(tapSeen[7].points1) <= 1 && llabs(tapSeen[8].points1) <= 1, @"each frame's points are a whole number, 0 or -1");

        // Continuous source: pixels, no phases
        Seen *c1 = &tapSeen[12];
        expect(c1->continuous && c1->phase == 0 && c1->points1 == -7, @"the continuous source: continuous, no phase, 7 points down");
        expect(nsSeen[12].precise && nsSeen[12].nsPhase == 0, @"AppKit: precise, no phase");

        // Cut short: began, then cancelled when the pointer leaves
        Seen *k1 = &tapSeen[13], *k2 = &tapSeen[14];
        expect(k1->phase == kCGScrollPhaseBegan && k2->phase == kCGScrollPhaseCancelled && k2->points1 == 0 && k2->continuous,
               @"a finger scroll the pointer leaves the window in: began, then cancelled");
        expect(nsSeen[14].nsPhase == NSEventPhaseCancelled, @"AppKit's event has the cancelled phase");
        // With Shift held: the same conversion as X11's wheel, made where the NSEvent is made from the CGEvent
        Seen *s1 = &tapSeen[15], *s2 = &tapSeen[16], *s3 = &tapSeen[17];
        Seen *m1 = &nsSeen[15], *m2 = &nsSeen[16];
        expect(!s1->continuous && s1->lines1 == -1 && s1->lines2 == 0 && (s1->flags & kCGEventFlagMaskShift),
               @"a wheel notch with Shift held: the CGEvent keeps its vertical line and has the Shift flag");
        expect(!m1->precise && fabs(m1->dx + 1.0) < 0.01 && m1->dy == 0,
               @"QUIRK (Shift): the NSEvent of a wheel line with Shift held scrolls sideways: deltaX -1, deltaY 0");
        expect(s2->continuous && s2->phase == kCGScrollPhaseBegan && s2->points1 == -12 && s3->phase == kCGScrollPhaseEnded &&
                       m2->precise && m2->dx == 0 && fabs(m2->dy + 1.2) < 0.01 && m2->sdy == -12,
               @"a finger scroll with Shift held is not converted: deltaY -1.2, scrolling delta -12");
        expect(tapSeen[0].x == tapSeen[1].x && tapSeen[0].y == tapSeen[1].y && nsSeen[0].window,
               @"the events carry the pointer's location and name the window");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
