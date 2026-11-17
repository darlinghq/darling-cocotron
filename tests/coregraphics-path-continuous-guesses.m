#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

// CGPathCreateMutableCopyByTransformingPath (public, documented: EXPECT_DOC) and CGPathCreateWithContinuousRoundedRect
// (private, not in the public documentation: EXPECT_GUESS). The guess: the argument order is (rect, cornerWidth,
// cornerHeight, transform), copied from CGPathCreateWithRoundedRect, and the result is the ordinary rounded rectangle
// (WebKit's own fallback where the continuous form is unavailable). Names are looked up with dlsym: the stock link
// line of the harness does not export them.
typedef CGMutablePathRef (*MutableCopyFn)(CGPathRef, const CGAffineTransform *);
typedef CGPathRef (*ContinuousFn)(CGRect, CGFloat, CGFloat, const CGAffineTransform *);

static int failures;
#define EXPECT_DOC(condition, message) \
    do { if (!(condition)) { printf("FAIL (documented contract): %s\n", message); failures++; } } while (0)
#define EXPECT_GUESS(condition, message) \
    do { if (!(condition)) { printf("FAIL (GUESS, not in the public documentation): %s\n", message); failures++; } } while (0)

#define MAX_POINTS 128
typedef struct { int types[MAX_POINTS]; CGPoint points[MAX_POINTS * 3]; int count, npoints; } Elements;

static void collect(void *info, const CGPathElement *e) {
    Elements *out = info;
    static const int counts[] = { 1, 1, 2, 3, 0 };
    if (out->count >= MAX_POINTS) return;
    out->types[out->count++] = e->type;
    for (int k = 0; k < counts[e->type]; k++) out->points[out->npoints++] = e->points[k];
}
static Elements elementsOf(CGPathRef path) { Elements e; memset(&e, 0, sizeof e); CGPathApply(path, &e, collect); return e; }
static int samePoint(CGPoint a, CGPoint b) { return a.x == b.x && a.y == b.y; }
static int sameElements(const Elements *a, const Elements *b) {
    if (a->count != b->count || a->npoints != b->npoints) return 0;
    if (memcmp(a->types, b->types, a->count * sizeof(int)) != 0) return 0;
    for (int k = 0; k < a->npoints; k++) if (!samePoint(a->points[k], b->points[k])) return 0;
    return 1;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    MutableCopyFn mutableCopy = (MutableCopyFn) dlsym(RTLD_DEFAULT, "CGPathCreateMutableCopyByTransformingPath");
    ContinuousFn continuous = (ContinuousFn) dlsym(RTLD_DEFAULT, "CGPathCreateWithContinuousRoundedRect");
    if (!mutableCopy || !continuous) { printf("FAIL: the two path functions are exported\n"); return 1; }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    CGMutablePathRef src = CGPathCreateMutable();
    CGPathMoveToPoint(src, NULL, 1, 2);
    CGPathAddLineToPoint(src, NULL, 11, 2);
    CGPathAddQuadCurveToPoint(src, NULL, 13, 4, 11, 6);
    CGPathAddCurveToPoint(src, NULL, 10, 7, 9, 8, 8, 9);
    CGPathCloseSubpath(src);
    Elements original = elementsOf(src);

    CGAffineTransform t = CGAffineTransformMake(2, 0, 0, 3, 5, 7);
    CGMutablePathRef copy = mutableCopy(src, &t);
    EXPECT_DOC(copy != NULL, "the transformed mutable copy is created");
    Elements moved = elementsOf(copy);
    EXPECT_DOC(moved.count == original.count && moved.npoints == original.npoints && memcmp(moved.types, original.types, original.count * sizeof(int)) == 0,
               "the copy has the same elements");
    int pointsOk = moved.npoints == original.npoints;
    for (int k = 0; pointsOk && k < original.npoints; k++)
        pointsOk = samePoint(moved.points[k], CGPointApplyAffineTransform(original.points[k], t));
    EXPECT_DOC(pointsOk, "every point, control points included, is multiplied by the transform");
    Elements after = elementsOf(src);
    EXPECT_DOC(sameElements(&after, &original), "the source path is not changed");

    CGPathAddLineToPoint(copy, NULL, 100, 100);
    Elements grown = elementsOf(copy);
    Elements untouched = elementsOf(src);
    EXPECT_DOC(grown.count == moved.count + 1 && sameElements(&untouched, &original), "the copy is mutable and independent of the source");
    CGPathRelease(copy);

    CGMutablePathRef plain = mutableCopy(src, NULL);
    Elements plainEls = elementsOf(plain);
    EXPECT_DOC(plain != NULL && sameElements(&plainEls, &original), "a NULL transform gives an identical copy");
    CGPathRelease(plain);
    // In a child: a missing guard crashes, and a crash must read as a failed expectation, not kill the test.
    {
        fflush(stdout);
        pid_t child = fork();
        if (child == 0) _exit(mutableCopy(NULL, &t) == NULL ? 0 : 1);
        int status = 0;
        waitpid(child, &status, 0);
        EXPECT_DOC(WIFEXITED(status) && WEXITSTATUS(status) == 0, "a NULL path gives NULL");
    }
    CGPathRelease(src);

    // Continuous rounded rectangle.
    CGRect rect = CGRectMake(0, 0, 200, 100);
    CGPathRef c = continuous(rect, 20, 20, NULL);
    EXPECT_GUESS(c != NULL, "the continuous rounded rectangle is created");
    if (c) {
        CGRect box = CGPathGetBoundingBox(c);
        EXPECT_GUESS(box.origin.x == 0 && box.origin.y == 0 && box.size.width == 200 && box.size.height == 100, "its bounds are the rectangle");
        CGPathRef plainRound = CGPathCreateWithRoundedRect(rect, 20, 20, NULL);
        Elements a = elementsOf(c), b = elementsOf(plainRound);
        EXPECT_GUESS(sameElements(&a, &b), "it is the ordinary rounded rectangle of the same rect and radii");
        EXPECT_GUESS(a.count > 4 && a.types[0] == kCGPathElementMoveToPoint, "it is a subpath of lines and curves starting with a move");
        CGPathRelease(plainRound);
        CGPathRelease(c);
    }
    // Argument order: width radius first. An elliptical corner distinguishes the two radii.
    {
        CGPathRef a = continuous(rect, 40, 10, NULL), b = CGPathCreateWithRoundedRect(rect, 40, 10, NULL), swapped = CGPathCreateWithRoundedRect(rect, 10, 40, NULL);
        Elements ea = elementsOf(a), eb = elementsOf(b), es = elementsOf(swapped);
        EXPECT_GUESS(sameElements(&ea, &eb), "cornerWidth is the second argument and cornerHeight the third");
        EXPECT_GUESS(!sameElements(&ea, &es), "(control) swapping the radii changes the path");
        CGPathRelease(a); CGPathRelease(b); CGPathRelease(swapped);
    }
    // Radii clamped to half the size, like CGPathCreateWithRoundedRect.
    {
        CGPathRef a = continuous(rect, 150, 150, NULL), b = CGPathCreateWithRoundedRect(rect, 150, 150, NULL);
        Elements ea = elementsOf(a), eb = elementsOf(b);
        EXPECT_GUESS(sameElements(&ea, &eb), "oversized radii are clamped like CGPathCreateWithRoundedRect");
        CGPathRelease(a); CGPathRelease(b);
    }
    // Transform.
    {
        CGAffineTransform shift = CGAffineTransformMakeTranslation(10, 20);
        CGPathRef a = continuous(rect, 20, 20, &shift);
        CGRect box = a ? CGPathGetBoundingBox(a) : CGRectZero;
        EXPECT_GUESS(a && box.origin.x == 10 && box.origin.y == 20 && box.size.width == 200, "the transform is applied");
        if (a) CGPathRelease(a);
    }
    [pool release];
    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("PASS\n");
    return 0;
}
