/* Copyright (c) 2007 Christopher J. W. Lloyd

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

#import "CGConversions.h"
#import <CoreGraphics/CGPattern.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Onyx2D/O2Pattern.h>

CGPatternRef CGPatternRetain(CGPatternRef self) {
    return (CGPatternRef)O2PatternRetain((O2PatternRef)self);
}

void CGPatternRelease(CGPatternRef self) {
    O2PatternRelease((O2PatternRef)self);
}

CGPatternRef CGPatternCreate(void *info, CGRect bounds,
                             CGAffineTransform matrix, CGFloat xstep,
                             CGFloat ystep, CGPatternTiling tiling,
                             bool isColored,
                             const CGPatternCallbacks *callbacks)
{
    return (CGPatternRef)O2PatternCreate(info, bounds, O2AffineTransformFromCG(matrix), xstep,
                           ystep, tiling, isColored,
                           O2PatternCallbacksFromCG(callbacks));
}

void *CGPatternGetImage(CGPatternRef self) {
    return O2PatternGetImage((O2PatternRef)self);
}

CGRect CGPatternGetBounds(CGPatternRef self) {
    return O2PatternGetBounds((O2PatternRef)self);
}

CGAffineTransform CGPatternGetMatrix(CGPatternRef self) {
    return CGAffineTransformFromO2(O2PatternGetMatrix((O2PatternRef)self));
}

CGPatternTiling CGPatternGetTiling(CGPatternRef self) {
    return O2PatternGetTiling((O2PatternRef)self);
}

bool CGPatternIsColored(CGPatternRef self) {
    return O2PatternIsColored((O2PatternRef)self);
}

static void drawImagePattern(void *info, CGContextRef context) {
    CGImageRef image = info;
    CGContextDrawImage(context,
                       CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)),
                       image);
}

static void releaseImagePattern(void *info) {
    CGImageRelease((CGImageRef) info);
}

CGPatternRef CGPatternCreateWithImage2(CGImageRef image, CGAffineTransform transform,
                                       CGPatternTiling tiling)
{
    if (image == NULL || CGImageGetWidth(image) == 0 || CGImageGetHeight(image) == 0)
        return NULL;

    static const CGPatternCallbacks callbacks = {0, drawImagePattern, releaseImagePattern};
    CGFloat width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    CGPatternRef pattern = CGPatternCreate((void *) CGImageRetain(image),
                                           CGRectMake(0, 0, width, height), transform,
                                           width, height, tiling, true, &callbacks);
    if (pattern == NULL)
        CGImageRelease(image);
    return pattern;
}
