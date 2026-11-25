// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The relative mouse mode, the warp and the hidden cursor of a games-style application on the Wayland backend:
// CGAssociateMouseAndMouseCursorPosition(false) locks the pointer, the mouse events carry the deltas and the cursor
// stays where it is (the NSEvents and the CGEvents seen by an event tap, CGGetLastMouseDelta), CGWarpMouseCursorPosition
// moves the cursor of the application while it is locked, CGDisplayHideCursor and +[NSCursor hide] count and hide
// the cursor of the pointer. Driven by appkit-wayland-relative-mouse.sh (a virtual pointer on a headless compositor,
// libwayland's debug output for the cursor requests): the program prints READY, then "STEP n" before each part and
// waits for the driver's motion (it pumps events for a fixed time), and "MARK name" after each cursor call. It stops
// when the key "q" comes up or after 90 seconds.
// Usage: appkit-wayland-relative-mouse (no arguments), run with DARLING_APPKIT_BACKEND=wayland
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int step;
    int type;
    int64_t dx, dy;
    double x, y; // CGEvent: global location; NSEvent: location in the window
} Seen;
#define MAX 512
static Seen tapSeen[MAX], nsSeen[MAX];
static int tapCount, nsCount, currentStep;
static BOOL quit;
static NSWindow *window;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if ((type != kCGEventMouseMoved && type != kCGEventLeftMouseDragged) || tapCount >= MAX)
        return event;
    Seen *s = &tapSeen[tapCount++];
    CGPoint p = CGEventGetLocation(event);
    s->step = currentStep;
    s->type = type;
    s->dx = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
    s->dy = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
    s->x = p.x;
    s->y = p.y;
    return event;
}

@interface NSObject (RelativeMouseFixture)
+ (id) currentDisplay;
- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) point;
- (void) setCursor: (id) cursor;
@end

// An image that draws itself flat: a cursor made of it needs no cursor theme.
@interface FlatCursorImage : NSImage
@end
@implementation FlatCursorImage
- (void) drawInRect: (NSRect) rect fromRect: (NSRect) source operation: (NSCompositingOperation) operation
           fraction: (CGFloat) fraction {
    [[NSColor cyanColor] setFill];
    NSRectFill(rect);
}
@end

@interface RelApplication : NSApplication
@end
@implementation RelApplication
- (void) sendEvent: (NSEvent *) event {
    NSEventType type = [event type];
    if (type == NSEventTypeKeyUp && [[event characters] isEqualToString: @"q"])
        quit = YES;
    if ((type == NSEventTypeMouseMoved || type == NSEventTypeLeftMouseDragged) && nsCount < MAX) {
        Seen *s = &nsSeen[nsCount++];
        s->step = currentStep;
        s->type = (int) type;
        s->dx = (int64_t) [event deltaX];
        s->dy = (int64_t) [event deltaY];
        s->x = [event locationInWindow].x;
        s->y = [event locationInWindow].y;
    }
    [super sendEvent: event];
}
@end

static void pump(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
}

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}
// The driver moves the pointer when it sees the STEP line, and the program waits for the events of the step (the
// ones of the tap), not for a time: what the program prints reaches the driver later than the pointer's events
// reach the program. STEP and MARK are written to the standard error stream, the one libwayland's debug output
// of the requests is on, so that the order of the requests and the marks is kept.
static int tapsInStep(int n) {
    int c = 0;
    for (int i = 0; i < tapCount; i++)
        c += tapSeen[i].step == n;
    return c;
}
static void step(int n, int events) {
    currentStep = n;
    fprintf(stderr, "STEP %d\n", n);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 20];
    while (tapsInStep(n) < events && [deadline timeIntervalSinceNow] > 0)
        pump(0.05);
    pump(0.5);
}
static void mark(const char *name) {
    pump(0.5);
    fprintf(stderr, "MARK %s\n", name);
    pump(0.5);
}

static void sums(int which, int64_t *dx, int64_t *dy, int *count, double *minX, double *maxX, double *minY, double *maxY, BOOL ns) {
    *dx = *dy = 0;
    *count = 0;
    *minX = *minY = 1e9;
    *maxX = *maxY = -1e9;
    Seen *list = ns ? nsSeen : tapSeen;
    int n = ns ? nsCount : tapCount;
    for (int i = 0; i < n; i++) {
        if (list[i].step != which)
            continue;
        (*count)++;
        *dx += list[i].dx;
        *dy += list[i].dy;
        *minX = fmin(*minX, list[i].x);
        *maxX = fmax(*maxX, list[i].x);
        *minY = fmin(*minY, list[i].y);
        *maxY = fmax(*maxY, list[i].y);
    }
}

int main(void) {
    @autoreleasepool {
        RelApplication *app = (RelApplication *) [RelApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventLeftMouseDragged),
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
        [window setTitle: @"relative-mouse-wayland"];
        [window setAcceptsMouseMovedEvents: YES];
        [window makeKeyAndOrderFront: nil];
        [app finishLaunching];
        // A cursor of the application's own (an image, so that it needs no cursor theme): hiding the cursor and
        // showing it again must bring it back.
        NSImage *image = [[FlatCursorImage alloc] initWithSize: NSMakeSize(16, 16)];
        // The display's own cursor call, as the cursor-scale fixture does: the window cursor machinery is not what
        // is tested here.
        id display = [NSClassFromString(@"NSDisplay") currentDisplay];
        [display setCursor: [display cursorWithImage: image hotSpot: NSMakePoint(8, 8)]];
        pump(0.5);
        fprintf(stderr, "READY\n");

        int64_t dx, dy;
        int count;
        double minX, maxX, minY, maxY;
        CGFloat primaryHeight = NSHeight([[[NSScreen screens] objectAtIndex: 0] frame]);

        // 1. the mouse is associated: moves go to the cursor and are deltas of the position
        step(1, 3);
        sums(1, &dx, &dy, &count, &minX, &maxX, &minY, &maxY, YES);
        expect(count >= 2 && maxX - minX > 5, @"associated: the NSEvents of motion carry different locations");
        int32_t ldx = 0, ldy = 0;
        CGGetLastMouseDelta(&ldx, &ldy);
        expect(ldx != 0 || ldy != 0, @"associated: CGGetLastMouseDelta has the motion since the last call");
        CGGetLastMouseDelta(&ldx, &ldy);
        expect(ldx == 0 && ldy == 0, @"CGGetLastMouseDelta starts again after each call");

        // 2. disconnected: the cursor stays, the events carry the deltas (7,4), (-3,2), (5,-6)
        CGAssociateMouseAndMouseCursorPosition(false);
        pump(1.0);
        NSPoint frozen = [NSEvent mouseLocation];
        step(2, 3);
        sums(2, &dx, &dy, &count, &minX, &maxX, &minY, &maxY, YES);
        expect(count == 3 && dx == 9 && dy == 0, [NSString stringWithFormat: @"relative: three NSEvents with deltas summing to (9, 0) (%d events, (%lld, %lld))", count, (long long) dx, (long long) dy]);
        expect(count > 0 && maxX - minX < 0.5 && maxY - minY < 0.5, @"relative: the location in the NSEvents stays where the cursor was");
        NSPoint now = [NSEvent mouseLocation];
        expect(fabs(now.x - frozen.x) < 0.5 && fabs(now.y - frozen.y) < 0.5, @"relative: +[NSEvent mouseLocation] does not move");
        sums(2, &dx, &dy, &count, &minX, &maxX, &minY, &maxY, NO);
        expect(count == 3 && dx == 9 && maxX - minX < 0.5, @"relative: the CGEvents of the tap have the same deltas and a fixed location");
        CGGetLastMouseDelta(&ldx, &ldy);
        expect(ldx == 9 && ldy == 0, [NSString stringWithFormat: @"relative: CGGetLastMouseDelta is the sum (9, 0), got (%d, %d)", ldx, ldy]);

        // 3. a warp moves the cursor of the application, the next events are at that place
        NSRect frame = [window frame];
        CGPoint target = CGPointMake(NSMinX(frame) + 150, primaryHeight - (NSMinY(frame) + 120));
        CGError warped = CGWarpMouseCursorPosition(target);
        pump(0.3);
        NSPoint after = [NSEvent mouseLocation];
        expect(warped == kCGErrorSuccess && fabs(after.x - target.x) < 0.5 && fabs(after.y - (primaryHeight - target.y)) < 0.5,
               @"warp while locked: +[NSEvent mouseLocation] is the target");
        step(3, 1);
        sums(3, &dx, &dy, &count, &minX, &maxX, &minY, &maxY, YES);
        NSPoint inWindow = [window convertScreenToBase: NSMakePoint(target.x, primaryHeight - target.y)];
        expect(count == 1 && fabs(minX - inWindow.x) < 1.5 && fabs(minY - inWindow.y) < 1.5,
               [NSString stringWithFormat: @"warp: the next event is at the target (%.1f, %.1f), expected (%.1f, %.1f)", minX, minY, inWindow.x, inWindow.y]);

        // 4. the hide count
        mark("pre");
        CGDisplayHideCursor(kCGDirectMainDisplay);
        mark("hide1");
        CGDisplayHideCursor(kCGDirectMainDisplay);
        mark("hide2");
        CGDisplayShowCursor(kCGDirectMainDisplay);
        mark("show1");
        CGDisplayShowCursor(kCGDirectMainDisplay);
        mark("show2");
        CGDisplayShowCursor(kCGDirectMainDisplay);
        mark("show3");
        [NSCursor hide];
        mark("nshide");
        [NSCursor unhide];
        mark("nsunhide");

        // 5. connected again: the pointer is free (the lock ends), then hidden until the mouse moves
        CGAssociateMouseAndMouseCursorPosition(true);
        pump(1.0);
        step(4, 2);
        [NSCursor setHiddenUntilMouseMoves: YES];
        mark("hideuntil");
        step(5, 1);
        mark("end");
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 20];
        while (!quit && [deadline timeIntervalSinceNow] > 0)
            pump(0.2);
    }
    for (int i = 0; i < tapCount; i++)
        printf("  tap %2d: step %d type %d delta %lld,%lld at %.1f,%.1f\n", i, tapSeen[i].step, tapSeen[i].type,
               (long long) tapSeen[i].dx, (long long) tapSeen[i].dy, tapSeen[i].x, tapSeen[i].y);
    for (int i = 0; i < nsCount; i++)
        printf("  ns  %2d: step %d type %d delta %lld,%lld in window %.1f,%.1f\n", i, nsSeen[i].step, nsSeen[i].type,
               (long long) nsSeen[i].dx, (long long) nsSeen[i].dy, nsSeen[i].x, nsSeen[i].y);
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
