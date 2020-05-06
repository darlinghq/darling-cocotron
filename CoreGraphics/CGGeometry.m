/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. */

#ifndef MIN
#define MIN(a, b)                                                              \
    ({                                                                         \
        __typeof__(a) _a = (a);                                                \
        __typeof__(b) _b = (b);                                                \
        (_a < _b) ? _a : _b;                                                   \
    })
#else
#warning MIN is already defined, MIN(a, b) may not behave as expected.
#endif

#ifndef MAX
#define MAX(a, b)                                                              \
    ({                                                                         \
        __typeof__(a) _a = (a);                                                \
        __typeof__(b) _b = (b);                                                \
        (_a > _b) ? _a : _b;                                                   \
    })
#else
#warning MAX is already defined, MAX(a, b) may not not behave as expected.
#endif

#import <CoreGraphics/CGGeometry.h>

const CGRect CGRectZero = {{0, 0}, {0, 0}};
const CGRect CGRectNull = {{INFINITY, INFINITY}, {0, 0}};
const CGPoint CGPointZero = {0, 0};
const CGSize CGSizeZero = {0, 0};
// Is this value the same as Apple CG?
const CGRect CGRectInfinite = {{0, 0}, {INFINITY, INFINITY}};

CGRect CGRectIntersection(CGRect rect0, CGRect rect1) {
    CGRect result;

    if (CGRectGetMaxX(rect0) <= CGRectGetMinX(rect1) ||
        CGRectGetMinX(rect0) >= CGRectGetMaxX(rect1) ||
        CGRectGetMaxY(rect0) <= CGRectGetMinY(rect1) ||
        CGRectGetMinY(rect0) >= CGRectGetMaxY(rect1)) {
        return CGRectZero;
    }

    result.origin.x = MAX(CGRectGetMinX(rect0), CGRectGetMinX(rect1));
    result.origin.y = MAX(CGRectGetMinY(rect0), CGRectGetMinY(rect1));
    result.size.width =
        MIN(CGRectGetMaxX(rect0), CGRectGetMaxX(rect1)) - result.origin.x;
    result.size.height =
        MIN(CGRectGetMaxY(rect0), CGRectGetMaxY(rect1)) - result.origin.y;

    return result;
}

CGRect CGRectIntegral(CGRect rect) {
    if (!CGRectIsEmpty(rect)) {
        CGFloat maxX = ceil(CGRectGetMaxX(rect));
        CGFloat maxY = ceil(CGRectGetMaxY(rect));
        rect.origin.x = floor(rect.origin.x);
        rect.origin.y = floor(rect.origin.y);
        rect.size.width = maxX - CGRectGetMinX(rect);
        rect.size.height = maxY - CGRectGetMinY(rect);
    }
    return rect;
}

CGRect CGRectUnion(CGRect a, CGRect b) {
    // make sure we handle null!
    if (CGRectIsNull(a)) {
        return b;
    }

    if (CGRectIsNull(b)) {
        return a;
    }

    CGFloat minX = MIN(CGRectGetMinX(a), CGRectGetMinX(b));
    CGFloat minY = MIN(CGRectGetMinY(a), CGRectGetMinY(b));
    CGFloat maxX = MAX(CGRectGetMaxX(a), CGRectGetMaxX(b));
    CGFloat maxY = MAX(CGRectGetMaxY(a), CGRectGetMaxY(b));
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

CFDictionaryRef CGPointCreateDictionaryRepresentation(CGPoint point) {
    CFDictionaryRef dict;
    CFStringRef keys[] = {CFSTR("X"), CFSTR("Y")};
    CFNumberRef values[2];

    values[0] = CFNumberCreate(NULL, kCFNumberCGFloatType, &point.x);
    values[1] = CFNumberCreate(NULL, kCFNumberCGFloatType, &point.y);

    dict = CFDictionaryCreate(
        NULL, (const void **) keys, (const void **) values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFRelease(values[0]);
    CFRelease(values[1]);

    return dict;
}

bool CGPointMakeWithDictionaryRepresentation(CFDictionaryRef dict,
                                             CGPoint *point) {
    if (!dict || !point) {
        return NO;
    }

    CFNumberRef num;

    num = (CFNumberRef) CFDictionaryGetValue(dict, CFSTR("X"));
    if (CFGetTypeID(num) != CFNumberGetTypeID()) {
        return NO;
    }

    if (!CFNumberGetValue(num, kCFNumberCGFloatType, &point->x)) {
        return NO;
    }

    num = (CFNumberRef) CFDictionaryGetValue(dict, CFSTR("Y"));
    if (CFGetTypeID(num) != CFNumberGetTypeID()) {
        return NO;
    }

    if (!CFNumberGetValue(num, kCFNumberCGFloatType, &point->y)) {
        return NO;
    }

    return YES;
}

CFDictionaryRef CGSizeCreateDictionaryRepresentation(CGSize size) {
    CFDictionaryRef dict;
    CFStringRef keys[] = {CFSTR("Width"), CFSTR("Height")};
    CFNumberRef values[2];

    values[0] = CFNumberCreate(NULL, kCFNumberCGFloatType, &size.width);
    values[1] = CFNumberCreate(NULL, kCFNumberCGFloatType, &size.height);

    dict = CFDictionaryCreate(
        NULL, (const void **) keys, (const void **) values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFRelease(values[0]);
    CFRelease(values[1]);

    return dict;
}

bool CGSizeMakeWithDictionaryRepresentation(CFDictionaryRef dict,
                                            CGSize *size) {
    if (!dict || !size) {
        return NO;
    }

    CFNumberRef num;

    num = (CFNumberRef) CFDictionaryGetValue(dict, CFSTR("Width"));
    if (CFGetTypeID(num) != CFNumberGetTypeID()) {
        return NO;
    }

    if (!CFNumberGetValue(num, kCFNumberCGFloatType, &size->width)) {
        return NO;
    }

    num = (CFNumberRef) CFDictionaryGetValue(dict, CFSTR("Height"));
    if (CFGetTypeID(num) != CFNumberGetTypeID()) {
        return NO;
    }

    if (!CFNumberGetValue(num, kCFNumberCGFloatType, &size->height)) {
        return NO;
    }

    return YES;
}

CFDictionaryRef CGRectCreateDictionaryRepresentation(CGRect rect) {
    CFDictionaryRef dict;
    CFStringRef keys[] = {CFSTR("X"), CFSTR("Y"), CFSTR("Width"),
                          CFSTR("Height")};
    CFNumberRef values[4];

    values[0] = CFNumberCreate(NULL, kCFNumberCGFloatType, &rect.origin.x);
    values[1] = CFNumberCreate(NULL, kCFNumberCGFloatType, &rect.origin.y);
    values[2] = CFNumberCreate(NULL, kCFNumberCGFloatType, &rect.size.width);
    values[3] = CFNumberCreate(NULL, kCFNumberCGFloatType, &rect.size.height);

    dict = CFDictionaryCreate(
        NULL, (const void **) keys, (const void **) values, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFRelease(values[0]);
    CFRelease(values[1]);
    CFRelease(values[2]);
    CFRelease(values[3]);

    return dict;
}

bool CGRectMakeWithDictionaryRepresentation(CFDictionaryRef dict,
                                            CGRect *rect) {
    if (!dict || !rect) {
        return NO;
    }

    if (!CGPointMakeWithDictionaryRepresentation(dict, &rect->origin)) {
        return NO;
    }
    if (!CGSizeMakeWithDictionaryRepresentation(dict, &rect->size)) {
        return NO;
    }

    return YES;
}

bool CGSizeEqualToSize(CGSize a, CGSize b) {
    return a.width == b.width && a.height == b.height;
}

CGFloat CGRectGetMinX(CGRect rect) {
    return rect.origin.x;
}

CGFloat CGRectGetMaxX(CGRect rect) {
    return rect.origin.x + rect.size.width;
}

CGFloat CGRectGetMidX(CGRect rect) {
    return CGRectGetMinX(rect) +
           ((CGRectGetMaxX(rect) - CGRectGetMinX(rect)) / 2.f);
}

CGFloat CGRectGetMinY(CGRect rect) {
    return rect.origin.y;
}

CGFloat CGRectGetMaxY(CGRect rect) {
    return rect.origin.y + rect.size.height;
}

CGFloat CGRectGetMidY(CGRect rect) {
    return CGRectGetMinY(rect) +
           ((CGRectGetMaxY(rect) - CGRectGetMinY(rect)) / 2.f);
}

CGFloat CGRectGetWidth(CGRect rect) {
    return rect.size.width;
}

CGFloat CGRectGetHeight(CGRect rect) {
    return rect.size.height;
}

bool CGRectContainsPoint(CGRect rect, CGPoint point) {
    return (point.x >= CGRectGetMinX(rect) && point.x <= CGRectGetMaxX(rect)) &&
           (point.y >= CGRectGetMinY(rect) && point.y <= CGRectGetMaxY(rect));
}

bool CGPointEqualToPoint(CGPoint a, CGPoint b) {
    return ((a.x == b.x) && (a.y == b.y)) ? TRUE : FALSE;
}

CGRect CGRectInset(CGRect rect, CGFloat dx, CGFloat dy) {
    rect.origin.x += dx;
    rect.origin.y += dy;
    rect.size.width -= dx * 2;
    rect.size.height -= dy * 2;
    return rect;
}

CGRect CGRectOffset(CGRect rect, CGFloat dx, CGFloat dy) {
    rect.origin.x += dx;
    rect.origin.y += dy;
    return rect;
}

bool CGRectIsEmpty(CGRect rect) {
    return ((rect.size.width == 0) && (rect.size.height == 0)) ? TRUE : FALSE;
}

bool CGRectIntersectsRect(CGRect a, CGRect b) {
    if (b.origin.x > a.origin.x + a.size.width) {
        return false;
    }
    if (b.origin.y > a.origin.y + a.size.height) {
        return false;
    }
    if (a.origin.x > b.origin.x + b.size.width) {
        return false;
    }
    if (a.origin.y > b.origin.y + b.size.height) {
        return false;
    }
    return true;
}

bool CGRectEqualToRect(CGRect a, CGRect b) {
    return CGPointEqualToPoint(a.origin, b.origin) &&
           CGSizeEqualToSize(a.size, b.size);
}

bool CGRectIsInfinite(CGRect rect) {
    return (isinf(rect.origin.x) || isinf(rect.origin.y) ||
            isinf(rect.size.width) || isinf(rect.size.height));
}

bool CGRectIsNull(CGRect rect) {
    return CGRectEqualToRect(rect, CGRectNull);
}

bool CGRectContainsRect(CGRect a, CGRect b) {
    return (CGRectGetMinX(b) >= CGRectGetMinX(a) &&
            CGRectGetMaxX(b) <= CGRectGetMaxX(a) &&
            CGRectGetMinY(b) >= CGRectGetMinY(a) &&
            CGRectGetMaxY(b) <= CGRectGetMaxY(a));
}
