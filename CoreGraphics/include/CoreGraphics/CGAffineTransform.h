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

#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CoreGraphicsExport.h>

typedef struct {
    CGFloat a;
    CGFloat b;
    CGFloat c;
    CGFloat d;
    CGFloat tx;
    CGFloat ty;
} CGAffineTransform;

COREGRAPHICS_EXPORT const CGAffineTransform CGAffineTransformIdentity;

COREGRAPHICS_EXPORT bool CGAffineTransformIsIdentity(CGAffineTransform xform);

static CGAffineTransform __CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c,
                                        CGFloat d, CGFloat tx, CGFloat ty)
{
    CGAffineTransform xform = {a, b, c, d, tx, ty};
    return xform;
}
#define CGAffineTransformMake __CGAffineTransformMake

COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformMakeRotation(CGFloat radians);
COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformMakeScale(CGFloat scalex, CGFloat scaley);
COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty);

COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformConcat(CGAffineTransform xform, CGAffineTransform append);
COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformInvert(CGAffineTransform xform);

COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformRotate(CGAffineTransform xform, CGFloat radians);
COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformScale(CGAffineTransform xform, CGFloat scalex, CGFloat scaley);
COREGRAPHICS_EXPORT CGAffineTransform
CGAffineTransformTranslate(CGAffineTransform xform, CGFloat tx, CGFloat ty);

static CGPoint __CGPointApplyAffineTransform(CGPoint point, CGAffineTransform xform) {
    CGPoint p;

    p.x = xform.a * point.x + xform.c * point.y + xform.tx;
    p.y = xform.b * point.x + xform.d * point.y + xform.ty;

    return p;
}
#define CGPointApplyAffineTransform __CGPointApplyAffineTransform

static CGSize __CGSizeApplyAffineTransform(CGSize size, CGAffineTransform xform) {
    CGSize s;

    s.width = xform.a * size.width + xform.c * size.height;
    s.height = xform.b * size.width + xform.d * size.height;

    return s;
}
#define CGSizeApplyAffineTransform __CGSizeApplyAffineTransform

COREGRAPHICS_EXPORT CGRect CGRectApplyAffineTransform(CGRect rect,
                                                      CGAffineTransform t);

COREGRAPHICS_EXPORT bool
CGAffineTransformEqualToTransform(CGAffineTransform t1, CGAffineTransform t2);
