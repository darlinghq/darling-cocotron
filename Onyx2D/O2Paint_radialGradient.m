/*------------------------------------------------------------------------
 *
 * Derivative of the OpenVG 1.0.1 Reference Implementation
 * -------------------------------------
 *
 * Copyright (c) 2007 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and /or associated documentation files
 * (the "Materials "), to deal in the Materials without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Materials,
 * and to permit persons to whom the Materials are furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Materials.
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE MATERIALS OR
 * THE USE OR OTHER DEALINGS IN THE MATERIALS.
 *
 *-------------------------------------------------------------------*/
#import <Onyx2D/O2Paint_radialGradient.h>
#import <Onyx2D/O2Shading.h>

@implementation O2Paint_radialGradient

ONYX2D_STATIC_INLINE void quadratic(O2Float a, O2Float hb, O2Float c,
                                    O2Float *x1, O2Float *x2) {
    // Solve a*x*x + 2*hb*x + c = 0 numerically, trying not to lose precision
    // for cases when a is close to 0.
    O2Float qD = hb * hb - a * c;
    O2Float d = (O2Float) sqrt(qD);
    *x1 = c / (-hb + d);
    *x2 = c / (-hb - d);
}

void O2PaintRadialGradient(O2Paint_radialGradient *self, O2Float *g,
                           O2Float *rho, O2Float x, O2Float y) {
    RI_ASSERT(self);
    if (self->_endRadius <= 0.0f) {
        *g = 1.0f;
        *rho = 0.0f;
        return;
    }

    O2Point gx = O2PointMake(self->m_surfaceToPaintMatrix.a,
                             self->m_surfaceToPaintMatrix.b);
    O2Point gy = O2PointMake(self->m_surfaceToPaintMatrix.c,
                             self->m_surfaceToPaintMatrix.d);

    O2Float r = self->_endRadius;
    O2Float R = self->_startRadius;

    O2Point O = self->_endPoint;

    O2Point p = O2PointMake(x, y);
    p = Vector2Subtract(
        O2PointApplyAffineTransform(p, self->m_surfaceToPaintMatrix), O);

    O2Point f = self->_startPoint;
    f = Vector2Subtract(f, O);

    O2Point d = Vector2Subtract(p, f);
    O2Float dd = Vector2Dot(d, d);
    O2Float df = Vector2Dot(d, f);
    O2Float ff = Vector2Dot(f, f);

    O2Float a = ff - r * r - R * R + 2 * r * R;
    O2Float hb = df + R * R - R * r;
    O2Float c = dd - R * R;

    *rho = 0.01; // TODO: something smarter

    O2Float g_inside, g_outside;
    quadratic(a, hb, c, &g_inside, &g_outside);

    BOOL outsideVisible = (self->_extendStart || 0.0 <= g_outside - *rho) &&
                          (self->_extendEnd || g_outside + *rho <= 1.0) &&
                          (a >= 0.0 || R > r);
    *g = outsideVisible ? g_outside : g_inside;

    O2Float resultingRadius = (R * (1 - *g)) + (*g * r);
    if (resultingRadius < 0.0) {
        *g = NAN;
    }
}

ONYX2D_STATIC_INLINE O2argb32f
radialGradientColorAt(O2Paint_radialGradient *self, int x, int y, int *skip) {
    O2argb32f result;

    O2Float g, rho;
    O2PaintRadialGradient(self, &g, &rho, x + 0.5f, y + 0.5f);

    result = O2PaintColorRamp(self, g, rho, skip);

    return result;
}

ONYX2D_STATIC int radial_span_largb8u_PRE(O2Paint *selfX, int x, int y,
                                          O2argb8u *span, int length) {
    O2Paint_radialGradient *self = (O2Paint_radialGradient *) selfX;
    int i;
    int previous = -1;

    for (i = 0; i < length; i++, x++) {
        int skip = 0;
        O2argb32f value = radialGradientColorAt(self, x, y, &skip);

        if (skip != previous) {
            if (previous == -1) {
                previous = skip;
            } else {
                return (previous == 1) ? -i : i;
            }
        }

        span[i] = O2argb8uFromO2argb32f(value);
    }
    return (previous == 1) ? -length : length;
}

ONYX2D_STATIC int radial_span_largb32f_PRE(O2Paint *selfX, int x, int y,
                                           O2argb32f *span, int length) {
    O2Paint_radialGradient *self = (O2Paint_radialGradient *) selfX;
    int i;
    int previous = -1;

    for (i = 0; i < length; i++, x++) {
        int skip = 0;
        O2argb32f value = radialGradientColorAt(self, x, y, &skip);

        if (skip != previous) {
            if (previous == -1) {
                previous = skip;
            } else {
                return (previous == 1) ? -i : i;
            }
        }

        span[i] = value;
    }
    return (previous == 1) ? -length : length;
}

- initWithShading: (O2Shading *) shading
    deviceTransform: (O2AffineTransform) deviceTransform {
    [super initWithShading: shading
           deviceTransform: deviceTransform
           numberOfSamples: 1024];
    _paint_largb8u_PRE = radial_span_largb8u_PRE;
    _paint_largb32f_PRE = radial_span_largb32f_PRE;
    _startRadius = [shading startRadius];
    _endRadius = [shading endRadius];

    return self;
}

@end
