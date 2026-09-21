#import <QuartzCore/CATransform3D.h>
#include <stdio.h>
#include <math.h>
#include <string.h>

// Expected values come from Core Animation's documented semantics, in the
// row-vector convention the struct uses: v' = v * M, translation in m41..m43.

static int failures = 0;

static void eq(const char *what, CATransform3D got, CATransform3D want) {
    CGFloat a[16], b[16];

    memcpy(a, &got, sizeof got);
    memcpy(b, &want, sizeof want);

    for (int i = 0; i < 16; i++) {
        if (fabs(a[i] - b[i]) > 1e-9) {
            printf("%s=FAIL (element %d: %g, want %g)\n", what, i, (double)a[i], (double)b[i]);
            failures++;
            return;
        }
    }
    printf("%s=PASS\n", what);
}

static void eqbool(const char *what, bool got, bool want) {
    if (got != want) {
        printf("%s=FAIL (got %d, want %d)\n", what, (int)got, (int)want);
        failures++;
    } else {
        printf("%s=PASS\n", what);
    }
}

int main(void) {
    const CATransform3D identity = CATransform3DIdentity;

    CATransform3D translate = CATransform3DMakeTranslation(2, 3, 4);
    CATransform3D wantTranslate = {1,0,0,0, 0,1,0,0, 0,0,1,0, 2,3,4,1};
    eq("translation", translate, wantTranslate);

    CATransform3D scale = CATransform3DMakeScale(2, 3, 4);
    CATransform3D wantScale = {2,0,0,0, 0,3,0,0, 0,0,4,0, 0,0,0,1};
    eq("scale", scale, wantScale);

    // A positive angle about +z sends (1,0,0) to (0,1,0), so m11,m12,m21,m22
    // are cos,sin,-sin,cos as in CGAffineTransformMakeRotation.
    CATransform3D wantRotateZ = {0,1,0,0, -1,0,0,0, 0,0,1,0, 0,0,0,1};
    eq("rotation about z", CATransform3DMakeRotation(M_PI/2, 0, 0, 1), wantRotateZ);
    eq("rotation about x", CATransform3DMakeRotation(M_PI/2, 1, 0, 0),
       (CATransform3D){1,0,0,0, 0,0,1,0, 0,-1,0,0, 0,0,0,1});
    // +y is the axis whose sign pattern is easiest to transpose, so check it
    // explicitly: a positive quarter turn about +y sends (0,0,1) to (1,0,0).
    eq("rotation about y", CATransform3DMakeRotation(M_PI/2, 0, 1, 0),
       (CATransform3D){0,0,-1,0, 0,1,0,0, 1,0,0,0, 0,0,0,1});
    eq("rotation axis normalised", CATransform3DMakeRotation(M_PI/2, 0, 0, 5), wantRotateZ);
    eq("rotation about zero axis", CATransform3DMakeRotation(M_PI/2, 0, 0, 0), identity);

    // Concat(a, b) is a * b, so a applies first: scaling then translating
    // leaves the translation unscaled, and the reverse order scales it.
    eq("concat scale then translate", CATransform3DConcat(scale, translate),
       (CATransform3D){2,0,0,0, 0,3,0,0, 0,0,4,0, 2,3,4,1});
    eq("concat translate then scale", CATransform3DConcat(translate, scale),
       (CATransform3D){2,0,0,0, 0,3,0,0, 0,0,4,0, 4,9,16,1});

    CATransform3D composite = CATransform3DConcat(CATransform3DConcat(scale, wantRotateZ), translate);
    eq("composite times its inverse",
       CATransform3DConcat(composite, CATransform3DInvert(composite)), identity);
    eq("inverse of a translation", CATransform3DInvert(translate),
       CATransform3DMakeTranslation(-2, -3, -4));

    // A matrix with no inverse comes back unchanged rather than as infinities.
    CATransform3D singular = CATransform3DMakeScale(1, 1, 0);
    eq("inverse of a singular matrix", CATransform3DInvert(singular), singular);

    eqbool("identity is identity", CATransform3DIsIdentity(identity), true);
    eqbool("translation is not identity", CATransform3DIsIdentity(translate), false);
    eqbool("zero translation is identity",
           CATransform3DIsIdentity(CATransform3DMakeTranslation(0, 0, 0)), true);
    eqbool("unit scale is identity",
           CATransform3DIsIdentity(CATransform3DMakeScale(1, 1, 1)), true);

    // The composition helpers apply their operation before t: translating
    // (0,0,0) by (2,3,4) and then scaling by (2,3,4) lands at (4,9,16), while
    // scaling first leaves the later translation unscaled.
    eq("translate composes before t", CATransform3DTranslate(scale, 2, 3, 4),
       (CATransform3D){2,0,0,0, 0,3,0,0, 0,0,4,0, 4,9,16,1});
    eq("scale composes before t", CATransform3DScale(translate, 2, 3, 4),
       (CATransform3D){2,0,0,0, 0,3,0,0, 0,0,4,0, 2,3,4,1});
    eq("rotate composes before t",
       CATransform3DRotate(translate, M_PI/2, 0, 0, 1),
       (CATransform3D){0,1,0,0, -1,0,0,0, 0,0,1,0, 2,3,4,1});

    // Applying an operation to the identity must equal the Make* form.
    eq("translate on identity", CATransform3DTranslate(identity, 2, 3, 4), wantTranslate);
    eq("scale on identity", CATransform3DScale(identity, 2, 3, 4), wantScale);
    eq("rotate on identity", CATransform3DRotate(identity, M_PI/2, 0, 0, 1), wantRotateZ);

    // A 2D affine lifts into the 3D matrix leaving z alone.
    CGAffineTransform affine = {2, 3, 4, 5, 6, 7};
    eq("affine lifted into 3D", CATransform3DMakeAffineTransform(affine),
       (CATransform3D){2,3,0,0, 4,5,0,0, 0,0,1,0, 6,7,0,1});

    eqbool("transform equals itself", CATransform3DEqualToTransform(scale, scale), true);
    eqbool("different transforms are unequal",
           CATransform3DEqualToTransform(scale, translate), false);

    printf("catransform3d failures=%d\n", failures);
    return failures != 0;
}
