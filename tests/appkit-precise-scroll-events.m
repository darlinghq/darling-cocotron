#import <AppKit/AppKit.h>
#include <stdlib.h>

// Scroll wheel events from a device with precise deltas (a trackpad) differ from legacy wheel
// events in three documented ways:
//   hasPreciseScrollingDeltas  https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas
//   scrollingDeltaX/Y          https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltax
//   phase                      https://developer.apple.com/documentation/appkit/nsevent/phase-swift.property
// For a precise event the scrolling deltas are the amounts to scroll by (the pages name no unit) and
// the event has a gesture phase; a legacy wheel event has no phase and its scrolling deltas are
// multiplied by a line height by the receiver. Backends mark events through this private method of
// the class that scroll wheel events are made from.
// Not run in a Darling guest or on macOS; the expectations come from the pages above.
@interface NSEvent_mouse : NSEvent
- (void)_setPreciseScrollingDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY phase:(NSEventPhase)phase;
@end

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSEvent *scrollEvent(CGFloat deltaX, CGFloat deltaY)
{
    return [NSEvent mouseEventWithType:NSScrollWheel
                              location:NSMakePoint(5, 5)
                         modifierFlags:0
                                window:nil
                            clickCount:1
                                deltaX:deltaX
                                deltaY:deltaY];
}

int main(void)
{
    @autoreleasepool
    {
        NSEvent *legacy = scrollEvent(1, -2);
        expect(legacy.type == NSScrollWheel, @"event type");
        expect(!legacy.hasPreciseScrollingDeltas, @"a wheel event has no precise deltas");
        expect(legacy.phase == NSEventPhaseNone && legacy.momentumPhase == NSEventPhaseNone,
               @"a legacy wheel event has no phase");
        expect(legacy.scrollingDeltaX == 1 && legacy.scrollingDeltaY == -2,
               @"base behavior kept: an unmarked event's scrolling deltas are its deltaX and deltaY");

        NSEventPhase phases[] = {NSEventPhaseMayBegin, NSEventPhaseBegan, NSEventPhaseChanged,
                                 NSEventPhaseEnded, NSEventPhaseCancelled};
        for (NSUInteger i = 0; i < sizeof(phases) / sizeof(phases[0]); i++)
        {
            NSEvent *precise = scrollEvent(0, 0);
            [(NSEvent_mouse *)precise _setPreciseScrollingDeltaX:12.5 deltaY:-37.25 phase:phases[i]];
            expect(precise.hasPreciseScrollingDeltas, @"marked event has precise deltas");
            expect(precise.scrollingDeltaX == 12.5 && precise.scrollingDeltaY == -37.25,
                   @"scrolling deltas are the amounts given");
            expect(precise.phase == phases[i], @"phase is the one given");
            expect(precise.momentumPhase == NSEventPhaseNone, @"no momentum phase is reported");
            expect(precise.type == NSScrollWheel, @"marking keeps the type");
        }

        // Marking one event leaves other events alone.
        NSEvent *other = scrollEvent(3, 4);
        expect(!other.hasPreciseScrollingDeltas && other.phase == NSEventPhaseNone &&
                   other.scrollingDeltaX == 3 && other.scrollingDeltaY == 4,
               @"an unmarked event is unaffected by marking another");

        // Only scroll wheel events can be marked.
        NSEvent *moved = [NSEvent mouseEventWithType:NSMouseMoved
                                            location:NSMakePoint(0, 0)
                                       modifierFlags:0
                                              window:nil
                                          clickCount:0
                                              deltaX:0
                                              deltaY:0];
        BOOL raised = NO;
        @try
        {
            [(NSEvent_mouse *)moved _setPreciseScrollingDeltaX:1 deltaY:1 phase:NSEventPhaseBegan];
        }
        @catch (NSException *exception)
        {
            raised = YES;
        }
        expect(raised, @"a non-scroll event cannot be marked precise");
        expect(!moved.hasPreciseScrollingDeltas && moved.phase == NSEventPhaseNone,
               @"a refused event is unchanged");
    }
    NSLog(@"PASS: precise scroll events");
    return 0;
}
