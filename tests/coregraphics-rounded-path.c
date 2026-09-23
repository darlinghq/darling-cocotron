#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int count;
    int curves;
    int closes;
    CGPoint first;
    CGPoint firstCurveEnd;
} PathElements;

static void inspect(void *context, const CGPathElement *element)
{
    PathElements *state = context;
    if (state->count == 0)
        state->first = element->points[0];
    if (element->type == kCGPathElementAddCurveToPoint) {
        if (state->curves == 0)
            state->firstCurveEnd = element->points[2];
        state->curves++;
    }
    if (element->type == kCGPathElementCloseSubpath)
        state->closes++;
    state->count++;
}

static void expect(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static int near(CGFloat a, CGFloat b)
{
    return fabs(a - b) < 0.0001;
}

int main(void)
{
    CGRect rect = CGRectMake(2, 3, 100, 60);
    CGPathRef path = CGPathCreateWithRoundedRect(rect, 10, 5, NULL);
    PathElements state = {0};
    CGPathApply(path, &state, inspect);
    expect(state.count == 10 && state.curves == 4 && state.closes == 1,
           "four elliptical corners and a closed subpath");
    expect(near(state.first.x, 12) && near(state.first.y, 3),
           "first point respects the horizontal corner radius");
    expect(near(state.firstCurveEnd.x, 102) && near(state.firstCurveEnd.y, 8),
           "first curve ends at the next edge");
    CGRect bounds = CGPathGetBoundingBox(path);
    expect(near(bounds.origin.x, 2) && near(bounds.origin.y, 3) &&
           near(bounds.size.width, 100) && near(bounds.size.height, 60),
           "path stays within the original rectangle");
    CGPathRelease(path);

    CGAffineTransform translated = CGAffineTransformMakeTranslation(7, 11);
    path = CGPathCreateWithRoundedRect(rect, 500, 500, &translated);
    state = (PathElements){0};
    CGPathApply(path, &state, inspect);
    expect(near(state.first.x, 59) && near(state.first.y, 14),
           "oversized radii clamp and transform applies");
    bounds = CGPathGetBoundingBox(path);
    expect(near(bounds.origin.x, 9) && near(bounds.origin.y, 14) &&
           near(bounds.size.width, 100) && near(bounds.size.height, 60),
           "transformed bounds");
    CGPathRelease(path);

    CGMutablePathRef appended = CGPathCreateMutable();
    CGPathAddRect(appended, NULL, CGRectMake(0, 0, 1, 1));
    CGPathAddRoundedRect(appended, NULL, rect, 0, 5);
    state = (PathElements){0};
    CGPathApply(appended, &state, inspect);
    expect(state.count == 10 && state.curves == 0 && state.closes == 2,
           "zero-radius fallback appends a rectangle without dropping prior path");
    CGPathRelease(appended);

    puts("PASS: rounded path geometry, transforms, clamping, and append behavior");
    return 0;
}
