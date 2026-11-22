// Copyright (C) 2026 Lubos Dolezel
//
// CGContextGetClipBoundingBox on a bitmap context. Documented contract
// (https://developer.apple.com/documentation/coregraphics/cgcontext/boundingboxofclippath): the bounding box
// of the clipping path is the smallest rectangle that holds all points of the path, control points of Bezier
// curves included; the rectangle is in user space, so it follows the current transformation. The cases the
// documentation does not cover are pinned to what was observed on macOS 26.7.3 and Mac OS X 10.14.4 (identical;
// 100 x 80 bitmap context): no clip gives the context bounds, an empty intersection or a zero-size rectangle
// gives CGRectNull, a clip larger than the context gives the context bounds, a mask clip gives the intersection
// with the mask's rectangle, several rectangle subpaths give the box of their union, an even-odd hole does not
// change the box, ClipToRects intersects with the box of the rectangles, and under a 45 degree rotation the box
// is that, in user space, of the clip's rectangle in device space. Needs no window server.
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

    // observed: no clip is the context bounds
    box = CGContextGetClipBoundingBox(c);
    CHECK(same(box, 0, 0, 100, 80));

    // observed: a clip larger than the context is cut to the context
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(-10, -10, 200, 200));
    CHECK(same(CGContextGetClipBoundingBox(c), 0, 0, 100, 80));
    CGContextRestoreGState(c);

    // observed: disjoint clips and a zero-size rectangle give CGRectNull
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(0, 0, 10, 10));
    CGContextClipToRect(c, CGRectMake(50, 50, 10, 10));
    CHECK(CGRectIsNull(CGContextGetClipBoundingBox(c)));
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(10, 10, 0, 0));
    CHECK(CGRectIsNull(CGContextGetClipBoundingBox(c)));
    CGContextRestoreGState(c);

    // observed: two rectangle subpaths in one clip give the box of their union
    CGContextSaveGState(c);
    CGContextAddRect(c, CGRectMake(5, 5, 10, 10));
    CGContextAddRect(c, CGRectMake(60, 50, 10, 10));
    CGContextClip(c);
    CHECK(same(CGContextGetClipBoundingBox(c), 5, 5, 65, 55));
    CGContextRestoreGState(c);

    // observed: an even-odd clip with a hole gives the outer box
    CGContextSaveGState(c);
    CGContextAddRect(c, CGRectMake(5, 5, 60, 60));
    CGContextAddRect(c, CGRectMake(20, 20, 10, 10));
    CGContextEOClip(c);
    CHECK(same(CGContextGetClipBoundingBox(c), 5, 5, 60, 60));
    CGContextRestoreGState(c);

    // observed: a rectangle and then ClipToRects: the box of the intersection with the union of the rectangles
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(20, 20, 60, 60));
    CGRect small[2] = { CGRectMake(10, 10, 20, 20), CGRectMake(50, 50, 15, 15) };
    CGContextClipToRects(c, small, 2);
    CHECK(same(CGContextGetClipBoundingBox(c), 20, 20, 45, 45));
    CGContextRestoreGState(c);

    // observed: a mask clip gives the mask's rectangle, and a rectangle after it intersects
    {
        unsigned char alpha[4] = { 255, 255, 255, 255 };
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, alpha, sizeof alpha, NULL);
        CGImageRef mask = CGImageMaskCreate(2, 2, 8, 8, 2, provider, NULL, false);
        CGDataProviderRelease(provider);
        CHECK(mask != NULL);
        if (mask != NULL) {
            CGContextSaveGState(c);
            CGContextClipToMask(c, CGRectMake(20, 20, 40, 40), mask);
            CHECK(same(CGContextGetClipBoundingBox(c), 20, 20, 40, 40));
            CGContextClipToRect(c, CGRectMake(0, 0, 30, 30));
            CHECK(same(CGContextGetClipBoundingBox(c), 20, 20, 10, 10));
            CGContextRestoreGState(c);
            CGImageRelease(mask);
        }
    }

    // observed: under a 45 degree rotation the box is that of the clip's device rectangle in user space,
    // then back in the unrotated space the box of the rotated rectangle
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, 50, 40);
    CGContextRotateCTM(c, M_PI / 4);
    CGContextClipToRect(c, CGRectMake(-10, -10, 20, 20));
    box = CGContextGetClipBoundingBox(c);
    CHECK(fabs(box.origin.x + 20) < 1e-3 && fabs(box.origin.y + 20) < 1e-3 &&
          fabs(box.size.width - 40) < 1e-3 && fabs(box.size.height - 40) < 1e-3);
    CGContextRotateCTM(c, -M_PI / 4);
    box = CGContextGetClipBoundingBox(c);
    CHECK(fabs(box.origin.x + 14.142136) < 1e-3 && fabs(box.origin.y + 14.142136) < 1e-3 &&
          fabs(box.size.width - 28.284271) < 1e-3 && fabs(box.size.height - 28.284271) < 1e-3);
    CGContextRestoreGState(c);

    CGContextRelease(c);
    printf(g_failures ? "FAIL\n" : "PASS\n");
    return g_failures != 0;
}
