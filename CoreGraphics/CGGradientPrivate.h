/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

   Permission is hereby granted, free of charge, to any person obtaining a copy of
   this software and associated documentation files (the "Software"), to deal in
   the Software without restriction, including without limitation the rights to
   use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
   the Software, and to permit persons to whom the Software is furnished to do so,
   subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
   FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
   COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
   IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#ifndef CGGRADIENTPRIVATE_H
#define CGGRADIENTPRIVATE_H
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGGradient.h>
#import <CoreFoundation/CFRuntime.h>

/* Private to CoreGraphics: CGContext draws a gradient through a shading and needs its stops. */

/* Upper bound on components per stop, so the CGFunctionCreate range array fits on the stack. */
#define CGGradientMaximumComponents 16

struct CGGradient {
    CFRuntimeBase base;
    CGColorSpaceRef colorSpace;
    size_t count;              /* number of stops */
    size_t numberOfComponents; /* components per stop, alpha included */
    CGFloat *locations;        /* count entries, non-decreasing, within 0...1 */
    CGFloat *components;       /* count * numberOfComponents entries */
};

/* Interpolates the stops at t in 0...1; the shape CGFunctionCallbacks.evaluate needs. */
void CGGradientColorAtLocation(CGGradientRef gradient, CGFloat t,
                               CGFloat *components);

#endif /* CGGRADIENTPRIVATE_H */
