// Copyright (C) 2026 Lubos Dolezel
//
// NSAnimation -currentValue, from the public contract
// (https://developer.apple.com/documentation/appkit/nsanimation/currentvalue
// and https://developer.apple.com/documentation/appkit/nsanimationdelegate/animation(_:valueforprogress:)):
//  - when the delegate implements -animation:valueForProgress:, its result
//    for the current progress is the current value, even outside 0.0 ... 1.0;
//  - otherwise the value is computed from the current progress and the
//    animation curve.
// The curve pages (https://developer.apple.com/documentation/appkit/nsanimation/curve/easein
// and .../easeout) say ease in "slows down as it reaches the end" and ease out
// "slowly speeds up from the start", so the ease-in value leads the linear one
// and the ease-out value lags it. They give no formula. The test pins only
// that direction and what the choice in the implementation promises: every
// curve maps 0.0 to 0.0 and 1.0 to 1.0 and rises monotonically, the linear
// curve is the identity, and the ease-in-out curve is symmetric around the
// middle and starts slowly.
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
            CHECK(valueAt(animation, 0) == 0, "curve %d: value at 0.0", i);
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
        CHECK(valueAt(in, 0.5f) > 0.5f, "ease in slows down at the end, so it leads the linear value");
        CHECK(valueAt(out, 0.5f) < 0.5f, "ease out speeds up from the start, so it lags the linear value");
        CHECK(fabsf(valueAt(inOut, 0.5f) - 0.5f) < 1e-6f, "ease in-out passes through the middle");
        CHECK(fabsf(valueAt(inOut, 0.25f) + valueAt(inOut, 0.75f) - 1) < 1e-6f, "ease in-out is symmetric");
        CHECK(valueAt(inOut, 0.25f) < 0.25f, "ease in-out starts slowly");

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
