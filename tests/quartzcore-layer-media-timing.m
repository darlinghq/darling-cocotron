/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// CALayer adopts CAMediaTiming (Apple's CAMediaTiming reference): the
// defaults are speed 1, everything else 0/NO and fill mode "removed", and a
// layer's local time is (parent time - beginTime) * speed + timeOffset, which
// -convertTime:fromLayer: and -convertTime:toLayer: apply through the tree
// (nil being absolute time).
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)
#define NEAR(a, b) (fabs((a) - (b)) < 1e-9)

int main(void) {
    @autoreleasepool {
        CALayer *parent = [CALayer layer];
        CALayer *child = [CALayer layer];
        [parent addSublayer: child];

        CHECK([child conformsToProtocol: @protocol(CAMediaTiming)], "a layer is a CAMediaTiming");
        CHECK(child.speed == 1 && child.beginTime == 0 && child.timeOffset == 0 && child.duration == 0
              && child.repeatCount == 0 && child.repeatDuration == 0 && !child.autoreverses,
              "timing defaults");
        CHECK([child.fillMode isEqualToString: kCAFillModeRemoved], "the default fill mode is removed");

        CHECK(NEAR([child convertTime: 5 fromLayer: nil], 5), "with default timing every layer is on absolute time");

        parent.beginTime = 10;
        parent.speed = 2;
        child.timeOffset = 3;
        // parent: (t - 10) * 2; child: parent time + 3
        CHECK(NEAR([parent convertTime: 12 fromLayer: nil], 4), "parent local time from absolute time");
        CHECK(NEAR([child convertTime: 12 fromLayer: nil], 7), "child local time goes through the parent");
        CHECK(NEAR([child convertTime: 7 toLayer: nil], 12), "and back to absolute time");
        CHECK(NEAR([child convertTime: 4 fromLayer: parent], 7), "between two layers");
        CHECK(NEAR([parent convertTime: 7 fromLayer: child], 4), "and the other way");

        child.speed = 0;
        CHECK(NEAR([child convertTime: 100 fromLayer: nil], 3), "a stopped layer stays at its time offset");

        child.fillMode = kCAFillModeForwards;
        CHECK([child.fillMode isEqualToString: kCAFillModeForwards], "the fill mode can be set");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
