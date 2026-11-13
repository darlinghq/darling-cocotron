/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The CoreGraphics public headers must be safe to import twice, must declare
 * their enums as typed enums with the documented values, must provide the
 * cg_nullable qualifier and CGFontIndex, and must not define non-inline static
 * helpers that warn in every translation unit. The checks are compile-time
 * (_Static_assert) as far as possible, so the file also compiles unchanged
 * against Apple's SDK.
 */
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGAffineTransform.h>
#import <CoreGraphics/CGAffineTransform.h>
#import <CoreGraphics/CGPath.h>
#import <CoreGraphics/CGPath.h>
#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGImage.h>
#import <CoreGraphics/CGImage.h>
#import <CoreGraphics/CGFont.h>
#import <CoreGraphics/CGFont.h>
#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(CGLineCap) == 4 && sizeof(CGLineJoin) == 4, "line enums are 32-bit");
_Static_assert(sizeof(CGPathDrawingMode) == 4, "CGPathDrawingMode");
_Static_assert(sizeof(CGInterpolationQuality) == 4, "CGInterpolationQuality");
_Static_assert(sizeof(CGBlendMode) == 4, "CGBlendMode");
_Static_assert(sizeof(CGPathElementType) == 4, "CGPathElementType");
_Static_assert(sizeof(CGImageAlphaInfo) == 4, "CGImageAlphaInfo");
_Static_assert(sizeof(CGColorRenderingIntent) == 4, "CGColorRenderingIntent");

_Static_assert(kCGLineCapButt == 0 && kCGLineCapSquare == 2, "CGLineCap values");
_Static_assert(kCGLineJoinMiter == 0 && kCGLineJoinBevel == 2, "CGLineJoin values");
_Static_assert(kCGPathFill == 0 && kCGPathEOFillStroke == 4, "CGPathDrawingMode values");
_Static_assert(kCGInterpolationDefault == 0 && kCGInterpolationNone == 1 &&
               kCGInterpolationLow == 2 && kCGInterpolationMedium == 4 &&
               kCGInterpolationHigh == 3, "CGInterpolationQuality values");
_Static_assert(kCGBlendModeNormal == 0 && kCGBlendModeXOR == 25 &&
               kCGBlendModePlusLighter == 27, "CGBlendMode values");
_Static_assert(kCGPathElementMoveToPoint == 0 && kCGPathElementCloseSubpath == 4,
               "CGPathElementType values");
_Static_assert(kCGImageAlphaNone == 0 && kCGImageAlphaOnly == 7, "CGImageAlphaInfo values");
_Static_assert(sizeof(CGFontIndex) == 2, "CGFontIndex is unsigned short");
_Static_assert(sizeof(CGGlyph) == sizeof(CGFontIndex), "CGGlyph is a CGFontIndex");

static CGFloat scaled(const CGFloat * cg_nullable p) { return p ? *p * 2 : -1; }

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

int main(void) {
    CGFloat v = 3;
    CHECK(scaled(&v) == 6);
    CHECK(scaled(NULL) == -1);

    CGAffineTransform t = CGAffineTransformMakeTranslation(2, 3);
    CGPoint p = CGPointApplyAffineTransform(CGPointMake(1, 1), t);
    CHECK(p.x == 3 && p.y == 4);

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, 0, 0);
    CGPathAddLineToPoint(path, NULL, 4, 0);
    CGPathAddLineToPoint(path, NULL, 4, 4);
    CGPathCloseSubpath(path);
    CGRect box = CGPathGetBoundingBox(path);
    CHECK(box.size.width == 4 && box.size.height == 4);
    CGPathRelease(path);

    if (failures == 0) {
        printf("ALL PASSED\n");
        return 0;
    }
    return 1;
}
