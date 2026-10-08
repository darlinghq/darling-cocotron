#import <Foundation/NSAutoreleasePool.h>
#import <CoreGraphics/CGColor.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>

typedef CGColorRef (*CreateSRGB)(CGFloat, CGFloat, CGFloat, CGFloat);

#define CHECK(condition, code) do { \
    if (!(condition)) { \
        fprintf(stderr, "sRGB color check failed at line %d\n", __LINE__); \
        return code; \
    } \
} while (0)

static int matches(CGColorRef color, const CGFloat *expected) {
    if (color == NULL || CGColorGetNumberOfComponents(color) != 4)
        return 0;
    CGColorSpaceRef space = CGColorGetColorSpace(color);
    if (space == NULL || CGColorSpaceGetModel(space) != kCGColorSpaceModelRGB)
        return 0;
    CFStringRef name = CGColorSpaceGetName(space);
    if (name == NULL || !CFEqual(name, kCGColorSpaceSRGB))
        return 0;
    const CGFloat *components = CGColorGetComponents(color);
    for (size_t i = 0; i < 4; i++) {
        if (components[i] != expected[i])
            return 0;
    }
    return CGColorGetAlpha(color) == expected[3];
}

int main(void) {
    CreateSRGB create = (CreateSRGB) dlsym(RTLD_DEFAULT, "CGColorCreateSRGB");
    CHECK(create != NULL, 10);
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const CGFloat expected[] = { 0.125, 0.5, 0.875, 0.25 };
    CGColorRef color = create(expected[0], expected[1], expected[2], expected[3]);
    CHECK(matches(color, expected), 11);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CHECK(space != NULL, 12);
    CGColorRef equivalent = CGColorCreate(space, expected);
    CGColorSpaceRelease(space);
    CHECK(equivalent != NULL && CGColorEqualToColor(color, equivalent), 13);
    CGColorRelease(equivalent);
    CGColorRef copied = CGColorCreateCopy(color);
    CHECK(copied != NULL, 14);
    CGColorRef retained = CGColorRetain(copied);
    CGColorRelease(copied);
    CGColorRelease(color);
    [pool drain];
    CHECK(matches(retained, expected), 15);
    CGColorRelease(retained);

    pool = [[NSAutoreleasePool alloc] init];
    const CGFloat boundaries[][4] = { { 0, 1, 0, 0 }, { 1, 0, 1, 1 } };
    for (size_t i = 0; i < 2; i++) {
        color = create(boundaries[i][0], boundaries[i][1], boundaries[i][2], boundaries[i][3]);
        CHECK(matches(color, boundaries[i]), 16);
        CGColorRelease(color);
    }

    // Conservative rejection policy; no Apple invalid-input observation.
    CHECK(create(-0.01, 0.5, 0.5, 1) == NULL, 20);
    CHECK(create(0.5, 1.01, 0.5, 1) == NULL, 21);
    CHECK(create(0.5, 0.5, NAN, 1) == NULL, 22);
    CHECK(create(0.5, 0.5, 0.5, INFINITY) == NULL, 23);
    CHECK(create(0.5, 0.5, 0.5, -INFINITY) == NULL, 24);
    [pool drain];
    puts("sRGB color components, identity and owned lifetime passed");
    return 0;
}
