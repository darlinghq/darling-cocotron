// Link with AppKit and Foundation. No window or event server is required.
#import <Foundation/Foundation.h>
#import <AppKit/NSEvent.h>

@interface LegacyWheelEvent : NSEvent
@end
@implementation LegacyWheelEvent
- (CGFloat) deltaX { return -2.5; }
- (CGFloat) deltaY { return 3.0; }
@end

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    LegacyWheelEvent *event = [[LegacyWheelEvent alloc] init];
    NSCAssert([event scrollingDeltaX] == -2.5, @"forward horizontal delta");
    NSCAssert([event scrollingDeltaY] == 3.0, @"forward vertical delta");
    NSCAssert(![event hasPreciseScrollingDeltas], @"legacy deltas are not precise");
    NSCAssert(![NSEvent isSwipeTrackingFromScrollEventsEnabled],
              @"no swipe tracking implementation");
    [event release];
    [pool drain];
    return 0;
}
