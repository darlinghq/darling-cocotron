// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The pointer of the Wayland compositor reaches AppKit as CGEvents: the event taps of the process see the mouse down,
// up, dragged and moved events CoreGraphics decodes from the wl_pointer (button number, click state within the user's
// double-click interval and distance, pressure, deltas in whole points with the fraction carried to the next event, the
// modifier flags with the device bits, the global location), the state functions of CGEventSource follow them, and the
// NSEvents AppKit makes are made from the CGEvents the taps passed on, so that a tap that moves an event or changes
// its click state changes what the application gets. Driven by appkit-pointer-cgevents-wayland.sh (a virtual
// pointer and keyboard on a headless compositor): the program prints READY, then reads events until it sees the key
// "q" come up or 90 seconds have passed. The harness does, in this order (P is a point inside the window):
//   three moves; the window has not asked to be told of mouse moves: the tap sees them, the application does not
//   a left click at P (the first NSEvent makes the window accept mouse moved events), moves, back to P
//   four moves of 0.5, 0.25 points (fractional positions: whole deltas, the fraction carried)
//   after a pause longer than the double-click interval (1 second by default): a triple click (click state 1, 2, 3)
//   after a pause: a click (1), a click 2 points away (2), a click 38 points further (1)
//   after a pause: left, then right, then middle click at once (each button counts its own clicks)
//   a left, a right and a middle drag
//   a click with Shift, a click with Control (the tap makes its click state 9), a click with Command (the tap moves
//   it by 25, 15 points), all three at P, a pause apart
//   a click of the side button (button number 3)
// Usage: appkit-pointer-cgevents-wayland (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

// The device-dependent bits of the modifier flags (IOKit's IOLLEvent.h)
enum {
    DeviceLeftControl = 0x1,
    DeviceLeftShift = 0x2,
};

typedef struct {
    int seq;
    CGEventType type;
    int button;
    int click;
    double x, y;
    int dx, dy;
    double pressure;
    uint64_t flags;
    BOOL buttonDown;
    uint32_t counter;
} Seen;

#define MAX 2048
static Seen tapSeen[MAX], nsSeen[MAX];
static int tapCount, nsCount, sequence, nsMovedBeforeFirstClick;
static BOOL quit, acceptsMoved;
static NSWindow *window;

static BOOL isMouse(CGEventType t) {
    return (t >= kCGEventLeftMouseDown && t <= kCGEventRightMouseDragged) || t == kCGEventOtherMouseDown ||
           t == kCGEventOtherMouseUp || t == kCGEventOtherMouseDragged;
}

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (!isMouse(type) || type == kCGEventScrollWheel)
        return event;

    if (tapCount < MAX) {
        Seen *seen = &tapSeen[tapCount++];
        CGPoint location = CGEventGetLocation(event);
        seen->seq = ++sequence;
        seen->type = type;
        seen->button = (int) CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
        seen->click = (int) CGEventGetIntegerValueField(event, kCGMouseEventClickState);
        seen->x = location.x;
        seen->y = location.y;
        seen->dx = (int) CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
        seen->dy = (int) CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
        seen->pressure = CGEventGetDoubleValueField(event, kCGMouseEventPressure);
        seen->flags = CGEventGetFlags(event);
        seen->buttonDown = CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, (CGMouseButton) seen->button);
        seen->counter = CGEventSourceCounterForEventType(kCGEventSourceStateHIDSystemState, type);
    }

    // A tap that changes an event: Control makes the click state of a left press and release 9, Command moves any
    // event by 25, 15 points.
    uint64_t flags = CGEventGetFlags(event);
    if ((type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp) && (flags & kCGEventFlagMaskControl))
        CGEventSetIntegerValueField(event, kCGMouseEventClickState, 9);
    if (flags & kCGEventFlagMaskCommand) {
        CGPoint location = CGEventGetLocation(event);
        CGEventSetLocation(event, CGPointMake(location.x + 25, location.y + 15));
    }
    return event;
}

@interface PointerApplication : NSApplication
@end

@implementation PointerApplication
- (void) sendEvent: (NSEvent *) event {
    NSEventType type = [event type];
    if (type == NSEventTypeKeyUp && [[event characters] isEqualToString: @"q"])
        quit = YES;
    BOOL mouse = type == NSEventTypeLeftMouseDown || type == NSEventTypeLeftMouseUp || type == NSEventTypeLeftMouseDragged ||
                 type == NSEventTypeRightMouseDown || type == NSEventTypeRightMouseUp || type == NSEventTypeRightMouseDragged ||
                 type == NSEventTypeOtherMouseDown || type == NSEventTypeOtherMouseUp || type == NSEventTypeOtherMouseDragged ||
                 type == NSEventTypeMouseMoved;
    if (mouse && nsCount < MAX) {
        Seen *seen = &nsSeen[nsCount++];
        NSPoint location = [event locationInWindow];
        if ([event window] != nil)
            location = [[event window] convertBaseToScreen: location];
        seen->seq = ++sequence;
        seen->type = (CGEventType) type;
        BOOL pressOrRelease = type != NSEventTypeMouseMoved && type != NSEventTypeLeftMouseDragged &&
                              type != NSEventTypeRightMouseDragged && type != NSEventTypeOtherMouseDragged;
        seen->button = type == NSEventTypeMouseMoved ? 0 : (int) [event buttonNumber];
        seen->click = pressOrRelease ? (int) [event clickCount] : 0;
        seen->x = location.x;
        // The screen's y grows upwards here; the CGEvents' downwards
        seen->y = [[NSScreen screens][0] frame].size.height - location.y;
        seen->dx = (int) [event deltaX];
        seen->dy = (int) [event deltaY];
        seen->flags = [event modifierFlags];
        if (type == NSEventTypeLeftMouseDown && !acceptsMoved) {
            acceptsMoved = YES;
            nsMovedBeforeFirstClick = 0;
            for (int i = 0; i < nsCount - 1; i++)
                if (nsSeen[i].type == kCGEventMouseMoved)
                    nsMovedBeforeFirstClick++;
            [window setAcceptsMouseMovedEvents: YES];
        }
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

// The index of the nth (from 0) event of the type in the list, -1 when there are fewer
static int nth(Seen *list, int count, CGEventType type, int n) {
    for (int i = 0; i < count; i++) {
        if (list[i].type == type && n-- == 0)
            return i;
    }
    return -1;
}

static BOOL near(double a, double b) {
    return fabs(a - b) < 0.5;
}

int main(void) {
    @autoreleasepool {
        PointerApplication *app = (PointerApplication *) [PointerApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        CGEventMask mask = 0;
        for (CGEventType t = kCGEventLeftMouseDown; t <= kCGEventOtherMouseDragged; t++)
            if (t != kCGEventScrollWheel)
                mask |= CGEventMaskBit(t);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask,
                                             tapCallback, NULL);
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
        [window setTitle: @"ptr-cgevents-wayland"];
        [window makeKeyAndOrderFront: nil];
        [app finishLaunching];
        printf("READY\n");
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 90];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
        }
        printf("tap events %d, NSEvents %d\n", tapCount, nsCount);
        for (int i = 0; i < tapCount; i++)
            printf("  tap %3d: type %2d button %d click %d at %.1f,%.1f delta %d,%d pressure %.2f flags %#llx down %d counter %u\n",
                   tapSeen[i].seq, (int) tapSeen[i].type, tapSeen[i].button, tapSeen[i].click, tapSeen[i].x, tapSeen[i].y,
                   tapSeen[i].dx, tapSeen[i].dy, tapSeen[i].pressure, (unsigned long long) tapSeen[i].flags,
                   tapSeen[i].buttonDown, tapSeen[i].counter);
        for (int i = 0; i < nsCount; i++)
            printf("  ns  %3d: type %2d button %d click %d at %.1f,%.1f delta %d,%d flags %#llx\n", nsSeen[i].seq,
                   (int) nsSeen[i].type, nsSeen[i].button, nsSeen[i].click, nsSeen[i].x, nsSeen[i].y, nsSeen[i].dx,
                   nsSeen[i].dy, (unsigned long long) nsSeen[i].flags);

        // Left clicks in the order the harness makes them: 0 single, 1 to 3 triple, 4 timing, 5 near, 6 far, 7 with
        // the other buttons, 8 drag, 9 Shift, 10 Control, 11 Command.
        enum { L_SINGLE = 0, L_TRIPLE = 1, L_AFTERPAUSE = 4, L_NEAR = 5, L_FAR = 6, L_BUTTONS = 7, L_DRAG = 8, L_SHIFT = 9,
               L_CONTROL = 10, L_COMMAND = 11 };
        // KWin takes the click of the Meta key (Command) for its own window move: NO_COMMAND_CLICK=1 says the harness made
        // no such click
        int clicks = getenv("NO_COMMAND_CLICK") != NULL ? 11 : 12;
        int down[12], up[12];
        for (int i = 0; i < 12; i++) {
            down[i] = nth(tapSeen, tapCount, kCGEventLeftMouseDown, i);
            up[i] = nth(tapSeen, tapCount, kCGEventLeftMouseUp, i);
        }
        int rd = nth(tapSeen, tapCount, kCGEventRightMouseDown, 0), ru = nth(tapSeen, tapCount, kCGEventRightMouseUp, 0);
        int md = nth(tapSeen, tapCount, kCGEventOtherMouseDown, 0), mu = nth(tapSeen, tapCount, kCGEventOtherMouseUp, 0);

        BOOL all = YES;
        for (int i = 0; i < clicks; i++)
            all = all && down[i] >= 0 && up[i] >= 0;
        expect(all, [NSString stringWithFormat: @"the taps see %d left presses and releases", clicks]);
        if (!all) {
            printf("FAILED %d\n", failures);
            return 1;
        }

        // Fields of a click
        Seen *d = &tapSeen[down[L_SINGLE]], *u = &tapSeen[up[L_SINGLE]];
        expect(d->button == 0 && u->button == 0 && d->click == 1 && u->click == 1, @"a left click: button 0, click state 1 on both events");
        expect(d->pressure > 0.99 && u->pressure == 0, @"pressure 1 on the press, 0 on the release");
        expect(d->buttonDown && !u->buttonDown, @"CGEventSourceButtonState follows the button (down inside the press, up inside the release)");
        expect(d->dx == 0 && d->dy == 0, @"a press has no motion");
        expect((d->flags & 0xFF0000) == 0, @"no modifier flags");

        // Click state
        expect(tapSeen[down[L_TRIPLE]].click == 1 && tapSeen[down[L_TRIPLE] + 0].type == kCGEventLeftMouseDown, @"the first click after a pause is click 1");
        expect(tapSeen[down[L_TRIPLE + 1]].click == 2 && tapSeen[down[L_TRIPLE + 2]].click == 3, @"clicks within the interval: 2 and 3");
        expect(tapSeen[up[L_TRIPLE]].click == 1 && tapSeen[up[L_TRIPLE + 1]].click == 2 && tapSeen[up[L_TRIPLE + 2]].click == 3,
               @"each release reports the click state of its own press");
        expect(tapSeen[down[L_AFTERPAUSE]].click == 1, @"a click after the double-click interval is click 1");
        expect(tapSeen[down[L_NEAR]].click == 2, @"a click 2 points away within the interval continues the count");
        expect(tapSeen[down[L_FAR]].click == 1, @"a click 40 points away starts over");
        expect(rd >= 0 && ru >= 0 && tapSeen[rd].button == 1 && tapSeen[rd].click == 1 && tapSeen[ru].click == 1,
               @"a right click right after a left click: button 1 and click 1 (the buttons count apart)");
        expect(md >= 0 && mu >= 0 && tapSeen[md].button == 2 && tapSeen[md].click == 1 && tapSeen[mu].button == 2,
               @"a middle click: other mouse events, button 2, click 1");
        expect(rd >= 0 && tapSeen[rd].buttonDown && md >= 0 && tapSeen[md].buttonDown && !tapSeen[ru].buttonDown,
               @"the state of the right and the middle button follows");

        // Counters of the hardware state
        int leftDowns = 0, leftUps = 0;
        for (int i = 0; i < tapCount; i++) {
            leftDowns += tapSeen[i].type == kCGEventLeftMouseDown;
            leftUps += tapSeen[i].type == kCGEventLeftMouseUp;
        }
        int lastClick = clicks - 1;
        expect(tapSeen[down[lastClick]].counter == (uint32_t) leftDowns && tapSeen[up[lastClick]].counter == (uint32_t) leftUps && leftDowns == clicks,
               [NSString stringWithFormat: @"CGEventSourceCounterForEventType counts every left press and release (%d each)", clicks]);

        // Motion: the first move reaches the taps and not
        // the application, whose window has not asked for mouse moved events
        int firstDown = down[L_SINGLE];
        int m0 = nth(tapSeen, tapCount, kCGEventMouseMoved, 0);
        expect(m0 >= 0 && m0 < firstDown, @"the tap sees the mouse moved event of a window that has not asked for them");
        expect(nsMovedBeforeFirstClick == 0, @"a window that has not asked for mouse moved events gets none");
        // After the first click the window accepts them: moves of 10,10, 15,5 and -25,-15 points
        int afterUp = up[L_SINGLE];
        int m1 = -1, m2 = -1, m3 = -1;
        for (int i = afterUp; i < tapCount; i++) {
            if (tapSeen[i].type != kCGEventMouseMoved)
                continue;
            if (m1 < 0) m1 = i; else if (m2 < 0) m2 = i; else if (m3 < 0) m3 = i;
        }
        expect(m3 >= 0 && tapSeen[m1].dx == 10 && tapSeen[m1].dy == 10 && tapSeen[m2].dx == 15 && tapSeen[m2].dy == 5 &&
                       tapSeen[m3].dx == -25 && tapSeen[m3].dy == -15 && tapSeen[m1].button == 0 && tapSeen[m1].pressure == 0,
               @"mouse moved: the deltas of the motion (signed, y down), pressure 0");
        int tapMoved = 0, nsMoved = 0, tapSumX = 0, tapSumY = 0, nsSumX = 0, nsSumY = 0;
        for (int i = afterUp; i < tapCount; i++) {
            if (tapSeen[i].type == kCGEventMouseMoved) {
                tapMoved++;
                tapSumX += tapSeen[i].dx;
                tapSumY += tapSeen[i].dy;
            }
        }
        for (int i = 0; i < nsCount; i++) {
            if (nsSeen[i].type == kCGEventMouseMoved) {
                nsMoved++;
                nsSumX += nsSeen[i].dx;
                nsSumY += nsSeen[i].dy;
            }
        }
        expect(tapMoved >= 3 && nsMoved >= 1 && nsMoved <= tapMoved && nsSumX == tapSumX && nsSumY == tapSumY,
               [NSString stringWithFormat: @"AppKit's mouse moved events carry the same motion (tap %d events %d,%d; app %d events %d,%d)",
                                           tapMoved, tapSumX, tapSumY, nsMoved, nsSumX, nsSumY]);

        // Drags
        int ld = nth(tapSeen, tapCount, kCGEventLeftMouseDragged, 0), ld1 = nth(tapSeen, tapCount, kCGEventLeftMouseDragged, 1);
        expect(ld >= 0 && ld1 >= 0 && tapSeen[ld].dx == 10 && tapSeen[ld].dy == 5 && tapSeen[ld1].dx == 20 && tapSeen[ld1].dy == 10 &&
                       tapSeen[ld].button == 0 && tapSeen[ld].pressure > 0.99 && tapSeen[ld].buttonDown,
               @"a left drag: left mouse dragged with the deltas, button 0, pressure 1, the button state is down");
        int rdr = nth(tapSeen, tapCount, kCGEventRightMouseDragged, 0), odr = nth(tapSeen, tapCount, kCGEventOtherMouseDragged, 0);
        expect(rdr >= 0 && tapSeen[rdr].button == 1 && tapSeen[rdr].dx == 10 && tapSeen[rdr].dy == 5, @"a right drag: right mouse dragged, button 1");
        expect(odr >= 0 && tapSeen[odr].button == 2 && tapSeen[odr].dx == 10 && tapSeen[odr].dy == 5, @"a middle drag: other mouse dragged, button 2");
        int nsDrag = 0, nsDragX = 0, nsDragY = 0;
        for (int i = 0; i < nsCount; i++) {
            if (nsSeen[i].type == kCGEventLeftMouseDragged) {
                nsDrag++;
                nsDragX += nsSeen[i].dx;
                nsDragY += nsSeen[i].dy;
            }
        }
        expect(nsDrag >= 1 && nsDragX == 30 && nsDragY == 15, [NSString stringWithFormat: @"AppKit's left drag events add up to the motion (%d,%d)", nsDragX, nsDragY]);

        // AppKit's NSEvents are made from the CGEvents: the same types, buttons, click states and (screen) locations
        int nsLeftDown = 0, mismatch = 0;
        for (int i = 0; i < tapCount && i < MAX; i++) {
            if (tapSeen[i].type != kCGEventLeftMouseDown)
                continue;
            int n = nth(nsSeen, nsCount, kCGEventLeftMouseDown, nsLeftDown++);
            if (n < 0 || nsSeen[n].button != 0 || nsSeen[n].click != (i == down[L_CONTROL] ? 9 : tapSeen[i].click) ||
                !near(nsSeen[n].x, tapSeen[i].x + (clicks == 12 && i == down[L_COMMAND] ? 25 : 0)) ||
                !near(nsSeen[n].y, tapSeen[i].y + (clicks == 12 && i == down[L_COMMAND] ? 15 : 0)))
                mismatch++;
        }
        expect(nsLeftDown == clicks && mismatch == 0,
               [NSString stringWithFormat: @"AppKit's %d left presses have the click states and locations of the CGEvents (%d differ)", clicks, mismatch]);

        // Modifier flags
        Seen *sd = &tapSeen[down[L_SHIFT]];
        expect((sd->flags & kCGEventFlagMaskShift) != 0, @"a click with Shift: the Shift flag");
        // The device bit needs a keymap that names the key Shift_L at a keycode the process can tell (wtype makes
        // a keymap of its own for every run, whose keys are not those of a keyboard); DEVICE_BITS=1 says it has one
        if (getenv("DEVICE_BITS") != NULL)
            expect((sd->flags & DeviceLeftShift) != 0, @"and the left device bit");
        int nsShift = nth(nsSeen, nsCount, kCGEventLeftMouseDown, L_SHIFT);
        expect(nsShift >= 0 && (nsSeen[nsShift].flags & NSEventModifierFlagShift), @"AppKit's press has the Shift flag");

        // A tap that changes a click and one that moves it
        int nsControl = nth(nsSeen, nsCount, kCGEventLeftMouseDown, L_CONTROL);
        expect(nsControl >= 0 && nsSeen[nsControl].click == 9, @"the tap made the click state 9: AppKit's clickCount is 9");
        if (clicks == 12) {
            int nsCommand = nth(nsSeen, nsCount, kCGEventLeftMouseDown, L_COMMAND);
            expect(nsCommand >= 0 && nsShift >= 0 && near(nsSeen[nsCommand].x, nsSeen[nsShift].x + 25) && near(nsSeen[nsCommand].y, nsSeen[nsShift].y + 15),
                   @"the tap moved the click by 25, 15: AppKit's location moved with it");
            int nsCommandUp = nth(nsSeen, nsCount, kCGEventLeftMouseUp, L_COMMAND);
            expect(nsCommandUp >= 0 && near(nsSeen[nsCommandUp].x, nsSeen[nsCommand].x) && near(nsSeen[nsCommandUp].y, nsSeen[nsCommand].y), @"and its release");
        }

        // Fractional motion: four moves of 0.5, 0.25 points make whole deltas that add up (the fraction is carried to
        // the next event), and the location of the events moves by the fractions
        int f[4] = {-1, -1, -1, -1}, fn = 0;
        for (int i = m3 + 1; i < tapCount && fn < 4; i++)
            if (tapSeen[i].type == kCGEventMouseMoved)
                f[fn++] = i;
        if (fn == 4) {
            int sx = 0, sy = 0, large = 0;
            for (int k = 0; k < 4; k++) {
                sx += tapSeen[f[k]].dx;
                sy += tapSeen[f[k]].dy;
                large += abs(tapSeen[f[k]].dx) > 1 || abs(tapSeen[f[k]].dy) > 1;
            }
            expect(sx == 2 && sy == 1 && !large, [NSString stringWithFormat: @"four moves of 0.5, 0.25 points: whole deltas that add up to 2, 1 (got %d, %d)", sx, sy]);
            double fx = tapSeen[f[3]].x - tapSeen[f[0]].x, fy = tapSeen[f[3]].y - tapSeen[f[0]].y;
            expect(fabs(fx - 1.5) < 0.05 && fabs(fy - 0.75) < 0.05,
                   [NSString stringWithFormat: @"the global location moves by the fractions (%.2f, %.2f of 1.5, 0.75)", fx, fy]);
        } else {
            expect(NO, @"four fractional mouse moved events");
        }

        // The side button is the fourth button: other mouse events, button number 3
        int sideDown = -1, sideUp = -1;
        for (int i = 0; i < tapCount; i++) {
            if (tapSeen[i].type == kCGEventOtherMouseDown && tapSeen[i].button == 3 && sideDown < 0)
                sideDown = i;
            if (tapSeen[i].type == kCGEventOtherMouseUp && tapSeen[i].button == 3 && sideUp < 0)
                sideUp = i;
        }
        expect(sideDown >= 0 && sideUp > sideDown && tapSeen[sideDown].click == 1, @"the side button: other mouse down and up, button number 3, click 1");
        expect(sideDown >= 0 && tapSeen[sideDown].buttonDown && !tapSeen[sideUp].buttonDown, @"and CGEventSourceButtonState of button 3 follows it");

        // The location of the clicks in the NSEvents agrees with the CGEvents' (the tap that moved the Command click
        // moved the NSEvent with it, above); the window of the application got the events
        int nsOther = nth(nsSeen, nsCount, kCGEventOtherMouseDown, 2);
        expect(nsOther >= 0 || nth(nsSeen, nsCount, kCGEventOtherMouseDown, 1) >= 0, @"AppKit got the other mouse events too");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
