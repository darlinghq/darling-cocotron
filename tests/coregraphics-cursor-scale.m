// Copyright (C) 2026 Lubos Dolezel
//
// The private cursor-scale SPI starts at the neutral factor, accepts a finite factor in [1, 4], clamps values
// outside that range and rejects an invalid output pointer or a non-finite value without changing the state.
// Build: clang -framework CoreGraphics <private include dir> coregraphics-cursor-scale.m
#import <CoreGraphics/CGSCursorPrivate.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static CGFloat Get(void)
{
    CGFloat scale = 0;
    CHECK(CGSGetCursorScale(0, &scale) == kCGErrorSuccess);
    return scale;
}

int main(void)
{
    CHECK(Get() == 1.0);
    CHECK(CGSGetCursorScale(0, NULL) == kCGErrorIllegalArgument);

    CHECK(CGSSetCursorScale(0, 2.5) == kCGErrorSuccess);
    CHECK(Get() == 2.5);

    CHECK(CGSSetCursorScale(0, 0.0) == kCGErrorSuccess);
    CHECK(Get() == 1.0);

    CHECK(CGSSetCursorScale(0, 9.0) == kCGErrorSuccess);
    CHECK(Get() == 4.0);

    CHECK(CGSSetCursorScale(0, NAN) == kCGErrorIllegalArgument);
    CHECK(Get() == 4.0);
    CHECK(CGSSetCursorScale(0, -INFINITY) == kCGErrorIllegalArgument);
    CHECK(Get() == 4.0);

    if (failures == 0)
        printf("PASS: cursor scale SPI\n");
    return failures ? 1 : 0;
}
