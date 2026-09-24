#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CASpringAnimation.h>
#include <math.h>

@interface CASpringAnimation (Private)
- (CGFloat) _springProgressAtTime: (CFTimeInterval) t;
@end

static int near(double a, double b) {
    return fabs(a - b) < 1e-3;
}

int main(void) {
    @autoreleasepool {
        CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath: @"position"];
        if (![spring isKindOfClass: [CASpringAnimation class]] || ![[spring keyPath] isEqualToString: @"position"])
            return 1;
        if (spring.mass != 1 || spring.stiffness != 100 || spring.damping != 10 || spring.initialVelocity != 0)
            return 2;
        CASpringAnimation *plain = [[[CASpringAnimation alloc] init] autorelease];
        if (plain.mass != 1 || plain.stiffness != 100 || plain.damping != 10)
            return 3;

        // Underdamped (zeta 0.5, w0 10): starts at 0, overshoots to 1 + e^(-5 pi / wd) at t = pi / wd.
        double wd = 10 * sqrt(0.75);
        if (!near([spring _springProgressAtTime: 0], 0) ||
            !near([spring _springProgressAtTime: M_PI / wd], 1 + exp(-5 * M_PI / wd)))
            return 4;
        CFTimeInterval settle = spring.settlingDuration;
        if (!(settle > 1.0 && settle < 1.42) || fabs([spring _springProgressAtTime: settle] - 1) >= 0.001)
            return 5;

        // Critically damped (c 20): 1 - e^(-10 t) (1 + 10 t).
        spring.damping = 20;
        if (!near([spring _springProgressAtTime: 0.1], 1 - exp(-1) * 2))
            return 6;
        // Overdamped with an initial velocity still starts at 0 with that slope.
        spring.damping = 50;
        spring.initialVelocity = 3;
        double slope = ([spring _springProgressAtTime: 1e-6] - [spring _springProgressAtTime: 0]) / 1e-6;
        if (!near([spring _springProgressAtTime: 0], 0) || fabs(slope - 3) > 1e-2 || !isfinite(spring.settlingDuration))
            return 7;

        spring.damping = 0;
        if (!isinf(spring.settlingDuration))
            return 8;
        @try {
            spring.mass = 0;
            return 9;
        } @catch (NSException *e) {
            if (![[e name] isEqualToString: NSInvalidArgumentException])
                return 10;
        }
    }
    return 0;
}
