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

#import <CoreFoundation/CFBase.h>
#import <CoreFoundation/CFDictionary.h>
#import <CoreGraphics/CoreGraphicsExport.h>
#include <stdbool.h>

#include <CoreGraphics/CGBase.h>

struct CGPoint {
    CGFloat x;
    CGFloat y;
};
typedef struct CGPoint CGPoint;

struct CGSize {
    CGFloat width;
    CGFloat height;
};
typedef struct CGSize CGSize;

#define CGVECTOR_DEFINED 1

struct CGVector {
    CGFloat dx;
    CGFloat dy;
};
typedef struct CGVector CGVector;

struct CGRect {
    CGPoint origin;
    CGSize size;
};
typedef struct CGRect CGRect;

typedef CF_ENUM(uint32_t, CGRectEdge) {
    CGRectMinXEdge,
    CGRectMinYEdge,
    CGRectMaxXEdge,
    CGRectMaxYEdge
};

COREGRAPHICS_EXPORT const CGRect CGRectZero;
COREGRAPHICS_EXPORT const CGRect CGRectNull;
COREGRAPHICS_EXPORT const CGPoint CGPointZero;
COREGRAPHICS_EXPORT const CGSize CGSizeZero;
COREGRAPHICS_EXPORT const CGRect CGRectInfinite;

static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat width,
                                CGFloat height) {
    CGRect result = {{x, y}, {width, height}};
    return result;
}

static inline CGPoint CGPointMake(CGFloat x, CGFloat y) {
    CGPoint result = {x, y};
    return result;
}

static inline CGSize CGSizeMake(CGFloat x, CGFloat y) {
    CGSize result = {x, y};
    return result;
}

COREGRAPHICS_EXPORT bool CGSizeEqualToSize(CGSize a, CGSize b);

COREGRAPHICS_EXPORT CGFloat CGRectGetMinX(CGRect rect);

COREGRAPHICS_EXPORT CGFloat CGRectGetMaxX(CGRect rect);

COREGRAPHICS_EXPORT CGFloat CGRectGetMidX(CGRect rect);

COREGRAPHICS_EXPORT CGFloat CGRectGetMinY(CGRect rect);

COREGRAPHICS_EXPORT CGFloat CGRectGetMaxY(CGRect rect);

COREGRAPHICS_EXPORT CGFloat CGRectGetMidY(CGRect rect);

COREGRAPHICS_EXPORT CGFloat CGRectGetWidth(CGRect rect);

COREGRAPHICS_EXPORT CGFloat CGRectGetHeight(CGRect rect);

COREGRAPHICS_EXPORT bool CGRectContainsPoint(CGRect rect, CGPoint point);

COREGRAPHICS_EXPORT bool CGPointEqualToPoint(CGPoint a, CGPoint b);

COREGRAPHICS_EXPORT CGRect CGRectInset(CGRect rect, CGFloat dx, CGFloat dy);

COREGRAPHICS_EXPORT CGRect CGRectOffset(CGRect rect, CGFloat dx, CGFloat dy);

COREGRAPHICS_EXPORT bool CGRectIsEmpty(CGRect rect);

COREGRAPHICS_EXPORT bool CGRectIntersectsRect(CGRect a, CGRect b);

COREGRAPHICS_EXPORT bool CGRectEqualToRect(CGRect a, CGRect b);

COREGRAPHICS_EXPORT bool CGRectIsInfinite(CGRect rect);

COREGRAPHICS_EXPORT bool CGRectIsNull(CGRect rect);

COREGRAPHICS_EXPORT CGRect CGRectUnion(CGRect a, CGRect b);
COREGRAPHICS_EXPORT CGRect CGRectIntersection(CGRect a, CGRect b);
COREGRAPHICS_EXPORT CGRect CGRectIntegral(CGRect rect);

COREGRAPHICS_EXPORT bool CGRectContainsRect(CGRect a, CGRect b);

CFDictionaryRef CGPointCreateDictionaryRepresentation(CGPoint point);
bool CGPointMakeWithDictionaryRepresentation(CFDictionaryRef dict,
                                             CGPoint *point);

CFDictionaryRef CGSizeCreateDictionaryRepresentation(CGSize size);
bool CGSizetMakeWithDictionaryRepresentation(CFDictionaryRef dict,
                                             CGSize *size);

CFDictionaryRef CGRectCreateDictionaryRepresentation(CGRect rect);
bool CGRectMakeWithDictionaryRepresentation(CFDictionaryRef dict, CGRect *rect);
