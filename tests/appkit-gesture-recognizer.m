#import <AppKit/AppKit.h>
#include <stdlib.h>

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

// Begins on press, changes on drag, ends on release; ends on a magnify end.
@interface DragRecognizer : NSGestureRecognizer
@property NSInteger resets;
@end

@implementation DragRecognizer
- (void)mouseDown:(NSEvent *)event { self.state = NSGestureRecognizerStateBegan; }
- (void)mouseDragged:(NSEvent *)event { self.state = NSGestureRecognizerStateChanged; }
- (void)mouseUp:(NSEvent *)event { self.state = NSGestureRecognizerStateEnded; }
- (void)magnifyWithEvent:(NSEvent *)event
{
    self.state = event.phase == NSEventPhaseEnded ? NSGestureRecognizerStateEnded : NSGestureRecognizerStateChanged;
}
- (void)reset { self.resets++; }
@end

@interface Target : NSObject <NSGestureRecognizerDelegate>
@property(retain) NSMutableArray *states;
@property BOOL allowBegin;
@end

@implementation Target
- (void)handle:(NSGestureRecognizer *)recognizer { [self.states addObject:@(recognizer.state)]; }
- (BOOL)gestureRecognizerShouldBegin:(NSGestureRecognizer *)recognizer { return self.allowBegin; }
@end

@interface CountingView : NSView
@property NSInteger downs;
@end

@implementation CountingView
- (void)mouseDown:(NSEvent *)event { self.downs++; }
@end

static NSEvent *mouse(NSEventType type, NSWindow *window, NSPoint point)
{
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0
                          windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                       styleMask:NSTitledWindowMask
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSView *parent = [[NSView alloc] initWithFrame:NSMakeRect(100, 0, 100, 100)];
        CountingView *child = [[CountingView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        [parent addSubview:child];
        [content addSubview:parent];
        window.contentView = content;

        Target *target = [Target new];
        target.states = [NSMutableArray array];
        target.allowBegin = YES;
        DragRecognizer *recognizer = [[DragRecognizer alloc] initWithTarget:target action:@selector(handle:)];
        expect(recognizer.enabled && recognizer.state == NSGestureRecognizerStatePossible && recognizer.view == nil,
               @"initial recognizer state");
        [parent addGestureRecognizer:recognizer];
        expect(recognizer.view == parent && [parent.gestureRecognizers isEqual:@[ recognizer ]],
               @"adding a recognizer sets its view");

        [window sendEvent:mouse(NSEventTypeLeftMouseDown, window, NSMakePoint(110, 10))];
        expect(recognizer.state == NSGestureRecognizerStateBegan && child.downs == 1,
               @"a press on a subview reaches the ancestor's recognizer and still reaches the view");
        NSPoint local = [recognizer locationInView:parent];
        expect(local.x == 10 && local.y == 10, @"locationInView converts the last event");
        [window sendEvent:mouse(NSEventTypeLeftMouseDragged, window, NSMakePoint(150, 40))];
        expect(recognizer.state == NSGestureRecognizerStateChanged, @"drag changes the recognizer");
        [window sendEvent:mouse(NSEventTypeLeftMouseUp, window, NSMakePoint(150, 40))];
        expect([target.states isEqual:(@[ @(NSGestureRecognizerStateBegan), @(NSGestureRecognizerStateChanged),
                                           @(NSGestureRecognizerStateEnded) ])],
               @"began, changed and ended send the action");
        expect(recognizer.state == NSGestureRecognizerStatePossible && recognizer.resets == 1,
               @"an ended recognizer is reset after the event");

        [target.states removeAllObjects];
        target.allowBegin = NO;
        recognizer.delegate = target;
        [window sendEvent:mouse(NSEventTypeLeftMouseDown, window, NSMakePoint(110, 10))];
        expect(target.states.count == 0 && recognizer.state == NSGestureRecognizerStatePossible &&
                   recognizer.resets == 2,
               @"a delegate that refuses to begin fails the recognizer without an action");
        recognizer.delegate = nil;

        recognizer.enabled = NO;
        [window sendEvent:mouse(NSEventTypeLeftMouseDown, window, NSMakePoint(110, 10))];
        expect(target.states.count == 0 && child.downs == 3, @"a disabled recognizer gets no events");
        recognizer.enabled = YES;

        [window sendEvent:mouse(NSEventTypeLeftMouseDown, window, NSMakePoint(10, 10))];
        expect(target.states.count == 0, @"events outside the view don't reach its recognizer");

        NSEvent *magnify = [[NSEvent_gesture alloc] initWithType:NSEventTypeMagnify location:NSMakePoint(150, 50)
                                                   modifierFlags:0 window:window phase:NSEventPhaseEnded
                                                   magnification:0 rotation:0];
        [window sendEvent:magnify];
        expect([target.states isEqual:@[ @(NSGestureRecognizerStateEnded) ]] && recognizer.resets == 3,
               @"magnify events reach recognizers");

        [target.states removeAllObjects];
        [window sendEvent:mouse(NSEventTypeLeftMouseDown, window, NSMakePoint(110, 10))];
        recognizer.enabled = NO;
        expect([target.states isEqual:(@[ @(NSGestureRecognizerStateBegan), @(NSGestureRecognizerStateCancelled) ])] &&
                   recognizer.state == NSGestureRecognizerStatePossible,
               @"disabling an active recognizer cancels it");
        recognizer.enabled = YES;

        [content addGestureRecognizer:recognizer];
        expect(recognizer.view == content && parent.gestureRecognizers.count == 0,
               @"adding to another view moves the recognizer");
        [content removeGestureRecognizer:recognizer];
        expect(recognizer.view == nil && content.gestureRecognizers.count == 0, @"removing clears the view");

        NSLog(@"PASS: NSGestureRecognizer receives window events and drives its target");
    }
    return 0;
}
