// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process without AppKit controls the pointer through CoreGraphics on X11: CGDisplayHideCursor() and
// CGDisplayShowCursor() count (CGCursorIsVisible() follows, CGSForceShowCursor() forgets the count),
// CGAssociateMouseAndMouseCursorPosition(false) freezes the cursor while the mouse makes deltas (the events and
// CGEventCreate(NULL) report the frozen cursor, kCGMouseEventDeltaX/Y and CGGetLastMouseDelta() report the motion),
// CGWarpMouseCursorPosition() moves the frozen cursor without a delta and, while the mouse is associated, drops the
// local mouse motion for CGSetLocalEventsSuppressionInterval() seconds (the motion still counts for
// CGGetLastMouseDelta()). Driven by coregraphics-x11-relative-mouse.sh (XTest): the program prints "READY <window>"
// with the X window id and takes its commands from the keys that come up in its window (the tap sees them):
//   h hide, s show, f force show (each checks CGCursorIsVisible against the count it expects)
//   d disassociate (the cursor freezes where it is), e reset the counters of the events and of the deltas
//   c check what happened since e: the events were all at the frozen cursor, their deltas add up to (25, 5)
//   g CGGetLastMouseDelta() is (25, 5)
//   w warp the frozen cursor by (100, 50): CGEventCreate(NULL) follows, the delta of the warp is 0
//   a associate again; CGEventCreate(NULL) is where the cursor froze, plus the warp
//   x set a suppression interval of 0.6 s and warp (associated) to 50 points right of where the cursor froze; y check what happened since e: no event before
//     the interval was over, one afterwards, and the dropped motion counted for CGGetLastMouseDelta()
//   z set the interval to 0 and warp; v check: an event at once
//   q quit
// Usage: coregraphics-x11-relative-mouse (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>

typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);
extern void *_CGSNativeDisplay(CGSConnectionID cid);

// Deprecated, so not in the SDK's headers
extern boolean_t CGCursorIsVisible(void);
extern CGError CGSetLocalEventsSuppressionInterval(CFTimeInterval seconds);

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static BOOL quit;
static int hides;
static CGPoint frozen, afterWarp;
static int events;                 // mouse events since 'e'
static int atFrozen;               // of those, at the cursor's position
static int sumDX, sumDY;
static CFAbsoluteTime lastReset, firstEventTime;
static CFAbsoluteTime warpTime;

static CGPoint currentLocation(void) {
    CGEventRef e = CGEventCreate(NULL);
    CGPoint p = CGEventGetLocation(e);
    CFRelease(e);
    return p;
}

static CGPoint expectedPosition;   // where events must be (the frozen cursor)

static void command(UniChar c) {
    char what[160];
    switch (c) {
    case 'h':
        CGDisplayHideCursor(kCGDirectMainDisplay);
        hides++;
        expect(CGCursorIsVisible() == (hides == 0), "after a hide the cursor is not visible");
        break;
    case 's':
        CGDisplayShowCursor(kCGDirectMainDisplay);
        if (hides > 0)
            hides--;
        snprintf(what, sizeof(what), "a show undoes one hide (pending %d): visible %d", hides, hides == 0);
        expect(CGCursorIsVisible() == (hides == 0), what);
        break;
    case 'f':
        CGSForceShowCursor(CGSMainConnectionID());
        hides = 0;
        expect(CGCursorIsVisible(), "a forced show forgets every pending hide");
        break;
    case 'd':
        frozen = currentLocation();
        expectedPosition = frozen;
        expect(CGAssociateMouseAndMouseCursorPosition(false) == kCGErrorSuccess, "CGAssociateMouseAndMouseCursorPosition(false) succeeds");
        printf("INFO frozen at %.1f %.1f\n", frozen.x, frozen.y);
        break;
    case 'e': {
        int32_t dx, dy;
        CGGetLastMouseDelta(&dx, &dy);
        events = atFrozen = sumDX = sumDY = 0;
        firstEventTime = 0;
        lastReset = CFAbsoluteTimeGetCurrent();
        break;
    }
    case 'c':
        printf("INFO %d events, %d at the frozen cursor, deltas %d,%d\n", events, atFrozen, sumDX, sumDY);
        expect(events >= 3 && atFrozen == events, "disassociated: every mouse event reports the frozen cursor");
        expect(sumDX == 25 && sumDY == 5, "disassociated: kCGMouseEventDeltaX/Y add up to the motion of the mouse (25, 5)");
        {
            CGPoint p = currentLocation();
            expect(fabs(p.x - frozen.x) < 1 && fabs(p.y - frozen.y) < 1, "disassociated: CGEventCreate(NULL) is the frozen cursor");
        }
        break;
    case 'g': {
        int32_t dx = 0, dy = 0;
        CGGetLastMouseDelta(&dx, &dy);
        snprintf(what, sizeof(what), "CGGetLastMouseDelta() is the motion (25, 5), got %d, %d", dx, dy);
        expect(dx == 25 && dy == 5, what);
        CGGetLastMouseDelta(&dx, &dy);
        expect(dx == 0 && dy == 0, "CGGetLastMouseDelta() takes what it reports");
        break;
    }
    case 'w': {
        CGPoint target = CGPointMake(frozen.x + 100, frozen.y + 50);
        expect(CGWarpMouseCursorPosition(target) == kCGErrorSuccess, "CGWarpMouseCursorPosition succeeds while disassociated");
        CGPoint p = currentLocation();
        snprintf(what, sizeof(what), "a warp moves the frozen cursor (now %.0f,%.0f)", p.x, p.y);
        expect(fabs(p.x - target.x) < 1 && fabs(p.y - target.y) < 1, what);
        int32_t dx = 99, dy = 99;
        CGGetLastMouseDelta(&dx, &dy);
        expect(dx == 0 && dy == 0, "a warp makes no mouse delta");
        afterWarp = target;
        break;
    }
    case 'a':
        expect(CGAssociateMouseAndMouseCursorPosition(true) == kCGErrorSuccess, "CGAssociateMouseAndMouseCursorPosition(true) succeeds");
        {
            CGPoint p = currentLocation();
            snprintf(what, sizeof(what), "the cursor shows where it froze, moved by the warp (now %.0f,%.0f)", p.x, p.y);
            expect(fabs(p.x - afterWarp.x) < 3 && fabs(p.y - afterWarp.y) < 3, what);
        }
        break;
    case 'x':
        CGSetLocalEventsSuppressionInterval(0.6);
        CGWarpMouseCursorPosition(CGPointMake(frozen.x + 50, frozen.y));
        warpTime = CFAbsoluteTimeGetCurrent();
        break;
    case 'y': {
        int32_t dx = 0, dy = 0;
        CGGetLastMouseDelta(&dx, &dy);
        printf("INFO %d events, first %.2f s after the warp, delta %d,%d\n", events, firstEventTime ? firstEventTime - warpTime : -1.0, dx, dy);
        expect(events >= 1 && firstEventTime - warpTime >= 0.55, "after a warp the local mouse motion is dropped for the suppression interval, then arrives");
        expect(dx >= 20 && dy >= 0, "the motion that was dropped still counts for CGGetLastMouseDelta()");
        break;
    }
    case 'z': {
        CGSetLocalEventsSuppressionInterval(0);
        int32_t dx, dy;
        CGGetLastMouseDelta(&dx, &dy);
        CGWarpMouseCursorPosition(CGPointMake(frozen.x + 30, frozen.y + 30));
        warpTime = CFAbsoluteTimeGetCurrent();
        break;
    }
    case 'v':
        expect(events >= 1 && firstEventTime - warpTime < 0.5, "with a suppression interval of 0 the motion after a warp is not dropped");
        break;
    case 'q':
        quit = YES;
        break;
    }
    fflush(stdout);
}

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventKeyUp) {
        UniChar c = 0;
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 1, &length, &c);
        if (length == 1)
            command(c);
        return event;
    }
    if (type == kCGEventMouseMoved || type == kCGEventLeftMouseDragged) {
        CGPoint p = CGEventGetLocation(event);
        events++;
        if (fabs(p.x - expectedPosition.x) < 1 && fabs(p.y - expectedPosition.y) < 1)
            atFrozen++;
        sumDX += (int) CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
        sumDY += (int) CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
        if (firstEventTime == 0)
            firstEventTime = CFAbsoluteTimeGetCurrent();
    }
    return event;
}

int main(void) {
    @autoreleasepool {
        CGSConnectionID cid = CGSMainConnectionID();
        if (cid == 0 || _CGSNativeDisplay(cid) == NULL) {
            printf("FAIL no connection to the window system\n");
            return 1;
        }
        CGRect frame = CGRectMake(100, 100, 400, 300);
        RegionRef region = NULL;
        CGSWindowID wid = 0;
        if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess ||
            CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        expect(CGCursorIsVisible(), "the cursor starts visible");

        CGEventMask mask = CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventLeftMouseDragged);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        printf("READY %lu\n", (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, wid));
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 60];
        while (!quit && [deadline timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        CGAssociateMouseAndMouseCursorPosition(true);
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
    }
    return failures != 0;
}
