#import <Foundation/NSRaise.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#include <math.h>
#import <QuartzCore/CAMediaTimingFunction.h>

NSString *const kCAMediaTimingFunctionLinear = @"kCAMediaTimingFunctionLinear";
NSString *const kCAMediaTimingFunctionEaseIn = @"kCAMediaTimingFunctionEaseIn";
NSString *const kCAMediaTimingFunctionEaseOut =
        @"kCAMediaTimingFunctionEaseOut";
NSString *const kCAMediaTimingFunctionEaseInEaseOut =
        @"kCAMediaTimingFunctionEaseInEaseOut";
NSString *const kCAMediaTimingFunctionDefault =
        @"kCAMediaTimingFunctionDefault";

@implementation CAMediaTimingFunction

- initWithControlPoints: (float)
                    c1x: (float) c1y
                       :(float) c2x
                       :(float) c2y
{
    _c1x = c1x;
    _c1y = c1y;
    _c2x = c2x;
    _c2y = c2y;
    return self;
}

+ functionWithControlPoints: (float)
                        c1x: (float) c1y
                           :(float) c2x
                           :(float) c2y
{
    return [[[self alloc] initWithControlPoints: c1x: c1y:c2x:c2y] autorelease];
}

+ functionWithName: (NSString *) name {
    if ([name isEqualToString: kCAMediaTimingFunctionLinear])
        return [self functionWithControlPoints: 0: 0:1:1];
    if ([name isEqualToString: kCAMediaTimingFunctionEaseIn])
        return [self functionWithControlPoints: 0.42: 0:1:1];
    if ([name isEqualToString: kCAMediaTimingFunctionEaseOut])
        return [self functionWithControlPoints: 0: 0:0.58:1];
    if ([name isEqualToString: kCAMediaTimingFunctionEaseInEaseOut])
        return [self functionWithControlPoints: 0.42: 0:0.58:1];
    if ([name isEqualToString: kCAMediaTimingFunctionDefault])
        return [self functionWithControlPoints: 0.25: 0.1:0.25:1];

    // QUIRK: an unknown name raises CAMediaTimingFunctionInvalid rather than
    // returning nil. Not documented. Evidence: black-box observation on macOS
    // 26.7.3 and Mojave 10.14.4 (tier 2). Test: quartzcore-media-timing-function
    // (unknown_name_raises)
    [NSException raise: @"CAMediaTimingFunctionInvalid"
                format: @"unknown timing function name: %@", name];
    return nil;
}

- (void) getControlPointAtIndex: (size_t) index values: (float[2]) ptr {

    switch (index) {

    default:
    case 0:
        ptr[0] = 0;
        ptr[1] = 0;
        break;

    case 1:
        ptr[0] = _c1x;
        ptr[1] = _c1y;
        break;

    case 2:
        ptr[0] = _c2x;
        ptr[1] = _c2y;
        break;

    case 3:
        ptr[0] = 1;
        ptr[1] = 1;
        break;
    }
}


// The curve is the cubic Bezier through (0,0), c1, c2, (1,1), parameterised by
// s in [0,1]. The animation's elapsed fraction t is the curve's x, so the
// eased progress is y at the s where x(s) = t, not y at s = t. The x
// polynomial is not guaranteed monotonic when a control x lies outside
// [0,1]; Newton's method is tried first and bisection on [0,1] is the
// fallback so a result is always produced.
static double bezier(double a, double b, double s) {
    double u = 1.0 - s;
    return 3.0 * u * u * s * a + 3.0 * u * s * s * b + s * s * s;
}

static double bezierDerivative(double a, double b, double s) {
    double u = 1.0 - s;
    return 3.0 * u * u * a + 6.0 * u * s * (b - a) + 3.0 * s * s * (1.0 - b);
}

- (float) _solveForInput: (float) input {
    double t = input;

    if (t <= 0.0)
        t = 0.0;
    else if (t >= 1.0)
        t = 1.0;

    double s = t;
    BOOL converged = NO;

    for (int i = 0; i < 8; i++) {
        double error = bezier(_c1x, _c2x, s) - t;
        if (fabs(error) < 1e-9) {
            converged = YES;
            break;
        }
        double slope = bezierDerivative(_c1x, _c2x, s);
        if (fabs(slope) < 1e-6)
            break;
        s -= error / slope;
        if (s < 0.0 || s > 1.0)
            break;
    }

    if (!converged) {
        double lo = 0.0, hi = 1.0;
        s = t;
        for (int i = 0; i < 64; i++) {
            if (bezier(_c1x, _c2x, s) < t)
                lo = s;
            else
                hi = s;
            s = (lo + hi) / 2.0;
        }
    }

    return bezier(_c1y, _c2y, s);
}

@end
