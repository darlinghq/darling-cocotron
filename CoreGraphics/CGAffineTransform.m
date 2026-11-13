/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreGraphics/CGAffineTransform.h>

const CGAffineTransform CGAffineTransformIdentity = {1, 0, 0, 1, 0, 0};

// Keep the header's inline helpers for source clients, but also provide the
// canonical symbols imported by prebuilt clients such as SwiftUI and CotEditor.
#undef CGPointApplyAffineTransform
#undef CGSizeApplyAffineTransform
COREGRAPHICS_EXPORT CGPoint CGPointApplyAffineTransform(
        CGPoint point, CGAffineTransform transform) {
    return __CGPointApplyAffineTransform(point, transform);
}

COREGRAPHICS_EXPORT CGSize CGSizeApplyAffineTransform(
        CGSize size, CGAffineTransform transform) {
    return __CGSizeApplyAffineTransform(size, transform);
}

bool CGAffineTransformIsIdentity(CGAffineTransform xform) {
    return xform.a == 1 && xform.b == 0 && xform.c == 0 && xform.d == 1 &&
           xform.tx == 0 && xform.ty == 0;
}

// Compares the six components with ==, so a transform containing NaN is not
// equal to itself and 0 equals -0.
bool CGAffineTransformEqualToTransform(CGAffineTransform t1,
                                       CGAffineTransform t2)
{
    return t1.a == t2.a && t1.b == t2.b && t1.c == t2.c && t1.d == t2.d &&
           t1.tx == t2.tx && t1.ty == t2.ty;
}

CGAffineTransform CGAffineTransformMakeRotation(CGFloat radians) {
    CGAffineTransform xform = {
            cos(radians), sin(radians), -sin(radians), cos(radians), 0, 0};
    return xform;
}

CGAffineTransform CGAffineTransformMakeScale(CGFloat scalex, CGFloat scaley) {
    CGAffineTransform xform = {scalex, 0, 0, scaley, 0, 0};
    return xform;
}

CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty) {
    CGAffineTransform xform = {1, 0, 0, 1, tx, ty};
    return xform;
}

CGAffineTransform CGAffineTransformConcat(CGAffineTransform xform,
                                          CGAffineTransform append)
{
    CGAffineTransform result;

    result.a = xform.a * append.a + xform.b * append.c;
    result.b = xform.a * append.b + xform.b * append.d;
    result.c = xform.c * append.a + xform.d * append.c;
    result.d = xform.c * append.b + xform.d * append.d;
    result.tx = xform.tx * append.a + xform.ty * append.c + append.tx;
    result.ty = xform.tx * append.b + xform.ty * append.d + append.ty;

    return result;
}

CGAffineTransform CGAffineTransformInvert(CGAffineTransform xform) {
    CGAffineTransform result;
    CGFloat determinant;

    determinant = xform.a * xform.d - xform.c * xform.b;
    if (determinant == 0) {
        return xform;
    }

    result.a = xform.d / determinant;
    result.b = -xform.b / determinant;
    result.c = -xform.c / determinant;
    result.d = xform.a / determinant;
    result.tx = (-xform.d * xform.tx + xform.c * xform.ty) / determinant;
    result.ty = (xform.b * xform.tx - xform.a * xform.ty) / determinant;

    return result;
}

CGAffineTransform CGAffineTransformRotate(CGAffineTransform xform,
                                          CGFloat radians)
{
    CGAffineTransform rotate = CGAffineTransformMakeRotation(radians);
    return CGAffineTransformConcat(rotate, xform);
}

CGAffineTransform CGAffineTransformScale(CGAffineTransform xform,
                                         CGFloat scalex, CGFloat scaley)
{
    CGAffineTransform scale = CGAffineTransformMakeScale(scalex, scaley);
    return CGAffineTransformConcat(scale, xform);
}

CGAffineTransform CGAffineTransformTranslate(CGAffineTransform xform,
                                             CGFloat tx, CGFloat ty)
{
    CGAffineTransform translate = CGAffineTransformMakeTranslation(tx, ty);
    return CGAffineTransformConcat(translate, xform);
}

// Transforms all four corners and returns the smallest rectangle that
// contains them, since a rotation or skew does not keep the rectangle
// axis-aligned.
CGRect CGRectApplyAffineTransform(CGRect rect, CGAffineTransform t) {
    if (CGRectIsNull(rect))
        return rect;

    CGFloat minX = 0, minY = 0, maxX = 0, maxY = 0;

    for (int i = 0; i < 4; i++) {
        CGFloat x = rect.origin.x + ((i & 1) ? rect.size.width : 0);
        CGFloat y = rect.origin.y + ((i & 2) ? rect.size.height : 0);
        CGFloat tx = t.a * x + t.c * y + t.tx;
        CGFloat ty = t.b * x + t.d * y + t.ty;

        if (i == 0 || tx < minX)
            minX = tx;
        if (i == 0 || ty < minY)
            minY = ty;
        if (i == 0 || tx > maxX)
            maxX = tx;
        if (i == 0 || ty > maxY)
            maxY = ty;
    }

    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

bool CGAffineTransformEqualToTransform(CGAffineTransform t1, CGAffineTransform t2)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);

    return true;
}
