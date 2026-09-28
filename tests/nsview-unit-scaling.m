// Build against the candidate AppKit, then run in Darling.
#import <AppKit/AppKit.h>
#include <assert.h>
#include <math.h>

@interface BoundsObserver : NSObject {
@public
    NSUInteger count;
}
- (void) changed: (NSNotification *) notification;
@end
@implementation BoundsObserver
- (void) changed: (NSNotification *) notification { count++; }
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 80)];
    [view setBounds: NSMakeRect(12, 20, 100, 80)];
    [view setPostsBoundsChangedNotifications: YES];
    BoundsObserver *observer = [BoundsObserver new];
    [[NSNotificationCenter defaultCenter] addObserver: observer
            selector: @selector(changed:)
            name: NSViewBoundsDidChangeNotification object: view];
    [view scaleUnitSquareToSize: NSMakeSize(2, 4)];
    assert(NSEqualRects([view bounds], NSMakeRect(6, 5, 50, 20)));
    assert(NSEqualRects([view frame], NSMakeRect(0, 0, 100, 80)));
    assert(observer->count == 1);
    [view scaleUnitSquareToSize: NSMakeSize(1, 1)];
    assert(observer->count == 1);
    [view scaleUnitSquareToSize: NSMakeSize(0.5, 0.25)];
    assert(NSEqualRects([view bounds], NSMakeRect(12, 20, 100, 80)));
    assert(observer->count == 2);
    CGFloat invalid[] = {0, -1, INFINITY, NAN};
    for (NSUInteger i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        BOOL caught = NO;
        @try { [view scaleUnitSquareToSize: NSMakeSize(invalid[i], 1)]; }
        @catch (NSException *exception) {
            caught = [[exception name] isEqualToString: NSInvalidArgumentException];
        }
        assert(caught);
        assert(NSEqualRects([view bounds], NSMakeRect(12, 20, 100, 80)));
    }
    [[NSNotificationCenter defaultCenter] removeObserver: observer];
    [observer release];
    [view release];
    [pool drain];
    return 0;
}
