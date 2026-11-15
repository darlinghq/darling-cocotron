// Copyright (C) 2026 Lubos Dolezel
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>

// The named functions' control points and the eased progress for given
// elapsed fractions. Reference numbers were observed on macOS 26.7.3 and
// Mojave 10.14.4 (-[CAMediaTimingFunction _solveForInput:]); the same values
// follow from solving the cubic Bezier's x(s) = t and returning y(s).

@interface CAMediaTimingFunction (Probe)
- (float) _solveForInput: (float) input;
@end

static int failures;

static void expectNear(const char *what, double got, double want) {
    if (fabs(got - want) > 1e-4) {
        printf("%s=FAIL (got %g, want %g)\n", what, got, want);
        failures++;
    } else {
        printf("%s=PASS\n", what);
    }
}

static void expectPoints(const char *what, NSString *name, float c1x, float c1y, float c2x, float c2y) {
    CAMediaTimingFunction *f = [CAMediaTimingFunction functionWithName: name];
    float p[2][2], z[2], o[2];
    [f getControlPointAtIndex: 0 values: z];
    [f getControlPointAtIndex: 1 values: p[0]];
    [f getControlPointAtIndex: 2 values: p[1]];
    [f getControlPointAtIndex: 3 values: o];
    if (z[0] != 0 || z[1] != 0 || o[0] != 1 || o[1] != 1 || p[0][0] != c1x || p[0][1] != c1y ||
        p[1][0] != c2x || p[1][1] != c2y) {
        printf("%s=FAIL\n", what);
        failures++;
    } else {
        printf("%s=PASS\n", what);
    }
}

static void expectCurve(const char *what, CAMediaTimingFunction *f, const float *xs, const float *ys, int n) {
    for (int i = 0; i < n; i++) {
        char label[96];
        snprintf(label, sizeof label, "%s_x%.3f", what, xs[i]);
        expectNear(label, [f _solveForInput: xs[i]], ys[i]);
    }
}

int main(void) {
    @autoreleasepool {
        expectPoints("controlpoints_linear", kCAMediaTimingFunctionLinear, 0, 0, 1, 1);
        expectPoints("controlpoints_easein", kCAMediaTimingFunctionEaseIn, 0.42f, 0, 1, 1);
        expectPoints("controlpoints_easeout", kCAMediaTimingFunctionEaseOut, 0, 0, 0.58f, 1);
        expectPoints("controlpoints_easeinout", kCAMediaTimingFunctionEaseInEaseOut, 0.42f, 0, 0.58f, 1);
        expectPoints("controlpoints_default", kCAMediaTimingFunctionDefault, 0.25f, 0.1f, 0.25f, 1);
        // QUIRK coverage: an unknown name raises (observed on macOS 26.7.3 and Mojave).
        BOOL raised = NO;
        @try {
            [CAMediaTimingFunction functionWithName: @"unknown"];
        } @catch (NSException *e) {
            raised = [[e name] isEqualToString: @"CAMediaTimingFunctionInvalid"];
        }
        printf("unknown_name_raises=%s\n", raised ? "PASS" : "FAIL");
        failures += !raised;

        // Control points are floats: a value that is not exactly
        // representable round-trips as the float.
        CAMediaTimingFunction *odd = [CAMediaTimingFunction functionWithControlPoints: 0.1f : 0.2f : 0.3f : 0.4f];
        float v[2];
        [odd getControlPointAtIndex: 1 values: v];
        if (v[0] != 0.1f || v[1] != 0.2f) {
            printf("controlpoints_float_roundtrip=FAIL\n");
            failures++;
        } else {
            printf("controlpoints_float_roundtrip=PASS\n");
        }

        const float xs[] = {0, 0.25f, 0.5f, 0.75f, 1};
        const float linear[] = {0, 0.25f, 0.5f, 0.75f, 1};
        const float easeIn[] = {0, 0.09346f, 0.31536f, 0.62186f, 1};
        const float easeOut[] = {0, 0.37814f, 0.68464f, 0.90654f, 1};
        const float easeInOut[] = {0, 0.12916f, 0.5f, 0.87084f, 1};
        const float dflt[] = {0, 0.40851f, 0.80240f, 0.96046f, 1};
        expectCurve("linear", [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionLinear], xs, linear, 5);
        expectCurve("easein", [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseIn], xs, easeIn, 5);
        expectCurve("easeout", [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseOut], xs, easeOut, 5);
        expectCurve("easeinout", [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseInEaseOut], xs, easeInOut, 5);
        expectCurve("default", [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionDefault], xs, dflt, 5);

        // Control y outside [0,1] overshoots; the progress is still a function of x.
        const float cx[] = {0, 0.125f, 0.25f, 0.375f, 0.5f, 0.625f, 0.75f, 0.875f, 1};
        const float cy[] = {0, -0.20516f, -0.06541f, 0.19443f, 0.5f, 0.80557f, 1.06541f, 1.20516f, 1};
        expectCurve("overshoot", [CAMediaTimingFunction functionWithControlPoints: 0.2f : -1 : 0.8f : 2], cx, cy, 9);
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
