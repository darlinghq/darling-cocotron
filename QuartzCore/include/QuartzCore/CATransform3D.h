
#import <QuartzCore/CABase.h>
#import <CoreGraphics/CGAffineTransform.h>

#include <stdbool.h>

typedef struct {
    CGFloat m11, m12, m13, m14;
    CGFloat m21, m22, m23, m24;
    CGFloat m31, m32, m33, m34;
    CGFloat m41, m42, m43, m44;
} CATransform3D;

CA_EXPORT const CATransform3D CATransform3DIdentity;

// CATransform3D is a row-vector matrix: a point is transformed as v' = v * M,
// so the translation lives in m41..m43 and CATransform3DConcat(a, b) applies
// a before b.

CA_EXPORT CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz);

CA_EXPORT CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz);

// Rotates by angle radians about the axis (x, y, z), which need not be a unit
// vector. A zero-length axis yields the identity.
CA_EXPORT CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z);

CA_EXPORT CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b);

// Returns the inverse of t, or t unchanged when t has no inverse.
CA_EXPORT CATransform3D CATransform3DInvert(CATransform3D t);

CA_EXPORT bool CATransform3DIsIdentity(CATransform3D t);

CA_EXPORT bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b);

// The three below apply the named operation before t.
CA_EXPORT CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz);

CA_EXPORT CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz);

CA_EXPORT CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z);

// Lifts a 2D affine transform into the 3D matrix: the 2x2 linear part goes to
// m11, m12, m21, m22 and the translation to m41, m42, leaving z untouched.
CA_EXPORT CATransform3D CATransform3DMakeAffineTransform(CGAffineTransform m);
