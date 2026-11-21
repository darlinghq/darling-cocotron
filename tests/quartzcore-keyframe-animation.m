// CAKeyframeAnimation keeps the documented properties:
// https://developer.apple.com/documentation/quartzcore/cakeyframeanimation
// An animation made with +animationWithKeyPath: or -init is a linear one, array
// properties are copied, the path is kept, and a property animation's own key
// path still works.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

int main(void) {
    @autoreleasepool {
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath: @"position.x"];
        CHECK([animation isKindOfClass: [CAKeyframeAnimation class]], "class");
        CHECK([[animation keyPath] isEqualToString: @"position.x"], "key path");
        CHECK([[animation calculationMode] isEqualToString: kCAAnimationLinear], "default mode through +animationWithKeyPath:");
        CHECK([animation values] == nil && [animation keyTimes] == nil && [animation timingFunctions] == nil, "arrays start empty");
        CHECK([animation path] == NULL && [animation rotationMode] == nil, "path and rotation mode start empty");

        CAKeyframeAnimation *plain = [[[CAKeyframeAnimation alloc] init] autorelease];
        CHECK([[plain calculationMode] isEqualToString: kCAAnimationLinear], "default mode through -init");

        // Arrays are copied: later changes to the source do not reach the animation.
        NSMutableArray *values = [NSMutableArray arrayWithObjects: @0, @10, @20, nil];
        animation.values = values;
        [values addObject: @30];
        CHECK([[animation values] count] == 3, "values are copied (%lu)", (unsigned long) [[animation values] count]);
        CHECK([[[animation values] objectAtIndex: 1] intValue] == 10, "values keep their order");

        NSArray *times = @[@0, @0.5, @1];
        animation.keyTimes = times;
        CHECK([[animation keyTimes] isEqualToArray: times], "keyTimes");

        CAMediaTimingFunction *easeIn = [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseIn];
        CAMediaTimingFunction *easeOut = [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseOut];
        animation.timingFunctions = @[easeIn, easeOut];
        CHECK([[animation timingFunctions] count] == 2 && [[animation timingFunctions] objectAtIndex: 1] == easeOut, "timingFunctions");

        animation.calculationMode = kCAAnimationDiscrete;
        CHECK([[animation calculationMode] isEqualToString: kCAAnimationDiscrete], "calculationMode");
        animation.rotationMode = kCAAnimationRotateAuto;
        CHECK([[animation rotationMode] isEqualToString: kCAAnimationRotateAuto], "rotationMode");

        animation.tensionValues = @[@0.5];
        animation.continuityValues = @[@0.25];
        animation.biasValues = @[@-0.5];
        CHECK([[[animation tensionValues] objectAtIndex: 0] doubleValue] == 0.5, "tensionValues");
        CHECK([[[animation continuityValues] objectAtIndex: 0] doubleValue] == 0.25, "continuityValues");
        CHECK([[[animation biasValues] objectAtIndex: 0] doubleValue] == -0.5, "biasValues");

        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, 100, 50);
        animation.path = path;
        CHECK(animation.path != NULL, "path kept");
        CGPathRelease(path);
        CHECK(animation.path != NULL && !CGPathIsEmpty(animation.path), "path survives the caller's release");
        animation.path = NULL;
        CHECK(animation.path == NULL, "path cleared");

        // Inherited behaviour is untouched.
        animation.duration = 2;
        animation.additive = YES;
        CHECK(animation.duration == 2 && [animation isAdditive], "inherited properties");
    }
    if (failures == 0)
        puts("PASS: CAKeyframeAnimation properties");
    return failures != 0;
}
