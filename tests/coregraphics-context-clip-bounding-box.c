// Copyright (C) 2026 Lubos Dolezel
//
// CGContextGetClipBoundingBox on a bitmap context. Documented contract
// (https://developer.apple.com/documentation/coregraphics/cgcontext/boundingboxofclippath): the bounding box
// of the clipping path is the smallest rectangle that holds all points of the path, control points of Bezier
// curves included; the rectangle is in user space, so it follows the current transformation. The documentation
// does not say what the box is with no clip, with a mask clip, or when clips do not intersect, so those cases
// are not tested. Needs no window server.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

static int g_failures;
#define CHECK(condition) do { if (!(condition)) { \
    printf("FAIL line %d: %s\n", __LINE__, #condition); g_failures++; } } while (0)

static int same(CGRect rect, double x, double y, double width, double height)
{
    return fabs(rect.origin.x - x) < 1e-6 && fabs(rect.origin.y - y) < 1e-6 &&
           fabs(rect.size.width - width) < 1e-6 && fabs(rect.size.height - height) < 1e-6;
}

static CGContextRef make_context(void)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, 100, 80, 8, 400, rgb, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    return c;
}

int main(void)
{
    CGContextRef c = make_context();

    // one rectangle
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(10, 20, 30, 40));
    CGRect box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 10, 20, 30, 40));

    // user space: the same clip seen through a changed transformation
    CGContextTranslateCTM(c, 5, 5);
    box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 5, 15, 30, 40));
    CGContextScaleCTM(c, 2, 2);
    box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 2.5, 7.5, 15, 20));

    // a quarter turn maps the rectangle to a rectangle with its sides swapped
    CGContextRotateCTM(c, M_PI / 2);
    box = CGContextGetClipBoundingBox(c);
    CHECK(fabs(box.size.width - 20) < 1e-4 && fabs(box.size.height - 15) < 1e-4);
    CGContextRestoreGState(c);

    // intersection of rectangles
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(0, 0, 50, 50));
    CGContextClipToRect(c, CGRectMake(20, 10, 50, 50));
    box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 20, 10, 30, 40));
    CGContextRestoreGState(c);

    // a triangle: the box of its points
    CGContextSaveGState(c);
    CGContextMoveToPoint(c, 10, 10);
    CGContextAddLineToPoint(c, 60, 10);
    CGContextAddLineToPoint(c, 35, 50);
    CGContextClosePath(c);
    CGContextClip(c);
    box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 10, 10, 50, 40));
    // and under a translation
    CGContextTranslateCTM(c, 3, -4);
    box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 7, 14, 50, 40));
    CGContextRestoreGState(c);

    // a Bezier curve: the control points count
    CGContextSaveGState(c);
    CGContextMoveToPoint(c, 10, 10);
    CGContextAddCurveToPoint(c, 10, 70, 90, 70, 90, 10);
    CGContextClosePath(c);
    CGContextClip(c);
    box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 10, 10, 80, 60));
    CGContextRestoreGState(c);

    CGContextRelease(c);
    printf(g_failures ? "FAIL\n" : "PASS\n");
    return g_failures != 0;
}
