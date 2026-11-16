// Copyright (C) 2026 Lubos Dolezel
// CAGradientLayer: the defaults, the properties, and the pixels of an axial gradient drawn into a
// bitmap context. Colors are compared by their dominant channels because macOS converts them to the
// color space of the output.
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

// macOS renders a layer into a context with -renderInContext:. Where that is not implemented, the
// bitmap the layer builds for its contents is drawn instead (macOS has no contents for a gradient layer).
static void render(CAGradientLayer *layer, CGContextRef context)
{
    if ([layer respondsToSelector: @selector(renderInContext:)]) {
        [layer renderInContext: context];
        return;
    }
    [layer display];
    CGImageRef image = (CGImageRef) layer.contents;
    if (image != NULL)
        CGContextDrawImage(context, layer.bounds, image);
}

static unsigned char *pixel(unsigned char *p, int x, int y, int w)
{
    return p + (y * w + x) * 4;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        CAGradientLayer *layer = [CAGradientLayer layer];
        CHECK(layer.colors == nil);
        CHECK(layer.locations == nil);
        CHECK(layer.startPoint.x == 0.5 && layer.startPoint.y == 0);
        CHECK(layer.endPoint.x == 0.5 && layer.endPoint.y == 1);
        CHECK([layer.type isEqualToString: kCAGradientLayerAxial]);

        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        CGColorRef blue = CGColorCreateGenericRGB(0, 0, 1, 1);
        layer.frame = CGRectMake(0, 0, 100, 20);
        layer.colors = [NSArray arrayWithObjects: (id) red, (id) blue, nil];
        layer.locations = [NSArray arrayWithObjects: [NSNumber numberWithDouble: 0], [NSNumber numberWithDouble: 1], nil];
        layer.startPoint = CGPointMake(0, 0.5);
        layer.endPoint = CGPointMake(1, 0.5);
        CHECK([layer.colors count] == 2);
        CHECK([layer.locations count] == 2);
        CHECK(layer.startPoint.x == 0 && layer.startPoint.y == 0.5);
        CHECK(layer.endPoint.x == 1 && layer.endPoint.y == 0.5);

        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 100, 20, 8, 400, rgb, kCGImageAlphaPremultipliedLast);
        render(layer, context);
        unsigned char *p = CGBitmapContextGetData(context);
        unsigned char *left = pixel(p, 2, 10, 100), *middle = pixel(p, 50, 10, 100), *right = pixel(p, 97, 10, 100);
        CHECK(left[0] > 200 && left[2] < 60 && left[3] == 255);
        CHECK(right[2] > 200 && right[0] < 60 && right[3] == 255);
        CHECK(middle[0] > 90 && middle[0] < 200 && middle[2] > 90 && middle[2] < 200);
        CGContextRelease(context);

        // Default points on a vertical layer: the start (0.5, 0) is the bottom edge of the layer, whose
        // rows are the last ones in memory; with only two colors they sit at 0 and 1.
        CAGradientLayer *vertical = [CAGradientLayer layer];
        vertical.frame = CGRectMake(0, 0, 20, 100);
        vertical.colors = [NSArray arrayWithObjects: (id) red, (id) blue, nil];
        context = CGBitmapContextCreate(NULL, 20, 100, 8, 80, rgb, kCGImageAlphaPremultipliedLast);
        render(vertical, context);
        p = CGBitmapContextGetData(context);
        CHECK(pixel(p, 10, 97, 20)[0] > 200 && pixel(p, 10, 97, 20)[2] < 60);
        CHECK(pixel(p, 10, 2, 20)[2] > 200 && pixel(p, 10, 2, 20)[0] < 60);

        // Locations: everything beyond the last location takes the last color.
        vertical.locations = [NSArray arrayWithObjects: [NSNumber numberWithDouble: 0], [NSNumber numberWithDouble: 0.25], nil];
        CGContextClearRect(context, CGRectMake(0, 0, 20, 100));
        render(vertical, context);
        CHECK(pixel(p, 10, 2, 20)[2] > 200 && pixel(p, 10, 2, 20)[0] < 60);
        CHECK(pixel(p, 10, 97, 20)[0] > 200 && pixel(p, 10, 97, 20)[2] < 60);
        CHECK(pixel(p, 10, 80, 20)[2] > pixel(p, 10, 80, 20)[0]); // 0.2 up from the bottom is 80% of the way to the last color
        CGContextRelease(context);

        // No colors: nothing is drawn.
        CAGradientLayer *empty = [CAGradientLayer layer];
        empty.frame = CGRectMake(0, 0, 20, 20);
        context = CGBitmapContextCreate(NULL, 20, 20, 8, 80, rgb, kCGImageAlphaPremultipliedLast);
        render(empty, context);
        p = CGBitmapContextGetData(context);
        CHECK(pixel(p, 10, 10, 20)[3] == 0);
        CGContextRelease(context);
        CGColorSpaceRelease(rgb);
        CGColorRelease(red);
        CGColorRelease(blue);
    }
    if (g_failures == 0)
        printf("PASS\n");
    return g_failures != 0;
}
