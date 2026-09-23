#import <AppKit/AppKit.h>
#include <math.h>
#include <stdlib.h>

// The backends create gesture events through this private class.
@interface NSEvent_gesture : NSEvent
- (instancetype)initWithType:(NSEventType)type
                    location:(NSPoint)location
               modifierFlags:(NSEventModifierFlags)modifierFlags
                      window:(NSWindow *)window
                       phase:(NSEventPhase)phase
               magnification:(CGFloat)magnification
                    rotation:(float)rotation;
@end

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface GestureView : NSView
@property NSInteger magnifications, rotations;
@property CGFloat lastMagnification;
@property float lastRotation;
@end

@implementation GestureView
- (void)magnifyWithEvent:(NSEvent *)event
{
    self.magnifications++;
    self.lastMagnification = event.magnification;
}
- (void)rotateWithEvent:(NSEvent *)event
{
    self.rotations++;
    self.lastRotation = event.rotation;
}
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        expect(NSEventTypeMagnify == 30 && NSEventTypeRotate == 18 && NSEventPhaseBegan == 1 &&
                   NSEventPhaseChanged == 4 && NSEventPhaseEnded == 8 && NSEventPhaseCancelled == 16,
               @"event type and phase values");
        expect(NSEventMaskMagnify & NSAnyEventMask, @"magnify events match NSAnyEventMask");

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                       styleMask:NSTitledWindowMask
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        GestureView *parent = [[GestureView alloc] initWithFrame:NSMakeRect(100, 0, 100, 100)];
        NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        [parent addSubview:child];
        [content addSubview:parent];
        window.contentView = content;

        NSEvent *magnify = [[NSEvent_gesture alloc] initWithType:NSEventTypeMagnify
                                                        location:NSMakePoint(120, 20)
                                                   modifierFlags:NSEventModifierFlagShift
                                                          window:window
                                                           phase:NSEventPhaseChanged
                                                   magnification:0.25
                                                        rotation:0];
        expect(magnify.type == NSEventTypeMagnify && magnify.phase == NSEventPhaseChanged &&
                   magnify.magnification == 0.25 && magnify.momentumPhase == NSEventPhaseNone &&
                   magnify.modifierFlags == NSEventModifierFlagShift && magnify.window == window,
               @"magnify event values");
        NSEvent *rotate = [[NSEvent_gesture alloc] initWithType:NSEventTypeRotate
                                                       location:NSMakePoint(120, 20)
                                                  modifierFlags:0
                                                         window:window
                                                          phase:NSEventPhaseBegan
                                                  magnification:0
                                                       rotation:-12.5f];
        expect(rotate.phase == NSEventPhaseBegan && rotate.rotation == -12.5f, @"rotate event values");

        NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                            location:NSZeroPoint
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:window.windowNumber
                                             context:nil
                                         eventNumber:0
                                          clickCount:1
                                            pressure:1];
        expect(click.phase == NSEventPhaseNone && click.magnification == 0 && click.rotation == 0,
               @"other events have no gesture values");

        BOOL raised = NO;
        @try {
            [[NSEvent_gesture alloc] initWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                           window:window phase:NSEventPhaseBegan magnification:0 rotation:0];
        } @catch (NSException *exception) {
            raised = [exception.name isEqual:NSInvalidArgumentException];
        }
        expect(raised, @"only magnify and rotate are gesture events");

        // The hit view (the child) does not handle gestures; NSResponder passes them up.
        [window sendEvent:magnify];
        [window sendEvent:rotate];
        expect(parent.magnifications == 1 && parent.lastMagnification == 0.25 && parent.rotations == 1 &&
                   parent.lastRotation == -12.5f,
               @"NSWindow delivers gestures to the view under the pointer and up the responder chain");

        NSLog(@"PASS: NSEvent magnify and rotate events carry phase, magnification and rotation");
    }
    return 0;
}
