// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process without AppKit that has an X11 window of its own (a CGS window) receives the pointer of that window as
// CGEvents: an event tap sees the mouse moved, down, up and dragged events CoreGraphics decodes from the server's
// pointer events, with the window number of the CGS window, the click state, the button number, the deltas, pressure,
// the modifier flags and the global location, and the state functions of CGEventSource follow them. Driven by
// coregraphics-x11-pointer-no-appkit.sh (XTest): the program prints "READY <window>" with the X window id, then runs
// its run loop until it sees the key "q" come up or 30 seconds have passed. The harness does:
//   a move to P-(20,20), a move to P (mouse moved, deltas 20, 20)
//   a left click, and a second one at once (click states 1 and 2)
//   a right click, a middle click
//   a left drag by 10, 5 and then 20, 10
//   a left click with Shift held
//   the key q
// Usage: coregraphics-x11-pointer-no-appkit (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n. The "CLICK" line tells the harness where the first click was.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdio.h>

typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);
extern void *_CGSNativeDisplay(CGSConnectionID cid);

enum { DeviceLeftShift = 0x2 };

typedef struct {
    CGEventType type;
    int button, click, dx, dy;
    double x, y, pressure;
    uint64_t flags;
    int64_t window;
    BOOL buttonDown;
    uint32_t counter;
} Seen;

#define MAX 512
static Seen seen[MAX];
static int count;
static BOOL quit;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventKeyUp) {
        UniChar c = 0;
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 1, &length, &c);
        if (length == 1 && c == 'q')
            quit = YES;
        return event;
    }
    if (count >= MAX)
        return event;
    Seen *s = &seen[count++];
    CGPoint location = CGEventGetLocation(event);
    s->type = type;
    s->button = (int) CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
    s->click = (int) CGEventGetIntegerValueField(event, kCGMouseEventClickState);
    s->dx = (int) CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
    s->dy = (int) CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
    s->x = location.x;
    s->y = location.y;
    s->pressure = CGEventGetDoubleValueField(event, kCGMouseEventPressure);
    s->flags = CGEventGetFlags(event);
    s->window = CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer);
    s->buttonDown = CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, (CGMouseButton) s->button);
    s->counter = CGEventSourceCounterForEventType(kCGEventSourceStateHIDSystemState, type);
    return event;
}

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static int nth(CGEventType type, int n) {
    for (int i = 0; i < count; i++) {
        if (seen[i].type == type && n-- == 0)
            return i;
    }
    return -1;
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
        if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        if (CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess) {
            printf("FAIL cannot order the window in\n");
            return 1;
        }

        CGEventMask mask = CGEventMaskBit(kCGEventKeyUp);
        for (CGEventType t = kCGEventLeftMouseDown; t <= kCGEventOtherMouseDragged; t++)
            if (t != kCGEventScrollWheel && (t <= kCGEventRightMouseDragged || t >= kCGEventOtherMouseDown))
                mask |= CGEventMaskBit(t);
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

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 30];
        while (!quit && [deadline timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);

        printf("tap events %d, window %u\n", count, (unsigned) wid);
        for (int i = 0; i < count; i++)
            printf("  tap %3d: type %2d button %d click %d at %.1f,%.1f delta %d,%d pressure %.2f flags %#llx window %lld down %d counter %u\n", i,
                   (int) seen[i].type, seen[i].button, seen[i].click, seen[i].x, seen[i].y, seen[i].dx, seen[i].dy, seen[i].pressure,
                   (unsigned long long) seen[i].flags, (long long) seen[i].window, seen[i].buttonDown, seen[i].counter);

        int m2 = nth(kCGEventMouseMoved, 1);
        expect(m2 >= 0 && seen[m2].dx == 20 && seen[m2].dy == 20 && seen[m2].pressure == 0 && seen[m2].window == wid,
               "mouse moved: the deltas of the motion, pressure 0, the window number of the CGS window");
        int d1 = nth(kCGEventLeftMouseDown, 0), u1 = nth(kCGEventLeftMouseUp, 0), d2 = nth(kCGEventLeftMouseDown, 1), u2 = nth(kCGEventLeftMouseUp, 1);
        if (d1 < 0 || u1 < 0 || d2 < 0 || u2 < 0) {
            printf("FAIL the tap sees no clicks\nFAILED %d\n", failures + 1);
            return 1;
        }
        printf("CLICK %.0f %.0f\n", seen[d1].x, seen[d1].y);
        expect(seen[d1].button == 0 && seen[d1].click == 1 && seen[d1].pressure > 0.99 && seen[d1].window == wid && !(seen[d1].flags & 0xFF0000),
               "a left press: button 0, click state 1, pressure 1, the window number, no modifiers");
        expect(seen[u1].click == 1 && seen[u1].pressure == 0 && seen[u1].window == wid, "its release: click state 1, pressure 0");
        expect(seen[d1].buttonDown && !seen[u1].buttonDown, "CGEventSourceButtonState follows the button");
        expect(seen[d2].click == 2 && seen[u2].click == 2, "the second click at once is click state 2, and so is its release");
        expect(seen[u2].counter == 2 && seen[d2].counter == 2, "CGEventSourceCounterForEventType counts the presses and releases");
        int rd = nth(kCGEventRightMouseDown, 0), md = nth(kCGEventOtherMouseDown, 0), mu = nth(kCGEventOtherMouseUp, 0);
        expect(rd >= 0 && seen[rd].button == 1 && seen[rd].click == 1 && seen[rd].buttonDown, "a right click: right mouse events, button 1, click state 1");
        expect(md >= 0 && mu >= 0 && seen[md].button == 2 && seen[md].click == 1 && seen[md].buttonDown && !seen[mu].buttonDown,
               "a middle click: other mouse events, button 2, click state 1");
        int g1 = nth(kCGEventLeftMouseDragged, 0), g2 = nth(kCGEventLeftMouseDragged, 1);
        expect(g2 >= 0 && seen[g1].dx == 10 && seen[g1].dy == 5 && seen[g2].dx == 20 && seen[g2].dy == 10 && seen[g1].pressure > 0.99 &&
                       seen[g1].button == 0 && seen[g1].buttonDown && seen[g1].window == wid,
               "a left drag: left mouse dragged with the deltas, pressure 1, the button state is down");
        int sd = nth(kCGEventLeftMouseDown, 3);
        expect(sd >= 0 && (seen[sd].flags & kCGEventFlagMaskShift) && (seen[sd].flags & DeviceLeftShift),
               "a click with Shift held: the Shift flag and the left device bit");
        expect(!CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft), "after the buttons went up, the button state is up");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
