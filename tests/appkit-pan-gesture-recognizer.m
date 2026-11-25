/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSPanGestureRecognizer, fed mouse events through -[NSWindow sendEvent:],
 * as observed on macOS 26.7.3 and Mac OS X 10.14.4:
 *  - the defaults (primary button, one touch, no translation);
 *  - the first drag after the button goes down begins the pan, each further
 *    drag changes it and the button going up ends it; a click fails it, and
 *    a button outside buttonMask is ignored;
 *  - the translation is the pointer's movement since the button went down,
 *    as a vector in the view asked about (y the other way in a flipped view),
 *    and setTranslation:inView: moves where it counts from;
 *  - the velocity is zero when the pan begins, the speed since the previous
 *    event at the first change, and then four fifths of that speed and one
 *    fifth of the velocity before (on the button going up as well);
 *  - timestamp, which WebKit declares, is the last event's.
 * Needs a window server.
 */
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

@interface NSPanGestureRecognizer (Timestamp)
@property(readonly) NSTimeInterval timestamp;
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL near(NSPoint p, double x, double y)
{
    return fabs(p.x - x) < 0.01 && fabs(p.y - y) < 0.01;
}

@interface PanView : NSView
@property BOOL flippedView;
@end

@implementation PanView
- (BOOL) acceptsFirstMouse: (NSEvent *) event { return YES; }
- (BOOL) isFlipped { return self.flippedView; }
@end

// What the recognizer reported at one action.
typedef struct {
    NSGestureRecognizerState state;
    NSPoint translation, windowTranslation, velocity, location;
    NSTimeInterval timestamp;
} Report;

@interface Recorder : NSObject {
@public
    NSView *_view;
    Report _reports[32];
    int _count;
}
@end

@implementation Recorder
- (void) pan: (NSPanGestureRecognizer *) recognizer {
    if (_count == 32)
        return;
    Report *r = &_reports[_count++];
    r->state = recognizer.state;
    r->translation = [recognizer translationInView: _view];
    r->windowTranslation = [recognizer translationInView: nil];
    r->velocity = [recognizer velocityInView: _view];
    r->location = [recognizer locationInView: _view];
    r->timestamp = recognizer.timestamp;
}
@end

static NSWindow *window;

static void post(NSEventType type, double x, double y, NSTimeInterval time)
{
    NSEvent *event = [NSEvent mouseEventWithType: type location: NSMakePoint(x, y) modifierFlags: 0
                                       timestamp: time windowNumber: window.windowNumber context: nil
                                     eventNumber: 0 clickCount: 1 pressure: 1];
    [window sendEvent: event];
}

// A pan from (100, 100) in the window: right in small steps, then a bigger
// step, a new origin for the translation, one more step and the button up.
static void pan(void)
{
    post(NSEventTypeLeftMouseDown, 100, 100, 10);
    for (int step = 1; step <= 6; step++)
        post(NSEventTypeLeftMouseDragged, 100 + step, 100, 10 + step * 0.01);
}

static void checkPan(BOOL flipped)
{
    PanView *view = [[PanView alloc] initWithFrame: NSMakeRect(50, 50, 300, 200)];
    view.flippedView = flipped;
    [window.contentView addSubview: view];
    Recorder *recorder = [[Recorder alloc] init];
    recorder->_view = view;
    NSPanGestureRecognizer *recognizer = [[NSPanGestureRecognizer alloc] initWithTarget: recorder action: @selector(pan:)];
    [view addGestureRecognizer: recognizer];
    double sign = flipped ? -1 : 1;

    pan();
    post(NSEventTypeLeftMouseDragged, 120, 110, 10.1);
    [recognizer setTranslation: NSMakePoint(5, 5) inView: view];
    expect(near([recognizer translationInView: view], 5, 5), "setTranslation:inView: reads back");
    post(NSEventTypeLeftMouseDragged, 130, 110, 10.2);
    post(NSEventTypeLeftMouseUp, 130, 110, 10.3);

    Report *r = recorder->_reports;
    expect(recorder->_count == 9, "a began, seven changes and an end");
    if (recorder->_count == 9) {
        expect(r[0].state == NSGestureRecognizerStateBegan, "the first drag begins the pan");
        expect(near(r[0].translation, 1, 0) && near(r[0].velocity, 0, 0), "beginning: one point, no velocity");
        expect(near(r[0].location, 51, flipped ? 150 : 50), "beginning: the location in the view");
        expect(r[0].timestamp == 10.01, "the timestamp is the event's");
        BOOL changes = YES;
        for (int i = 1; i <= 7; i++)
            changes &= r[i].state == NSGestureRecognizerStateChanged;
        expect(changes, "each further drag changes the pan");
        expect(near(r[1].translation, 2, 0) && near(r[1].velocity, 100, 0), "first change: the speed since the previous event");
        expect(near(r[5].translation, 6, 0) && near(r[5].velocity, 100, 0), "steady speed");
        expect(near(r[6].translation, 20, sign * 10) && near(r[6].windowTranslation, 20, 10),
               "the translation in the view and in the window");
        expect(near(r[6].velocity, 300, sign * 200), "a fifth of the velocity before and four fifths of the speed");
        expect(near(r[7].translation, 15, 5) && near(r[7].windowTranslation, 15, sign * 5),
               "the translation counts from where setTranslation:inView: put it");
        expect(near(r[7].velocity, 140, sign * 40), "velocity after the new origin");
        expect(r[8].state == NSGestureRecognizerStateEnded, "the button going up ends the pan");
        expect(near(r[8].translation, 15, 5) && near(r[8].velocity, 28, sign * 8), "ending: the button's event counts for the velocity");
        expect(r[8].timestamp == 10.3, "the timestamp of the end");
    }
    expect(recognizer.state == NSGestureRecognizerStatePossible && near([recognizer translationInView: view], 0, 0),
           "after the pan the recognizer starts again");

    recorder->_count = 0;
    post(NSEventTypeLeftMouseDown, 100, 100, 20);
    post(NSEventTypeLeftMouseUp, 100, 100, 20.1);
    expect(recorder->_count == 0 && recognizer.state == NSGestureRecognizerStatePossible, "a click is no pan");

    post(NSEventTypeRightMouseDown, 100, 100, 30);
    post(NSEventTypeRightMouseDragged, 130, 100, 30.1);
    post(NSEventTypeRightMouseUp, 130, 100, 30.2);
    expect(recorder->_count == 0, "the secondary button is not in the default mask");

    recognizer.buttonMask = 2;
    post(NSEventTypeLeftMouseDown, 100, 100, 40);
    post(NSEventTypeLeftMouseDragged, 130, 100, 40.1);
    post(NSEventTypeLeftMouseUp, 130, 100, 40.2);
    expect(recorder->_count == 0, "a button outside buttonMask is ignored");

    [view removeGestureRecognizer: recognizer];
    [view removeFromSuperview];
    [recognizer release];
    [recorder release];
    [view release];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        [window makeKeyAndOrderFront: nil];

        NSPanGestureRecognizer *fresh = [[NSPanGestureRecognizer alloc] initWithTarget: nil action: NULL];
        expect(fresh.buttonMask == 1 && fresh.numberOfTouchesRequired == 1, "the defaults");
        expect(fresh.state == NSGestureRecognizerStatePossible && fresh.timestamp == 0
                   && near([fresh translationInView: nil], 0, 0) && near([fresh velocityInView: nil], 0, 0),
               "a new recognizer has not moved");
        [fresh release];

        checkPan(NO);
        checkPan(YES);
        [window close];
    }

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
