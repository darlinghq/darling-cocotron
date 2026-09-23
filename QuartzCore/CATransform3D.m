#import <QuartzCore/CATransform3D.h>

#include <math.h>
#include <string.h>

const CATransform3D CATransform3DIdentity = {1, 0, 0, 0, 0, 1, 0, 0,
                                             0, 0, 1, 0, 0, 0, 0, 1};

// The struct is sixteen CGFloats in row-major order with no room for padding,
// so it can be viewed as a 4x4 array where element [i][j] is m(i+1)(j+1).
_Static_assert(sizeof(CATransform3D) == 16 * sizeof(CGFloat),
               "CATransform3D must be 16 packed CGFloats");

static void unpack(CATransform3D t, CGFloat m[4][4]) {
    memcpy(m, &t, sizeof(t));
}

static CATransform3D pack(const CGFloat m[4][4]) {
    CATransform3D t;
    memcpy(&t, m, sizeof(t));
    return t;
}

CATransform3D CATransform3DMakeTranslation(CGFloat tx, CGFloat ty, CGFloat tz) {
    CATransform3D t = CATransform3DIdentity;

    t.m41 = tx;
    t.m42 = ty;
    t.m43 = tz;

    return t;
}

CATransform3D CATransform3DMakeScale(CGFloat sx, CGFloat sy, CGFloat sz) {
    CATransform3D t = CATransform3DIdentity;

    t.m11 = sx;
    t.m22 = sy;
    t.m33 = sz;

    return t;
}

CATransform3D CATransform3DMakeRotation(CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
    CGFloat length = sqrt(x * x + y * y + z * z);

    if (length == 0)
        return CATransform3DIdentity;

    x /= length;
    y /= length;
    z /= length;

    CGFloat c = cos(angle), s = sin(angle), t = 1 - c;

    // Axis-angle rotation, transposed for the row-vector convention so that a
    // positive angle about +z sends (1, 0, 0) to (0, 1, 0), matching
    // CGAffineTransformMakeRotation in m11, m12, m21, m22.
    CATransform3D r = CATransform3DIdentity;

    r.m11 = c + x * x * t;
    r.m12 = x * y * t + z * s;
    r.m13 = x * z * t - y * s;

    r.m21 = y * x * t - z * s;
    r.m22 = c + y * y * t;
    r.m23 = y * z * t + x * s;

    r.m31 = z * x * t + y * s;
    r.m32 = z * y * t - x * s;
    r.m33 = c + z * z * t;

    return r;
}

CATransform3D CATransform3DConcat(CATransform3D a, CATransform3D b) {
    CGFloat l[4][4], r[4][4], p[4][4];

    unpack(a, l);
    unpack(b, r);

    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            p[i][j] = l[i][0] * r[0][j] + l[i][1] * r[1][j] +
                      l[i][2] * r[2][j] + l[i][3] * r[3][j];

    return pack(p);
}

CATransform3D CATransform3DInvert(CATransform3D t) {
    CGFloat m[4][4], r[4][4];

    unpack(t, m);

    // Cofactor expansion by complementary 2x2 minors: s* come from the top two
    // rows, c* from the bottom two.
    CGFloat s0 = m[0][0] * m[1][1] - m[1][0] * m[0][1];
    CGFloat s1 = m[0][0] * m[1][2] - m[1][0] * m[0][2];
    CGFloat s2 = m[0][0] * m[1][3] - m[1][0] * m[0][3];
    CGFloat s3 = m[0][1] * m[1][2] - m[1][1] * m[0][2];
    CGFloat s4 = m[0][1] * m[1][3] - m[1][1] * m[0][3];
    CGFloat s5 = m[0][2] * m[1][3] - m[1][2] * m[0][3];

    CGFloat c5 = m[2][2] * m[3][3] - m[3][2] * m[2][3];
    CGFloat c4 = m[2][1] * m[3][3] - m[3][1] * m[2][3];
    CGFloat c3 = m[2][1] * m[3][2] - m[3][1] * m[2][2];
    CGFloat c2 = m[2][0] * m[3][3] - m[3][0] * m[2][3];
    CGFloat c1 = m[2][0] * m[3][2] - m[3][0] * m[2][2];
    CGFloat c0 = m[2][0] * m[3][1] - m[3][0] * m[2][1];

    CGFloat det = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0;

    // A singular matrix has no inverse; Apple returns the argument unchanged.
    // The test is exact: a merely ill-conditioned matrix still inverts, and
    // picking a tolerance here would reject matrices Apple accepts.
    if (det == 0)
        return t;

    CGFloat d = 1 / det;

    r[0][0] = ( m[1][1] * c5 - m[1][2] * c4 + m[1][3] * c3) * d;
    r[0][1] = (-m[0][1] * c5 + m[0][2] * c4 - m[0][3] * c3) * d;
    r[0][2] = ( m[3][1] * s5 - m[3][2] * s4 + m[3][3] * s3) * d;
    r[0][3] = (-m[2][1] * s5 + m[2][2] * s4 - m[2][3] * s3) * d;

    r[1][0] = (-m[1][0] * c5 + m[1][2] * c2 - m[1][3] * c1) * d;
    r[1][1] = ( m[0][0] * c5 - m[0][2] * c2 + m[0][3] * c1) * d;
    r[1][2] = (-m[3][0] * s5 + m[3][2] * s2 - m[3][3] * s1) * d;
    r[1][3] = ( m[2][0] * s5 - m[2][2] * s2 + m[2][3] * s1) * d;

    r[2][0] = ( m[1][0] * c4 - m[1][1] * c2 + m[1][3] * c0) * d;
    r[2][1] = (-m[0][0] * c4 + m[0][1] * c2 - m[0][3] * c0) * d;
    r[2][2] = ( m[3][0] * s4 - m[3][1] * s2 + m[3][3] * s0) * d;
    r[2][3] = (-m[2][0] * s4 + m[2][1] * s2 - m[2][3] * s0) * d;

    r[3][0] = (-m[1][0] * c3 + m[1][1] * c1 - m[1][2] * c0) * d;
    r[3][1] = ( m[0][0] * c3 - m[0][1] * c1 + m[0][2] * c0) * d;
    r[3][2] = (-m[3][0] * s3 + m[3][1] * s1 - m[3][2] * s0) * d;
    r[3][3] = ( m[2][0] * s3 - m[2][1] * s1 + m[2][2] * s0) * d;

    return pack(r);
}

bool CATransform3DEqualToTransform(CATransform3D a, CATransform3D b) {
    CGFloat l[4][4], r[4][4];

    unpack(a, l);
    unpack(b, r);

    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            if (l[i][j] != r[i][j])
                return false;

    return true;
}

bool CATransform3DIsIdentity(CATransform3D t) {
    return CATransform3DEqualToTransform(t, CATransform3DIdentity);
}

CATransform3D CATransform3DTranslate(CATransform3D t, CGFloat tx, CGFloat ty, CGFloat tz) {
    return CATransform3DConcat(CATransform3DMakeTranslation(tx, ty, tz), t);
}

CATransform3D CATransform3DScale(CATransform3D t, CGFloat sx, CGFloat sy, CGFloat sz) {
    return CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), t);
}

CATransform3D CATransform3DRotate(CATransform3D t, CGFloat angle, CGFloat x, CGFloat y, CGFloat z) {
    return CATransform3DConcat(CATransform3DMakeRotation(angle, x, y, z), t);
}

CATransform3D CATransform3DMakeAffineTransform(CGAffineTransform m) {
    CATransform3D t = CATransform3DIdentity;

    t.m11 = m.a;
    t.m12 = m.b;
    t.m21 = m.c;
    t.m22 = m.d;
    t.m41 = m.tx;
    t.m42 = m.ty;

    return t;
}

@implementation NSValue (CATransform3DAdditions)

+ (NSValue *) valueWithCATransform3D: (CATransform3D) t {
    return [self valueWithBytes: &t objCType: @encode(CATransform3D)];
}

- (CATransform3D) CATransform3DValue {
    if (strcmp([self objCType], @encode(CATransform3D)) != 0)
        [NSException raise: NSInvalidArgumentException
                    format: @"NSValue of type %s does not hold a CATransform3D", [self objCType]];
    CATransform3D t;
    [self getValue: &t];
    return t;
}

@end
