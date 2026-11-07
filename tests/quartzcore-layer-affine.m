#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static void expect(BOOL condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static BOOL near(CGFloat a, CGFloat b)
{
    return fabs(a - b) < 0.0001;
}

int main(void)
{
    @autoreleasepool {
        CALayer *layer = [[CALayer alloc] init];
        CGAffineTransform identity = [layer affineTransform];
        expect(near(identity.a, 1) && near(identity.d, 1) &&
               near(identity.b, 0) && near(identity.c, 0) &&
               near(identity.tx, 0) && near(identity.ty, 0),
               "default affine transform is identity");

        CGAffineTransform value = CGAffineTransformMake(2, 0.25, -0.5, 3, 7, 11);
        [layer setAffineTransform:value];
        CGAffineTransform result = [layer affineTransform];
        expect(near(result.a, 2) && near(result.b, 0.25) &&
               near(result.c, -0.5) && near(result.d, 3) &&
               near(result.tx, 7) && near(result.ty, 11),
               "affine transform round trip");
        CATransform3D t = [layer transform];
        expect(near(t.m11, 2) && near(t.m12, 0.25) &&
               near(t.m21, -0.5) && near(t.m22, 3) &&
               near(t.m41, 7) && near(t.m42, 11) && near(t.m33, 1),
               "affine setter updates the layer transform used by the renderer");

        t = CATransform3DMakeTranslation(4, 6, 0);
        [layer setTransform:t];
        result = [layer affineTransform];
        expect(near(result.tx, 4) && near(result.ty, 6) &&
               near(result.a, 1) && near(result.d, 1),
               "3D transform updates affine getter");
        [layer release];
    }
    puts("PASS: CALayer affine transform and 3D transform agree");
    return 0;
}
