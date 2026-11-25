/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// CAPropertyAnimation's valueFunction (Apple's CAPropertyAnimation
// reference): none by default, and the function that is set is kept, for
// each animation, by the property animation subclasses too.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

int main(void) {
    @autoreleasepool {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath: @"transform"];
        CABasicAnimation *other = [CABasicAnimation animationWithKeyPath: @"transform"];
        CHECK(animation.valueFunction == nil, "an animation has no value function by default");

        CAValueFunction *rotate = [CAValueFunction functionWithName: kCAValueFunctionRotateZ];
        animation.valueFunction = rotate;
        CHECK(animation.valueFunction == rotate, "the value function that is set is kept");
        CHECK([animation.valueFunction.name isEqualToString: kCAValueFunctionRotateZ], "it is the function asked for");
        CHECK(other.valueFunction == nil, "setting one animation's function leaves others alone");

        animation.valueFunction = nil;
        CHECK(animation.valueFunction == nil, "the function can be taken away");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
