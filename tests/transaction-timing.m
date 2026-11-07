// Link against Foundation and QuartzCore; exits nonzero on a failed assertion.
#import <Foundation/Foundation.h>
#import <QuartzCore/CATransaction.h>
#import <QuartzCore/CAMediaTimingFunction.h>

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CAMediaTimingFunction *function =
        [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseIn];
    NSCAssert(function != nil, @"test requires a timing function");
    [CATransaction begin];
    [CATransaction setAnimationDuration: 0.75];
    [CATransaction setAnimationTimingFunction: function];
    NSCAssert([CATransaction animationTimingFunction] == function,
              @"timing function must round trip");
    NSCAssert([CATransaction animationDuration] == 0.75,
              @"setting timing function must preserve duration");
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction: nil];
    NSCAssert([CATransaction animationTimingFunction] == nil,
              @"nil timing function must be accepted");
    [CATransaction commit];
    NSCAssert([CATransaction animationTimingFunction] == function,
              @"nested transaction must not change outer state");
    [CATransaction setAnimationTimingFunction: nil];
    NSCAssert([CATransaction animationTimingFunction] == nil,
              @"nil must clear an existing function");
    NSCAssert([CATransaction animationDuration] == 0.75,
              @"clearing timing function must preserve duration");
    [CATransaction commit];
    [pool drain];
    return 0;
}
