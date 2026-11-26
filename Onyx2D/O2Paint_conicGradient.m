/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <Onyx2D/O2Paint_conicGradient.h>
#import <Onyx2D/O2Shading.h>

@implementation O2Paint_conicGradient

// The position along the function, 0 to 1, of the pixel centre (x, y). The
// sweep goes counterclockwise in user space from the start angle and wraps
// back to 0 after a full turn.
ONYX2D_STATIC_INLINE O2Float conicPosition(O2Paint_conicGradient *self, int x,
                                           int y)
{
    O2Point point = O2PointApplyAffineTransform(O2PointMake(x + 0.5f, y + 0.5f),
                                                self->m_surfaceToPaintMatrix);
    O2Float dx = point.x - self->_startPoint.x;
    O2Float dy = point.y - self->_startPoint.y;
    O2Float turns = (atan2(dy, dx) - self->_angle) / (2 * M_PI);

    turns -= floor(turns);
    // Rounding can leave exactly 1 for a point just before the start angle.
    if (turns >= 1)
        turns = 0;
    return turns;
}

ONYX2D_STATIC int conic_span_largb8u_PRE(O2Paint *selfX, int x, int y,
                                         O2argb8u *span, int length)
{
    O2Paint_conicGradient *self = (O2Paint_conicGradient *) selfX;
    int i;

    for (i = 0; i < length; i++, x++) {
        int skip = 0;
        O2argb32f value =
                O2PaintColorRamp(self, conicPosition(self, x, y), 0, &skip);

        span[i] = O2argb8uFromO2argb32f(value);
    }
    return length;
}

ONYX2D_STATIC int conic_span_largb32f_PRE(O2Paint *selfX, int x, int y,
                                          O2argb32f *span, int length)
{
    O2Paint_conicGradient *self = (O2Paint_conicGradient *) selfX;
    int i;

    for (i = 0; i < length; i++, x++) {
        int skip = 0;

        span[i] = O2PaintColorRamp(self, conicPosition(self, x, y), 0, &skip);
    }
    return length;
}

- initWithShading: (O2Shading *) shading
        deviceTransform: (O2AffineTransform) deviceTransform
{
    if ([super initWithShading: shading
                deviceTransform: deviceTransform
                numberOfSamples: 1024] == nil)
        return nil;
    _paint_largb8u_PRE = conic_span_largb8u_PRE;
    _paint_largb32f_PRE = conic_span_largb32f_PRE;
    _angle = [shading angle];

    return self;
}

@end
