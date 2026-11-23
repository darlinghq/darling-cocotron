// Copyright (C) 2026 Lubos Dolezel
//
// NSAnimation -currentValue, from the public contract
// (https://developer.apple.com/documentation/appkit/nsanimation/currentvalue
// and https://developer.apple.com/documentation/appkit/nsanimationdelegate/animation(_:valueforprogress:)):
//  - when the delegate implements -animation:valueForProgress:, its result
//    for the current progress is the current value, even outside 0.0 ... 1.0;
//  - otherwise the value is computed from the current progress and the
//    animation curve.
// The curve pages give no formula. macOS 10.14.4 and 26.7.3 (black-box observation) use sine
// curves: ease in 1 - cos(progress * pi / 2) (starts slowly, so its value lags the linear one),
// ease out sin(progress * pi / 2) (leads it) and ease in-out (1 - cos(progress * pi)) / 2; the
// linear curve is the identity. The test pins those values (QUIRK-free: they are the only
// definition of the curves).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

@interface ValueDelegate : NSObject {
@public
    NSAnimation *lastAnimation;
    NSAnimationProgress lastProgress;
}
@end

@implementation ValueDelegate
- (float) animation: (NSAnimation *) animation valueForProgress: (NSAnimationProgress) progress {
    lastAnimation = animation;
    lastProgress = progress;
    return 1 + progress; // a "rubber" value above 1.0
}
@end

static float valueAt(NSAnimation *animation, float progress) {
    [animation setCurrentProgress: progress];
    return [animation currentValue];
}

int main(void) {
    @autoreleasepool {
        NSAnimationCurve curves[] = {NSAnimationEaseInOut, NSAnimationEaseIn, NSAnimationEaseOut, NSAnimationLinear};
        NSAnimation *byCurve[4];
        for (int i = 0; i < 4; i++) {
            NSAnimation *animation = [[NSAnimation alloc] initWithDuration: 1 animationCurve: curves[i]];
            byCurve[i] = animation;
            CHECK(fabsf(valueAt(animation, 0)) < 1e-6f, "curve %d: value at 0.0", i);
            CHECK(fabsf(valueAt(animation, 1) - 1) < 1e-6f, "curve %d: value at 1.0", i);
            float previous = 0;
            for (int step = 1; step <= 20; step++) {
                float value = valueAt(animation, step / 20.0f);
                CHECK(value >= previous, "curve %d: not monotonic at step %d", i, step);
                previous = value;
            }
        }
        NSAnimation *inOut = byCurve[0], *in = byCurve[1], *out = byCurve[2], *linear = byCurve[3];
        CHECK(valueAt(linear, 0.3f) == 0.3f, "linear is the identity");
        for (int step = 0; step <= 8; step++) {
            double p = step / 8.0;
            CHECK(fabs(valueAt(in, p) - (1 - cos(p * M_PI_2))) < 1e-6, "ease in at %g", p);
            CHECK(fabs(valueAt(out, p) - sin(p * M_PI_2)) < 1e-6, "ease out at %g", p);
            CHECK(fabs(valueAt(inOut, p) - (1 - cos(p * M_PI)) / 2) < 1e-6, "ease in-out at %g", p);
        }
        // observed values (macOS 26.7.3 and 10.14.4)
        CHECK(fabsf(valueAt(in, 0.5f) - 0.29289f) < 1e-4f, "ease in at 0.5 is 0.29289");
        CHECK(fabsf(valueAt(out, 0.5f) - 0.70711f) < 1e-4f, "ease out at 0.5 is 0.70711");
        CHECK(fabsf(valueAt(inOut, 0.125f) - 0.03806f) < 1e-4f, "ease in-out at 0.125 is 0.03806");

        // a delegate's value wins, receives the animation and the current progress
        ValueDelegate *delegate = [ValueDelegate new];
        [linear setDelegate: delegate];
        CHECK(fabsf(valueAt(linear, 0.5f) - 1.5f) < 1e-6f, "delegate value is returned");
        CHECK(delegate->lastAnimation == linear, "delegate gets the animation");
        CHECK(delegate->lastProgress == 0.5f, "delegate gets the progress");
        [linear setDelegate: nil];
        CHECK(valueAt(linear, 0.5f) == 0.5f, "without a delegate the curve is used again");

        for (int i = 0; i < 4; i++)
            [byCurve[i] release];
        [delegate release];
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSAnimation currentValue");
    return 0;
}
