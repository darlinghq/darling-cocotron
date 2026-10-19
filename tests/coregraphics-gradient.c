#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 100
#define H 10

static int failures;

static void check(int ok, const char *what)
{
    if (!ok) {
        printf("FAIL: %s\n", what);
        failures++;
    }
}

static CGContextRef makeContext(unsigned char **pixels)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    *pixels = calloc(W * H, 4);
    CGContextRef context = CGBitmapContextCreate(*pixels, W, H, 8, W * 4, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(rgb);
    return context;
}

// Row H/2 is far from the vertical edges, so the horizontal gradients below
// are independent of the bitmap's y orientation.
static const unsigned char *at(const unsigned char *pixels, int x)
{
    return pixels + ((H / 2) * W + x) * 4;
}

static int near(const unsigned char *p, int r, int g, int b, int a)
{
    // Onyx2D quantises the stops to about one sample per axis pixel and then to 8 bits,
    // so an exact match is not expected; 8 units is well below any wrong rule's error.
    const int tolerance = 8;
    return abs(p[0] - r) <= tolerance && abs(p[1] - g) <= tolerance
        && abs(p[2] - b) <= tolerance && abs(p[3] - a) <= tolerance;
}

static void report(const unsigned char *p, int x, const char *what)
{
    printf("%s: x=%d rgba=%d,%d,%d,%d\n", what, x, p[0], p[1], p[2], p[3]);
}

static void checkPixel(const unsigned char *pixels, int x, int r, int g, int b, int a, const char *what)
{
    const unsigned char *p = at(pixels, x);
    if (!near(p, r, g, b, a)) {
        report(p, x, what);
        failures++;
    }
}

static CGGradientRef makeGradient(const CGFloat *components, const CGFloat *locations, size_t count)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(rgb, components, locations, count);
    CGColorSpaceRelease(rgb);
    return gradient;
}

static void drawLinear(CGGradientRef gradient, CGFloat x0, CGFloat x1, CGGradientDrawingOptions options,
    unsigned char **pixels)
{
    CGContextRef context = makeContext(pixels);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(x0, 5), CGPointMake(x1, 5), options);
    CGContextRelease(context);
}

int main(void)
{
    const CGFloat redBlue[] = { 1, 0, 0, 1, 0, 0, 1, 1 };
    CGGradientRef two = makeGradient(redBlue, NULL, 2);
    check(two != NULL, "two-stop gradient is created");
    if (!two)
        return 1;
    check(CGGradientGetTypeID() != 0 && CFGetTypeID(two) == CGGradientGetTypeID(),
        "gradient is a CF object of CGGradientGetTypeID");
    CFRetain(two);
    CFRelease(two);

    unsigned char *pixels;
    drawLinear(two, 0, W - 1, 0, &pixels);
    checkPixel(pixels, 1, 252, 0, 3, 255, "two-stop start is red");
    checkPixel(pixels, W / 2, 128, 0, 128, 255, "two-stop midpoint is purple");
    checkPixel(pixels, W - 2, 3, 0, 252, 255, "two-stop end is blue");
    free(pixels);

    // Without extend, nothing is painted outside the axis; with extend the end colours continue.
    drawLinear(two, 25, 75, 0, &pixels);
    checkPixel(pixels, 5, 0, 0, 0, 0, "no extend before start is transparent");
    checkPixel(pixels, 95, 0, 0, 0, 0, "no extend after end is transparent");
    free(pixels);
    drawLinear(two, 25, 75, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation, &pixels);
    checkPixel(pixels, 5, 255, 0, 0, 255, "extend before start continues red");
    checkPixel(pixels, 95, 0, 0, 255, 255, "extend after end continues blue");
    free(pixels);
    drawLinear(two, 25, 75, kCGGradientDrawsBeforeStartLocation, &pixels);
    checkPixel(pixels, 5, 255, 0, 0, 255, "extend before only: red before start");
    checkPixel(pixels, 95, 0, 0, 0, 0, "extend before only: nothing after end");
    free(pixels);

    // Five stops at 0, .25, .5, .75, 1: red, green, blue, white, black.
    const CGFloat fiveColors[] = { 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1 };
    const CGFloat fiveLocations[] = { 0, 0.25, 0.5, 0.75, 1 };
    CGGradientRef five = makeGradient(fiveColors, fiveLocations, 5);
    check(five != NULL, "five-stop gradient is created");
    drawLinear(five, 0, W, 0, &pixels);
    checkPixel(pixels, 25, 0, 255, 0, 255, "five-stop 0.25 is green");
    checkPixel(pixels, 50, 0, 0, 255, 255, "five-stop 0.5 is blue");
    checkPixel(pixels, 75, 255, 255, 255, 255, "five-stop 0.75 is white");
    checkPixel(pixels, 37, 0, 128, 128, 255, "five-stop between green and blue is teal");
    free(pixels);
    CGGradientRelease(five);

    // Two stops at the same location make a hard edge.
    const CGFloat hardColors[] = { 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1 };
    const CGFloat hardLocations[] = { 0, 0.5, 0.5, 1 };
    CGGradientRef hard = makeGradient(hardColors, hardLocations, 4);
    check(hard != NULL, "hard-stop gradient is created");
    drawLinear(hard, 0, W, 0, &pixels);
    checkPixel(pixels, 25, 255, 0, 0, 255, "hard stop: red before the edge");
    checkPixel(pixels, 75, 0, 0, 255, 255, "hard stop: blue after the edge");
    free(pixels);

    // The axis is 101 wide so one colour sample lands exactly on the coincident stops at .5
    // (x = 51); the later stop's colour must win there. Probes at 25 and 75 never reach the tie.
    drawLinear(hard, 0, W + 1, 0, &pixels);
    checkPixel(pixels, 51, 0, 0, 255, 255, "hard stop: the later colour wins at the coincident location");
    free(pixels);
    CGGradientRelease(hard);

    // A first stop above 0 holds its own colour to the left of it instead of extrapolating.
    const CGFloat lateStart[] = { 0.5, 0.5, 0.5, 1, 1, 1, 1, 1 };
    const CGFloat lateStartLocations[] = { 0.25, 1 };
    CGGradientRef late = makeGradient(lateStart, lateStartLocations, 2);
    check(late != NULL, "first-stop-at-0.25 gradient is created");
    drawLinear(late, 0, W, 0, &pixels);
    checkPixel(pixels, 10, 128, 128, 128, 255, "first stop above 0: left of it is the first colour");
    free(pixels);
    CGGradientRelease(late);

    // Locations {0, .8, .3, 1} never decrease: .3 becomes .8, so past .8 the ramp runs blue to white.
    const CGFloat unorderedColors[] = { 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1 };
    const CGFloat unorderedLocations[] = { 0, 0.8, 0.3, 1 };
    CGGradientRef unordered = makeGradient(unorderedColors, unorderedLocations, 4);
    check(unordered != NULL, "unordered-location gradient is created");
    drawLinear(unordered, 0, W, 0, &pixels);
    checkPixel(pixels, 70, 33, 222, 0, 255, "unordered locations: red to green below .8");
    checkPixel(pixels, 90, 126, 126, 255, 255, "unordered locations: blue to white past .8");
    free(pixels);
    CGGradientRelease(unordered);

    // Locations outside 0...1 are clamped, so {-1, 2} behaves like the default {0, 1}.
    const CGFloat outsideLocations[] = { -1, 2 };
    CGGradientRef outside = makeGradient(redBlue, outsideLocations, 2);
    check(outside != NULL, "out-of-range-location gradient is created");
    drawLinear(outside, 0, W, 0, &pixels);
    checkPixel(pixels, W / 2, 128, 0, 128, 255, "out-of-range locations are clamped to 0...1");
    free(pixels);
    CGGradientRelease(outside);

    // Alpha is interpolated and the result is premultiplied.
    const CGFloat fadeColors[] = { 1, 1, 1, 1, 1, 1, 1, 0 };
    CGGradientRef fade = makeGradient(fadeColors, NULL, 2);
    drawLinear(fade, 0, W, 0, &pixels);
    checkPixel(pixels, W / 2, 128, 128, 128, 128, "alpha fade midpoint is premultiplied half white");
    free(pixels);
    CGGradientRelease(fade);

    // Radial: red at the centre, blue at radius 40, nothing outside without extend.
    CGContextRef context = makeContext(&pixels);
    CGContextDrawRadialGradient(context, two, CGPointMake(50, 5), 0, CGPointMake(50, 5), 40, 0);
    CGContextRelease(context);
    checkPixel(pixels, 50, 255, 0, 0, 255, "radial centre is red");
    checkPixel(pixels, 70, 128, 0, 128, 255, "radial halfway is purple");
    checkPixel(pixels, 95, 0, 0, 0, 0, "radial outside the end radius is transparent");
    free(pixels);

    // The colour-array constructor converts CGColors.
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGColorRef red = CGColorCreate(rgb, redBlue);
    CGColorRef blue = CGColorCreate(rgb, redBlue + 4);
    const void *colors[] = { red, blue };
    CFArrayRef array = CFArrayCreate(NULL, colors, 2, &kCFTypeArrayCallBacks);
    CGGradientRef fromColors = CGGradientCreateWithColors(rgb, array, NULL);
    check(fromColors != NULL, "CGGradientCreateWithColors creates a gradient");
    if (fromColors) {
        drawLinear(fromColors, 0, W - 1, 0, &pixels);
        checkPixel(pixels, 1, 252, 0, 3, 255, "colour-array gradient starts red");
        checkPixel(pixels, W - 2, 3, 0, 252, 255, "colour-array gradient ends blue");
        free(pixels);
        CGGradientRelease(fromColors);
    }
    CFRelease(array);
    CGColorRelease(red);
    CGColorRelease(blue);

    // Invalid input is refused instead of read out of bounds.
    check(CGGradientCreateWithColorComponents(rgb, redBlue, NULL, 0) == NULL, "zero stops are refused");
    check(CGGradientCreateWithColorComponents(NULL, redBlue, NULL, 2) == NULL, "NULL colour space is refused");
    CGColorSpaceRelease(rgb);

    CGGradientRelease(two);
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
