#import <QuartzCore/QuartzCore.h>

int main(void) {
    @autoreleasepool {
        CATransform3D t = CATransform3DMakeTranslation(1, 2, 3);
        t = CATransform3DScale(t, 2, 4, 8);
        NSValue *value = [NSValue valueWithCATransform3D: t];
        if (strcmp([value objCType], @encode(CATransform3D)) != 0)
            return 1;
        if (!CATransform3DEqualToTransform([value CATransform3DValue], t))
            return 2;

        NSValue *point = [NSValue valueWithBytes: &(CGPoint){1, 2} objCType: @encode(CGPoint)];
        @try {
            [point CATransform3DValue];
            return 3;
        } @catch (NSException *e) {
            if (![[e name] isEqualToString: NSInvalidArgumentException])
                return 4;
        }
    }
    return 0;
}
