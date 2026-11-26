/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

// Touch events as CGEvents (darlinghq/darling#937, item E1), with no display: fingers of a touch screen
// are gesture CGEvents (type 29) with Darling's touch fields (CoreGraphicsPrivate.h), which the window
// system's backends post, and which AppKit turns into direct touch events (a view that handles
// touches) or mouse events (any other view). The test posts them with CGEventPost, in the process.
// Also pinned: an event tap sees the touch CGEvents, +[NSEvent eventWithCGEvent:] of them, and of a
// gesture event without touch data (the behavior of macOS 26.7.3: NSEvent of type 29, no touches;
// vd-upstream/mac-probes/touch-cgevent).
enum {
    kTouchIdentifier = 194, kTouchPhase = 195, kTouchNormalizedX = 196, kTouchNormalizedY = 197,
    kTouchDeviceWidth = 198, kTouchDeviceHeight = 199, kTouchLocationUnknown = 200, kTouchWindowNumber = 201,
};

static int failures, checks;
static void expect(BOOL ok, const char *what) {
    ++checks;
    if (!ok)
        ++failures;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    fflush(stdout);
}

@interface TouchView : NSView {
@public
    int began, moved, ended, cancelled;
    NSEvent *last;
}
@end
@implementation TouchView
- (void) touchesBeganWithEvent: (NSEvent *) e { began++; last = e; }
- (void) touchesMovedWithEvent: (NSEvent *) e { moved++; last = e; }
- (void) touchesEndedWithEvent: (NSEvent *) e { ended++; last = e; }
- (void) touchesCancelledWithEvent: (NSEvent *) e { cancelled++; last = e; }
@end

static NSWindow *window;
static NSView *plainView;
static TouchView *touchView;
static int tapped, tappedBegan;
static const CGFloat height = 200;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == 29) {
        tapped++;
        if (CGEventGetIntegerValueField(event, kTouchPhase) == 1)
            tappedBegan++;
    }
    return event;
}

static CGFloat screenHeight(void) {
    NSArray *screens = [NSScreen screens];
    return [screens count] > 0 ? NSMaxY([[screens objectAtIndex: 0] frame]) : 0;
}

// A finger of the touch screen, as the window system's backend would report it: base coordinates of the
// window, from its bottom left.
static CGEventRef makeTouch(NSWindow *w, long long finger, int phase, double x, double y) {
    CGEventRef e = CGEventCreate(NULL);
    CGEventSetType(e, (CGEventType) 29);
    CGEventSetIntegerValueField(e, kTouchIdentifier, finger);
    CGEventSetIntegerValueField(e, kTouchPhase, phase);
    NSPoint screen = [w convertBaseToScreen: NSMakePoint(x, y)];
    CGEventSetLocation(e, CGPointMake(screen.x, screenHeight() - screen.y));
    CGEventSetIntegerValueField(e, kTouchWindowNumber, [w windowNumber]);
    return e;
}

static void post(CGEventRef e) {
    CGEventPost(kCGSessionEventTap, e);
    CFRelease(e);
}

static void finger(long long id, int phase, double x, double y) {
    post(makeTouch(window, id, phase, x, y));
}

// Everything the event queue has, which the application also sends
static NSArray *drain(void) {
    NSMutableArray *events = [NSMutableArray array];
    NSEvent *e;
    while ((e = [NSApp nextEventMatchingMask: NSEventMaskAny
                                   untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                      inMode: NSDefaultRunLoopMode
                                     dequeue: YES]) != nil) {
        [events addObject: e];
        [NSApp sendEvent: e];
    }
    return events;
}

static BOOL near(NSPoint p, double x, double y) { return fabs(p.x - x) < 0.01 && fabs(p.y - y) < 0.01; }

static NSTouch *touchWithPhase(NSEvent *e, NSTouchPhase phase) {
    for (NSTouch *t in [e allTouches])
        if ([t phase] == phase)
            return t;
    return nil;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, height)
                                             styleMask: NSTitledWindowMask
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        NSView *content = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, height)];
        plainView = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, height)];
        touchView = [[TouchView alloc] initWithFrame: NSMakeRect(100, 0, 100, height)];
        [content addSubview: plainView];
        [content addSubview: touchView];
        [window setContentView: content];
        [window orderFront: nil];
        drain();

        CGEventMask mask = (CGEventMask) 1 << 29;
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             mask, tapCallback, NULL);
        expect(tap != NULL, "an event tap for gesture events can be created");
        if (tap != NULL)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(NULL, tap, 0), kCFRunLoopCommonModes);

        // A view that handles touches: direct touch events with the fingers
        CGEventRef down = makeTouch(window, 7, 1, 150, 50);
        CGEventSetIntegerValueField(down, kTouchNormalizedX, 500000);
        CGEventSetIntegerValueField(down, kTouchNormalizedY, 250000);
        CGEventSetIntegerValueField(down, kTouchDeviceWidth, 1000 * 1024);
        CGEventSetIntegerValueField(down, kTouchDeviceHeight, 500 * 1024);
        post(down);
        NSArray *events = drain();
        NSEvent *e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(e != nil && [e type] == NSEventTypeDirectTouch, "a touch screen finger on a touch view is a direct touch event");
        NSTouch *t = e ? touchWithPhase(e, NSTouchPhaseBegan) : nil;
        expect(t != nil && [[e allTouches] count] == 1, "one touch, in the Began phase");
        expect(t != nil && [t type] == NSTouchTypeDirect && [t identity] != nil, "direct type, with an identity");
        expect(t != nil && near([t locationInView: nil], 150, 50), "location in window base coordinates");
        expect(t != nil && near([t locationInView: touchView], 50, 50), "location in the view");
        expect(t != nil && near([t normalizedPosition], 0.5, 0.25), "the normalized position of the device");
        expect(t != nil && fabs([t deviceSize].width - 1000) < 0.01 && fabs([t deviceSize].height - 500) < 0.01,
               "the size of the device");
        expect(touchView->began == 1, "touchesBeganWithEvent: reached the view once");
        expect(e != nil && [[e touchesMatchingPhase: NSTouchPhaseBegan inView: touchView] count] == 1,
               "touchesMatchingPhase:inView: finds the finger in its view");
        id identity = [t identity];

        finger(7, 2, 160, 60);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        t = e ? touchWithPhase(e, NSTouchPhaseMoved) : nil;
        expect(t != nil && [[t identity] isEqual: identity] && near([t locationInView: nil], 160, 60) &&
                       near([t previousLocationInView: nil], 150, 50),
               "the move keeps the identity and gives the previous location");
        expect(touchView->moved == 1, "touchesMovedWithEvent: reached the view");

        // A second finger: both fingers are in the event, the first one stationary
        finger(8, 1, 170, 120);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(e != nil && [[e allTouches] count] == 2 && touchWithPhase(e, NSTouchPhaseBegan) != nil &&
                       touchWithPhase(e, NSTouchPhaseStationary) != nil,
               "the second finger's event has both, the first stationary");

        // The end carries no position: the finger ends where it last was
        CGEventRef up = makeTouch(window, 7, 8, 0, 0);
        CGEventSetIntegerValueField(up, kTouchLocationUnknown, 1);
        post(up);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        t = e ? touchWithPhase(e, NSTouchPhaseEnded) : nil;
        expect(t != nil && near([t locationInView: nil], 160, 60), "an end without a position is where the finger was");
        expect(touchView->ended == 1, "touchesEndedWithEvent: reached the view");

        // A cancel
        finger(8, 16, 170, 120);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(e != nil && touchWithPhase(e, NSTouchPhaseCancelled) != nil && touchView->cancelled == 1,
               "a cancelled finger reaches touchesCancelledWithEvent:");

        // A finger number used again without an end is cancelled first
        finger(9, 1, 150, 150);
        drain();
        finger(9, 1, 155, 155);
        events = drain();
        expect([events count] == 2 && touchWithPhase([events objectAtIndex: 0], NSTouchPhaseCancelled) != nil &&
                       touchWithPhase([events objectAtIndex: 1], NSTouchPhaseBegan) != nil,
               "a finger number that begins again cancels the old finger first");
        finger(9, 8, 155, 155);
        drain();

        // A view that takes no touches: the finger moves the mouse (view bottom-left origin)
        finger(1, 1, 50, 150);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(e != nil && [e type] == NSLeftMouseDown && near([e locationInWindow], 50, 150) && [e clickCount] == 1 &&
                       [e window] == window,
               "a finger on a plain view is a left mouse down in its window");
        finger(1, 2, 60, 140);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(e != nil && [e type] == NSLeftMouseDragged && near([e locationInWindow], 60, 140) &&
                       [e deltaX] == 10 && [e deltaY] == 10,
               "the move is a left mouse drag with deltas (y down)");
        finger(1, 8, 0, 0); // an end that names a position, which wins
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(e != nil && [e type] == NSLeftMouseUp, "the end is a left mouse up");
        finger(1, 1, 52, 148);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(e != nil && [e type] == NSLeftMouseDown && [e clickCount] == 2, "a quick second tap is a double click");
        finger(1, 8, 52, 148);
        drain();

        // The mouse is taken by one finger: a second one on a plain view is ignored
        finger(1, 1, 50, 150);
        finger(2, 1, 60, 160);
        events = drain();
        expect([events count] == 1, "a second finger on a view that takes no touches is ignored");
        finger(1, 8, 50, 150);
        finger(2, 8, 60, 160);
        drain();

        // Fingers that cannot be given to a window are dropped
        CGEventRef lost = makeTouch(window, 3, 1, 150, 50);
        CGEventSetIntegerValueField(lost, kTouchWindowNumber, 99999);
        post(lost);
        events = drain();
        expect([events count] == 0, "a finger that begins in no window of the application gives no event");
        // A move of a finger that never began
        finger(4, 2, 150, 50);
        events = drain();
        expect([events count] == 0, "a move of an unknown finger gives no event");

        // The event tap saw every touch event, with the fields as they were posted
        expect(tap == NULL || (tapped == 19 && tappedBegan == 9), "the event tap saw the touch CGEvents");

        // +[NSEvent eventWithCGEvent:]
        CGEventRef raw = makeTouch(window, 5, 2, 120, 80);
        CGEventSetIntegerValueField(raw, kTouchNormalizedX, 100000);
        NSEvent *made = [NSEvent eventWithCGEvent: raw];
        t = [[made allTouches] anyObject];
        expect(made != nil && [made type] == NSEventTypeDirectTouch && [[made allTouches] count] == 1 && t != nil &&
                       [t phase] == NSTouchPhaseMoved && near([t locationInView: nil], 120, 80) &&
                       fabs([t normalizedPosition].x - 0.1) < 1e-6,
               "eventWithCGEvent: of a touch CGEvent is a direct touch event of the one finger");
        CFRelease(raw);

        // A gesture CGEvent without touch data is an ordinary gesture event with no touches (macOS 26.7.3)
        CGEventRef plain = CGEventCreate(NULL);
        CGEventSetType(plain, (CGEventType) 29);
        CGEventSetLocation(plain, CGPointMake(100, 200));
        made = [NSEvent eventWithCGEvent: plain];
        expect(made != nil && [made type] == NSEventTypeGesture && [[made class] isEqual: [NSEvent class]],
               "eventWithCGEvent: of a gesture CGEvent without touch data is a plain gesture NSEvent");
        expect(made != nil && [[made touchesMatchingPhase: NSTouchPhaseAny inView: nil] count] == 0 &&
                       [[made allTouches] count] == 0,
               "and it has no touches");
        CFRelease(plain);

        printf("RESULT checks=%d failures=%d\n", checks, failures);
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED\n");
    }
    return failures == 0 ? 0 : 1;
}
