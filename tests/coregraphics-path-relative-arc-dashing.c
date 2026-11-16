// Copyright (C) 2026 Lubos Dolezel
//
// CGPathAddRelativeArc and CGPathCreateCopyByDashingPath.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); return 20; } } while (0)

typedef struct {
    int count;
    CGPathElementType type[64];
    CGPoint point[64][3];
} Recorded;

static void record(void *info, const CGPathElement *element) {
    Recorded *r = info;
    if (r->count >= 64)
        return;
    r->type[r->count] = element->type;
    int n = element->type == kCGPathElementMoveToPoint || element->type == kCGPathElementAddLineToPoint ? 1 :
            element->type == kCGPathElementAddQuadCurveToPoint ? 2 :
            element->type == kCGPathElementAddCurveToPoint ? 3 : 0;
    for (int i = 0; i < n; i++)
        r->point[r->count][i] = element->points[i];
    r->count++;
}
static void walk(CGPathRef path, Recorded *r) {
    memset(r, 0, sizeof *r);
    CGPathApply(path, r, record);
}
static int near(CGPoint p, double x, double y) {
    return fabs(p.x - x) < 0.001 && fabs(p.y - y) < 0.001;
}
// Whether the dashed result is exactly the given line pieces on the x axis (each a move and a line).
static int pieces(CGPathRef path, const double *pairs, int n) {
    Recorded r;
    walk(path, &r);
    if (r.count != 2 * n)
        return 0;
    for (int i = 0; i < n; i++) {
        if (r.type[2 * i] != kCGPathElementMoveToPoint || r.type[2 * i + 1] != kCGPathElementAddLineToPoint ||
            !near(r.point[2 * i][0], pairs[2 * i], 0) || !near(r.point[2 * i + 1][0], pairs[2 * i + 1], 0))
            return 0;
    }
    return 1;
}

// The length of a cubic, summed over a fine polyline.
static double cubicLength(CGPoint p0, CGPoint p1, CGPoint p2, CGPoint p3) {
    double length = 0;
    CGPoint previous = p0;
    for (int i = 1; i <= 2000; i++) {
        double t = i / 2000.0, u = 1 - t;
        CGPoint point = CGPointMake(u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                                    u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y);
        length += hypot(point.x - previous.x, point.y - previous.y);
        previous = point;
    }
    return length;
}

int main(void) {
    Recorded r;

    // Relative arc: a quarter turn counterclockwise from angle 0 on a circle at (10,10), radius 5.
    CGMutablePathRef arc = CGPathCreateMutable();
    CGPathAddRelativeArc(arc, NULL, 10, 10, 5, 0, M_PI / 2);
    walk(arc, &r);
    CHECK(r.count == 2);
    CHECK(r.type[0] == kCGPathElementMoveToPoint && near(r.point[0][0], 15, 10));
    CHECK(r.type[1] == kCGPathElementAddCurveToPoint && near(r.point[1][2], 10, 15));
    CHECK(near(r.point[1][0], 15, 10 + 5 * 0.5522847498) && near(r.point[1][1], 10 + 5 * 0.5522847498, 15));

    // A negative delta turns clockwise.
    CGMutablePathRef cw = CGPathCreateMutable();
    CGPathAddRelativeArc(cw, NULL, 10, 10, 5, 0, -M_PI / 2);
    walk(cw, &r);
    CHECK(r.count == 2 && near(r.point[1][2], 10, 5));

    // A half turn is two curves; a zero delta adds only the start point.
    CGMutablePathRef half = CGPathCreateMutable();
    CGPathAddRelativeArc(half, NULL, 10, 10, 5, 0, M_PI);
    walk(half, &r);
    CHECK(r.count == 3 && near(r.point[2][2], 5, 10));
    CGMutablePathRef none = CGPathCreateMutable();
    CGPathAddRelativeArc(none, NULL, 10, 10, 5, 0, 0);
    walk(none, &r);
    CHECK(r.count == 1 && r.type[0] == kCGPathElementMoveToPoint && near(r.point[0][0], 15, 10));

    // Deltas beyond a full turn keep going around.
    CGMutablePathRef full = CGPathCreateMutable();
    CGPathAddRelativeArc(full, NULL, 10, 10, 5, 0, 2 * M_PI);
    walk(full, &r);
    CHECK(r.count == 5 && near(r.point[4][2], 15, 10));
    CGMutablePathRef turnAndHalf = CGPathCreateMutable();
    CGPathAddRelativeArc(turnAndHalf, NULL, 10, 10, 5, 0, 3 * M_PI);
    walk(turnAndHalf, &r);
    CHECK(r.count == 7 && near(r.point[6][2], 5, 10));

    // An arbitrary start angle; the sweep is split into pieces of at most a quarter turn.
    CGMutablePathRef odd = CGPathCreateMutable();
    CGPathAddRelativeArc(odd, NULL, 10, 10, 5, M_PI, M_PI / 4);
    walk(odd, &r);
    CHECK(r.count == 2 && near(r.point[0][0], 5, 10) && near(r.point[1][2], 10 + 5 * cos(1.25 * M_PI), 10 + 5 * sin(1.25 * M_PI)));
    CHECK(near(r.point[1][0], 5, 10 - 5 * 4.0 / 3 * tan(M_PI / 16)));

    // With a current point, a line to the start of the arc comes first. The matrix applies to the points.
    CGMutablePathRef joined = CGPathCreateMutable();
    CGPathMoveToPoint(joined, NULL, 0, 0);
    CGAffineTransform scale = CGAffineTransformMakeScale(2, 3);
    CGPathAddRelativeArc(joined, &scale, 10, 10, 5, 0, M_PI / 2);
    walk(joined, &r);
    CHECK(r.count == 3 && r.type[1] == kCGPathElementAddLineToPoint && near(r.point[1][0], 30, 30));
    CHECK(near(r.point[2][2], 20, 45));

    // Dashing, 4 on and 2 off, over a line of length 20.
    CGMutablePathRef line = CGPathCreateMutable();
    CGPathMoveToPoint(line, NULL, 0, 0);
    CGPathAddLineToPoint(line, NULL, 20, 0);
    const CGFloat dash42[2] = {4, 2};
    CGPathRef d = CGPathCreateCopyByDashingPath(line, NULL, 0, dash42, 2);
    CHECK(d != NULL);
    const double p0[] = {0, 4, 6, 10, 12, 16, 18, 20};
    CHECK(pieces(d, p0, 4));
    // The phase skips into the pattern, and a negative phase wraps around it.
    d = CGPathCreateCopyByDashingPath(line, NULL, 1, dash42, 2);
    const double p1[] = {0, 3, 5, 9, 11, 15, 17, 20};
    CHECK(pieces(d, p1, 4));
    d = CGPathCreateCopyByDashingPath(line, NULL, 5, dash42, 2);
    const double p5[] = {1, 5, 7, 11, 13, 17, 19, 20};
    CHECK(pieces(d, p5, 4));
    d = CGPathCreateCopyByDashingPath(line, NULL, -1, dash42, 2);
    CHECK(pieces(d, p5, 4));
    // A single length is both the dash and the gap.
    const CGFloat dash3[1] = {3};
    d = CGPathCreateCopyByDashingPath(line, NULL, 0, dash3, 1);
    const double p3[] = {0, 3, 6, 9, 12, 15, 18, 20};
    CHECK(pieces(d, p3, 4));
    // With an odd count the pattern continues alternating through the repeat: 2 on, 1 off, 1 on, 2 off, ...
    const CGFloat dash211[3] = {2, 1, 1};
    d = CGPathCreateCopyByDashingPath(line, NULL, 0, dash211, 3);
    const double p211[] = {0, 2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15, 16, 18, 19, 20};
    CHECK(pieces(d, p211, 8));
    // Without a pattern the path comes back whole.
    d = CGPathCreateCopyByDashingPath(line, NULL, 0, NULL, 0);
    const double whole[] = {0, 20};
    CHECK(pieces(d, whole, 1));
    d = CGPathCreateCopyByDashingPath(line, NULL, 0, dash42, 0);
    CHECK(pieces(d, whole, 1));
    // Negative lengths count by their magnitude. All-zero lengths draw nothing.
    const CGFloat neg[2] = {-1, 2};
    d = CGPathCreateCopyByDashingPath(line, NULL, 0, neg, 2);
    const double pn[] = {0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15, 16, 18, 19};
    CHECK(pieces(d, pn, 7));
    const CGFloat zeros[2] = {0, 0};
    d = CGPathCreateCopyByDashingPath(line, NULL, 0, zeros, 2);
    CHECK(d != NULL);
    walk(d, &r);
    CHECK(r.count == 0);
    // The transform maps the result; the lengths stay in the source coordinates.
    CGAffineTransform twice = CGAffineTransformMakeScale(2, 2);
    d = CGPathCreateCopyByDashingPath(line, &twice, 0, dash42, 2);
    const double p2x[] = {0, 8, 12, 20, 24, 32, 36, 40};
    CHECK(pieces(d, p2x, 4));
    CHECK(CGPathCreateCopyByDashingPath(NULL, NULL, 0, dash42, 2) == NULL);

    // Each subpath restarts the pattern; a lone move point produces nothing.
    CGMutablePathRef two = CGPathCreateMutable();
    CGPathMoveToPoint(two, NULL, 0, 0);
    CGPathAddLineToPoint(two, NULL, 5, 0);
    CGPathMoveToPoint(two, NULL, 0, 10);
    CGPathAddLineToPoint(two, NULL, 5, 10);
    const CGFloat dash33[2] = {3, 3};
    d = CGPathCreateCopyByDashingPath(two, NULL, 0, dash33, 2);
    walk(d, &r);
    CHECK(r.count == 4 && near(r.point[0][0], 0, 0) && near(r.point[1][0], 3, 0) &&
          near(r.point[2][0], 0, 10) && near(r.point[3][0], 3, 10));
    CGMutablePathRef lone = CGPathCreateMutable();
    CGPathMoveToPoint(lone, NULL, 1, 1);
    d = CGPathCreateCopyByDashingPath(lone, NULL, 0, dash42, 2);
    CHECK(d != NULL);
    walk(d, &r);
    CHECK(r.count == 0);

    // A dash running around a corner keeps the corner; the closing edge of a subpath is dashed too.
    CGMutablePathRef rect = CGPathCreateMutable();
    CGPathMoveToPoint(rect, NULL, 0, 0);
    CGPathAddLineToPoint(rect, NULL, 10, 0);
    CGPathAddLineToPoint(rect, NULL, 10, 5);
    CGPathAddLineToPoint(rect, NULL, 0, 5);
    CGPathCloseSubpath(rect);
    const CGFloat dash63[2] = {6, 3};
    d = CGPathCreateCopyByDashingPath(rect, NULL, 0, dash63, 2);
    walk(d, &r);
    CHECK(r.count >= 8);
    CHECK(r.type[0] == kCGPathElementMoveToPoint && near(r.point[0][0], 0, 0));
    CHECK(r.type[1] == kCGPathElementAddLineToPoint && near(r.point[1][0], 6, 0));
    CHECK(near(r.point[2][0], 9, 0) && near(r.point[3][0], 10, 0) && near(r.point[4][0], 10, 5));
    int last = r.count - 1;
    CHECK(r.type[last] == kCGPathElementAddLineToPoint && near(r.point[last][0], 0, 0));
    CHECK(r.type[last - 1] == kCGPathElementMoveToPoint && near(r.point[last - 1][0], 0, 3));

    // A curve is cut into curves whose arc length is the dash length. The cubic here is about 27.9 long, so
    // with 6 on and 3 off there are three full dashes and a short one that ends at the end of the curve.
    CGMutablePathRef curve = CGPathCreateMutable();
    CGPathMoveToPoint(curve, NULL, 0, 0);
    CGPathAddCurveToPoint(curve, NULL, 0, 10, 20, 10, 20, 0);
    d = CGPathCreateCopyByDashingPath(curve, NULL, 0, dash63, 2);
    walk(d, &r);
    CHECK(r.count == 8);
    CHECK(r.type[0] == kCGPathElementMoveToPoint && near(r.point[0][0], 0, 0));
    for (int i = 0; i < 8; i += 2) {
        CHECK(r.type[i] == kCGPathElementMoveToPoint && r.type[i + 1] == kCGPathElementAddCurveToPoint);
        double length = cubicLength(r.point[i][0], r.point[i + 1][0], r.point[i + 1][1], r.point[i + 1][2]);
        if (i < 6)
            CHECK(fabs(length - 6) < 0.15);
        else
            CHECK(length > 0.5 && length < 1.0);
    }
    // The dashes are on the curve, in order: the pieces' start points move along it, and the last piece ends at its end.
    CHECK(r.point[2][0].x > r.point[1][2].x && r.point[4][0].x > r.point[3][2].x && r.point[6][0].x > r.point[5][2].x);
    CHECK(fabs(r.point[7][2].x - 20) < 0.05 && fabs(r.point[7][2].y) < 0.05);
    puts("PASS");
    return 0;
}
