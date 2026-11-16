// Copyright (C) 2026 Lubos Dolezel
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// Dashing: the outline of a path is walked by arc length and the "on" stretches of a dash pattern are copied out as
// open subpaths. Straight segments give lines; curves give the matching piece of the curve.

#import <Onyx2D/O2MutablePath.h>
#import <Onyx2D/O2Path.h>
#include <math.h>
#include <stdlib.h>

// How finely a curve's arc length is tabulated.
#define CURVE_STEPS 256

typedef struct {
    BOOL isCurve;
    O2Point p[4]; // a line uses p[0], p[1]; a cubic all four (a quadratic is raised to a cubic)
    O2Float length;
    O2Float table[CURVE_STEPS + 1]; // arc length at t = i / CURVE_STEPS, curves only
} DashSegment;

static O2Point lerp(O2Point a, O2Point b, double t) {
    return O2PointMake(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
}

static O2Point cubicPoint(const O2Point *p, double t) {
    O2Point a = lerp(p[0], p[1], t), b = lerp(p[1], p[2], t), c = lerp(p[2], p[3], t);
    return lerp(lerp(a, b, t), lerp(b, c, t), t);
}

static void measureSegment(DashSegment *segment) {
    if (!segment->isCurve) {
        segment->length = hypot(segment->p[1].x - segment->p[0].x, segment->p[1].y - segment->p[0].y);
        return;
    }
    O2Point previous = segment->p[0];
    segment->table[0] = 0;
    for (int i = 1; i <= CURVE_STEPS; i++) {
        O2Point point = cubicPoint(segment->p, (double) i / CURVE_STEPS);
        segment->table[i] = segment->table[i - 1] + hypot(point.x - previous.x, point.y - previous.y);
        previous = point;
    }
    segment->length = segment->table[CURVE_STEPS];
}

// The curve parameter that lies the given arc length from the start of the segment.
static double parameterAtLength(const DashSegment *segment, double distance) {
    if (!segment->isCurve)
        return segment->length > 0 ? distance / segment->length : 0;
    if (distance <= 0)
        return 0;
    if (distance >= segment->length)
        return 1;
    int low = 0, high = CURVE_STEPS;
    while (high - low > 1) {
        int mid = (low + high) / 2;
        if (segment->table[mid] <= distance)
            low = mid;
        else
            high = mid;
    }
    double span = segment->table[high] - segment->table[low];
    double fraction = span > 0 ? (distance - segment->table[low]) / span : 0;
    return (low + fraction) / CURVE_STEPS;
}

// The control points of the part of a cubic between two parameters.
static void subCubic(const O2Point *p, double t0, double t1, O2Point *out) {
    // Split at t1 and keep the first part, then split that at t0/t1 and keep the second part.
    O2Point a = lerp(p[0], p[1], t1), b = lerp(p[1], p[2], t1), c = lerp(p[2], p[3], t1);
    O2Point d = lerp(a, b, t1), e = lerp(b, c, t1);
    O2Point f = lerp(d, e, t1);
    O2Point q[4] = {p[0], a, d, f};
    double u = t1 > 0 ? t0 / t1 : 0;
    O2Point g = lerp(q[0], q[1], u), h = lerp(q[1], q[2], u), i = lerp(q[2], q[3], u);
    O2Point j = lerp(g, h, u), k = lerp(h, i, u);
    O2Point l = lerp(j, k, u);
    out[0] = l;
    out[1] = k;
    out[2] = i;
    out[3] = q[3];
}

typedef struct {
    O2MutablePathRef path;
    const O2AffineTransform *transform;
    const O2Float *lengths;
    size_t count;     // lengths in the cycle; a pattern of odd length is walked twice so on and off alternate
    size_t index;     // current pattern element
    O2Float remaining; // left of the current element
    BOOL dashOpen;
} Dasher;

// Starts a subpath: the pattern is entered phase units from its start.
static void dasherReset(Dasher *dasher, O2Float phase, O2Float total) {
    O2Float rest = fmod(phase, total);
    if (rest < 0)
        rest += total;
    dasher->index = 0;
    for (size_t guard = 0; guard < 2 * dasher->count && rest > 0 && rest >= dasher->lengths[dasher->index]; guard++) {
        rest -= dasher->lengths[dasher->index];
        dasher->index = (dasher->index + 1) % dasher->count;
    }
    dasher->remaining = dasher->lengths[dasher->index] - rest;
    dasher->dashOpen = NO;
}

static void dashSegment(Dasher *dasher, const DashSegment *segment) {
    O2Float position = 0;
    while (position < segment->length) {
        O2Float left = segment->length - position;
        BOOL ends = dasher->remaining <= left;
        O2Float take = ends ? dasher->remaining : left;
        BOOL on = (dasher->index & 1) == 0;
        if (on) {
            double t0 = parameterAtLength(segment, position);
            double t1 = ends ? parameterAtLength(segment, position + take) : 1;
            if (!dasher->dashOpen) {
                O2Point from = segment->isCurve ? cubicPoint(segment->p, t0) : lerp(segment->p[0], segment->p[1], t0);
                O2PathMoveToPoint(dasher->path, dasher->transform, from.x, from.y);
                dasher->dashOpen = YES;
            }
            if (segment->isCurve) {
                O2Point q[4];
                subCubic(segment->p, t0, t1, q);
                O2PathAddCurveToPoint(dasher->path, dasher->transform, q[1].x, q[1].y, q[2].x, q[2].y, q[3].x, q[3].y);
            } else {
                O2Point to = lerp(segment->p[0], segment->p[1], t1);
                O2PathAddLineToPoint(dasher->path, dasher->transform, to.x, to.y);
            }
        }
        if (ends) {
            position += take;
            if (on)
                dasher->dashOpen = NO;
            dasher->index = (dasher->index + 1) % dasher->count;
            dasher->remaining = dasher->lengths[dasher->index];
            if (dasher->remaining == 0 && position >= segment->length)
                break;
        } else {
            dasher->remaining -= take;
            position = segment->length;
        }
    }
}

O2PathRef O2PathCreateCopyByDashingPath(O2PathRef self, const O2AffineTransform *transform, O2Float phase,
    const O2Float *lengths, size_t count)
{
    if (self == nil || !isfinite(phase))
        return nil;
    if (lengths == NULL || count == 0) {
        O2MutablePathRef copy = O2PathCreateMutableCopy(self);
        if (copy != nil && transform != NULL)
            O2PathApplyTransform(copy, *transform);
        return copy;
    }

    // Lengths count by magnitude. Odd patterns are doubled so that the roles of the elements swap on the repeat.
    size_t cycle = (count & 1) ? count * 2 : count;
    O2Float *pattern = malloc(cycle * sizeof(O2Float));
    if (pattern == NULL)
        return nil;
    O2Float total = 0;
    for (size_t i = 0; i < cycle; i++) {
        pattern[i] = fabs(lengths[i % count]);
        if (!isfinite(pattern[i])) {
            free(pattern);
            return nil;
        }
        total += pattern[i];
    }

    O2MutablePathRef path = O2PathCreateMutable();
    if (total <= 0 || !isfinite(total)) {
        free(pattern);
        return path;
    }

    Dasher dasher = {path, transform, pattern, cycle, 0, 0, NO};
    const unsigned char *elements = O2PathElements(self);
    const O2Point *points = O2PathPoints(self);
    size_t elementCount = O2PathNumberOfElements(self);
    size_t pointIndex = 0;
    O2Point start = O2PointMake(0, 0), current = start;
    BOOL haveSubpath = NO;
    DashSegment *segment = malloc(sizeof(DashSegment));
    if (segment == NULL) {
        free(pattern);
        return path;
    }

    for (size_t i = 0; i < elementCount; i++) {
        switch (elements[i]) {
        case kO2PathElementMoveToPoint:
            if (haveSubpath)
                dasher.dashOpen = NO;
            start = current = points[pointIndex++];
            dasherReset(&dasher, phase, total);
            haveSubpath = YES;
            break;
        case kO2PathElementAddLineToPoint:
        case kO2PathElementAddQuadCurveToPoint:
        case kO2PathElementAddCurveToPoint: {
            if (!haveSubpath) {
                dasherReset(&dasher, phase, total);
                haveSubpath = YES;
            }
            segment->p[0] = current;
            if (elements[i] == kO2PathElementAddLineToPoint) {
                segment->isCurve = NO;
                segment->p[1] = points[pointIndex++];
                current = segment->p[1];
            } else if (elements[i] == kO2PathElementAddQuadCurveToPoint) {
                O2Point control = points[pointIndex++], end = points[pointIndex++];
                segment->isCurve = YES;
                segment->p[1] = lerp(current, control, 2.0 / 3);
                segment->p[2] = lerp(end, control, 2.0 / 3);
                segment->p[3] = end;
                current = end;
            } else {
                segment->isCurve = YES;
                segment->p[1] = points[pointIndex++];
                segment->p[2] = points[pointIndex++];
                segment->p[3] = points[pointIndex++];
                current = segment->p[3];
            }
            measureSegment(segment);
            dashSegment(&dasher, segment);
            break;
        }
        case kO2PathElementCloseSubpath:
            if (haveSubpath && (current.x != start.x || current.y != start.y)) {
                segment->isCurve = NO;
                segment->p[0] = current;
                segment->p[1] = start;
                measureSegment(segment);
                dashSegment(&dasher, segment);
            }
            dasher.dashOpen = NO;
            current = start;
            haveSubpath = NO;
            break;
        }
    }
    free(segment);
    free(pattern);
    return path;
}
