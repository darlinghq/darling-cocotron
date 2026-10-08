#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <float.h>
#include <math.h>
#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "stroker assertion at line%d\n", __LINE__); return 20; } } while (0)

static CGPathRef stroke(CGPathRef path, CGLineCap cap, CGLineJoin join, CGFloat limit) {
    return CGPathCreateCopyByStrokingPath(path, NULL, 4, cap, join, limit);
}
static BOOL inside(CGPathRef path, CGFloat x, CGFloat y) {
    return CGPathContainsPoint(path, NULL, CGPointMake(x, y), false);
}
static BOOL bounds(CGPathRef path, CGRect expected) {
    CGRect box = CGPathGetBoundingBox(path);
    return fabs(box.origin.x - expected.origin.x) < .001 &&
           fabs(box.origin.y - expected.origin.y) < .001 &&
           fabs(box.size.width - expected.size.width) < .001 &&
           fabs(box.size.height - expected.size.height) < .001;
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    CGMutablePathRef line = CGPathCreateMutable();
    CGPathMoveToPoint(line, NULL, 0, 0);
    CGPathAddLineToPoint(line, NULL, 10, 0);
    CGPathRef snapshot = CGPathCreateCopy(line);
    for (int cap = 0; cap < 3; cap++) {
        CGPathRef copy = stroke(line, cap, kCGLineJoinMiter, 10);
        if (copy == NULL) { fputs("stroker returned NULL\n", stderr); return 10; }
        CHECK(bounds(copy, CGRectMake(cap ? -2 : 0, -2, cap ? 14 : 10, 4)));
        CHECK(inside(copy, 5, 1) && !inside(copy, 5, 3));
        CHECK(inside(copy, -1.5, 0) == (cap != kCGLineCapButt));
        CHECK(inside(copy, -1.8, 1.8) == (cap == kCGLineCapSquare));
        CHECK(CGPathEqualToPath(line, snapshot));
        CGPathRelease(copy);
    }
    CGAffineTransform transform = CGAffineTransformMake(2, 0, 0, 3, 5, 7);
    CGPathRef copy = CGPathCreateCopyByStrokingPath(line, &transform, 4,
        kCGLineCapButt, kCGLineJoinMiter, 10);
    CHECK(copy && bounds(copy, CGRectMake(5, 1, 20, 12)) && inside(copy, 6, 2));
    CGPathRelease(copy);
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    CGMutablePathRef temporary = CGPathCreateMutableCopy(line);
    copy = stroke(temporary, kCGLineCapButt, kCGLineJoinMiter, 10);
    CGPathAddLineToPoint(temporary, NULL, 50, 0); CGPathRelease(temporary);
    [inner drain];
    CHECK(copy && bounds(copy, CGRectMake(0, -2, 10, 4)) && inside(copy, 5, 1));
    CHECK(!inside(copy, 30, 0)); CGPathRelease(copy);
    CGMutablePathRef corner = CGPathCreateMutable();
    CGPathMoveToPoint(corner, NULL, 0, 0); CGPathAddLineToPoint(corner, NULL, 10, 0);
    CGPathAddLineToPoint(corner, NULL, 10, 10);
    for (int join = 0; join < 3; join++) {
        copy = stroke(corner, kCGLineCapButt, join, 10);
        CHECK(copy && inside(copy, 11.5, -1.5) == (join == kCGLineJoinMiter));
        CHECK(inside(copy, 11.2, -1.2) == (join != kCGLineJoinBevel));
        CGPathRelease(copy);
    }
    copy = stroke(corner, kCGLineCapButt, kCGLineJoinMiter, 1);
    CHECK(copy && !inside(copy, 11.2, -1.2)); CGPathRelease(copy);
    CGPathRelease(corner);
    CGMutablePathRef rectangle = CGPathCreateMutable();
    CGPathAddRect(rectangle, NULL, CGRectMake(0, 0, 10, 10));
    copy = stroke(rectangle, kCGLineCapButt, kCGLineJoinMiter, 10);
    CGPathRef once = stroke(rectangle, kCGLineCapRound, kCGLineJoinBevel, 10);
    CGPathCloseSubpath(rectangle);
    CGPathRef twice = stroke(rectangle, kCGLineCapRound, kCGLineJoinBevel, 10);
    CHECK(once && twice && CGPathEqualToPath(once, twice));
    CGPathRelease(once); CGPathRelease(twice);
    CGPathRelease(rectangle);
    CHECK(copy && bounds(copy, CGRectMake(-2, -2, 14, 14)));
    CHECK(inside(copy, -.5, 5) && !inside(copy, 5, 5)); CGPathRelease(copy);
    for (int cubic = 0; cubic < 2; cubic++) {
        CGMutablePathRef curve = CGPathCreateMutable(); CGPathMoveToPoint(curve, NULL, 0, 0);
        if (cubic) CGPathAddCurveToPoint(curve, NULL, 0, 20, 20, 20, 20, 0);
        else CGPathAddQuadCurveToPoint(curve, NULL, 10, 20, 20, 0);
        copy = stroke(curve, kCGLineCapRound, kCGLineJoinRound, 10);
        CHECK(copy && inside(copy, 10, cubic ? 15 : 10) && !inside(copy, 10, 5));
        CGPathRelease(curve); CGPathRelease(copy);
    }
    CGPathMoveToPoint(line, NULL, 30, 0); CGPathAddLineToPoint(line, NULL, 40, 0);
    copy = stroke(line, kCGLineCapButt, kCGLineJoinMiter, 10);
    CHECK(copy && inside(copy, 5, 0) && inside(copy, 35, 0) && !inside(copy, 20, 0));
    CGPathRelease(copy);
    CGMutablePathRef point = CGPathCreateMutable();
    copy = stroke(point, kCGLineCapRound, kCGLineJoinRound, 10);
    CHECK(copy && CGPathIsEmpty(copy)); CGPathRelease(copy);
    CGPathMoveToPoint(point, NULL, 5, 5);
    copy = stroke(point, kCGLineCapRound, kCGLineJoinRound, 10);
    CHECK(copy && CGPathIsEmpty(copy)); CGPathRelease(copy);
    CGPathAddLineToPoint(point, NULL, 5, 5);
    for (int cap = 0; cap < 3; cap++) {
        copy = stroke(point, cap, kCGLineJoinRound, 10);
        CHECK(copy && CGPathIsEmpty(copy) == (cap != kCGLineCapRound));
        if (cap == kCGLineCapRound) CHECK(bounds(copy, CGRectMake(3, 3, 4, 4)) && inside(copy, 5, 5));
        CGPathRelease(copy);
    }
    CGPathRelease(point); point = CGPathCreateMutable();
    CGPathMoveToPoint(point, NULL, 5, 5); CGPathCloseSubpath(point);
    copy = stroke(point, kCGLineCapRound, kCGLineJoinRound, 10);
    CHECK(copy && inside(copy, 5, 5)); CGPathRelease(copy);
    transform.a = DBL_MAX;
    CHECK(CGPathCreateCopyByStrokingPath(point, &transform, 4, 1, 1, 10) == NULL);
    CGPathRelease(point); point = CGPathCreateMutable();
    CGPathMoveToPoint(point, NULL, 0, 0); CGPathAddLineToPoint(point, NULL, .000001, 0);
    CHECK(stroke(point, 0, 0, 10) == NULL);
    CGPathRelease(point); point = CGPathCreateMutable();
    CGPathMoveToPoint(point, NULL, 0, 0); CGPathAddLineToPoint(point, NULL, 10, 0);
    CGPathMoveToPoint(point, NULL, 5, 0); CGPathAddLineToPoint(point, NULL, 5, 0);
    copy = stroke(point, kCGLineCapRound, kCGLineJoinRound, 10);
    CHECK(copy && inside(copy, 5, 0)); CGPathRelease(copy);
    CGPathMoveToPoint(point, NULL, 5, -5); CGPathAddLineToPoint(point, NULL, 5, 5);
    copy = stroke(point, kCGLineCapRound, kCGLineJoinRound, 10);
    CHECK(copy && inside(copy, 5, 0) && inside(copy, 5, 4)); CGPathRelease(copy);
    CGPathRelease(point); point = CGPathCreateMutable();
    CGPathMoveToPoint(point, NULL, 10, 0); CGPathAddLineToPoint(point, NULL, 0, 0);
    CGPathMoveToPoint(point, NULL, 5, 0); CGPathAddLineToPoint(point, NULL, 5, 0);
    copy = stroke(point, kCGLineCapRound, kCGLineJoinRound, 10);
    CHECK(copy && inside(copy, 5, 0)); CGPathRelease(copy); CGPathRelease(point);
    for (int reverse = 0; reverse < 2; reverse++) {
        point = CGPathCreateMutable(); CGPathMoveToPoint(point, NULL, 0, 0);
        CGPathAddLineToPoint(point, NULL, reverse ? 0 : 10, reverse ? 10 : 0);
        CGPathAddLineToPoint(point, NULL, 10, 10);
        CGPathAddLineToPoint(point, NULL, reverse ? 10 : 0, reverse ? 0 : 10);
        CGPathCloseSubpath(point); CGPathMoveToPoint(point, NULL, 0, 5);
        CGPathAddLineToPoint(point, NULL, 0, 5);
        copy = stroke(point, kCGLineCapRound, kCGLineJoinBevel, 10);
        CHECK(copy && inside(copy, 0, 5)); CGPathRelease(copy); CGPathRelease(point);
    }
    point = CGPathCreateMutable();
    CGPathMoveToPoint(point, NULL, NAN, 0);
    CHECK(stroke(point, 0, 0, 10) == NULL); CGPathRelease(point);
    CHECK(CGPathCreateCopyByStrokingPath(line, NULL, 0, 0, 0, 10) == NULL);
    CHECK(CGPathCreateCopyByStrokingPath(line, NULL, NAN, 0, 0, 10) == NULL);
    CHECK(stroke(line, -1, 0, 10) == NULL && stroke(line, 0, 3, 10) == NULL);
    CHECK(stroke(line, 0, 0, .5) == NULL && stroke(line, 0, 0, nextafter(32768, 0)) == NULL);
    CHECK(CGPathCreateCopyByStrokingPath(line, NULL, .000001, 0, 0, 10) == NULL);
    transform.a = DBL_MAX;
    CHECK(CGPathCreateCopyByStrokingPath(line, &transform, 4, 0, 0, 10) == NULL);
    CGPathAddLineToPoint(line, NULL, 2000000, 0);
    CHECK(stroke(line, 0, 0, 10) == NULL);
    CGPathRelease(line); CGPathRelease(snapshot);
    [pool drain]; puts("stroked contours, caps, joins, curves, transforms and limits passed");
    return 0;
}
