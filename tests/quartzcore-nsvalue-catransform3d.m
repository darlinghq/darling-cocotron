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
        // quirk_other_type_reads_identity: a value of another type reads back as
        // the identity transform (see the QUIRK in CATransform3D.m).
        if (!CATransform3DEqualToTransform([point CATransform3DValue], CATransform3DIdentity))
            return 3;
        if (!CATransform3DEqualToTransform([(NSValue *) [NSNumber numberWithInt: 3] CATransform3DValue],
                                           CATransform3DIdentity))
            return 4;
    }
    return 0;
}
