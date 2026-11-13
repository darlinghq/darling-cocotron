// Copyright (C) 2026 Lubos Dolezel
//
// Layers and transparency layers on a bitmap context. CGLayerCreateWithContext
// must give a layer whose context can be drawn into, and drawing the layer
// must land at the requested position. A transparency layer must composite
// where its content was drawn: under a translated CTM the content appears
// once at the translated position, not offset by the translation twice.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

enum { W = 8, H = 8 };

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

// Premultiplied RGBA bitmap context; row 0 of the data is the top row.
static CGContextRef makeContext(unsigned char *data) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    memset(data, 0, W * H * 4);
    CGContextRef context =
            CGBitmapContextCreate(data, W, H, 8, W * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return context;
}

static int isRed(const unsigned char *data, int x, int rowFromTop) {
    const unsigned char *p = data + (rowFromTop * W + x) * 4;
    return p[0] == 255 && p[1] == 0 && p[2] == 0 && p[3] == 255;
}

static int isClear(const unsigned char *data, int x, int rowFromTop) {
    const unsigned char *p = data + (rowFromTop * W + x) * 4;
    return p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0;
}

static void testLayer(void) {
    unsigned char data[W * H * 4];
    CGContextRef context = makeContext(data);
    CHECK(context != NULL, "bitmap context");
    if (context == NULL)
        return;

    CGLayerRef layer = CGLayerCreateWithContext(context, CGSizeMake(4, 4), NULL);
    CHECK(layer != NULL, "layer created");
    if (layer == NULL)
        return;
    CGSize size = CGLayerGetSize(layer);
    CHECK(size.width == 4 && size.height == 4, "layer size %g x %g", size.width, size.height);
    CGContextRef layerContext = CGLayerGetContext(layer);
    CHECK(layerContext != NULL, "layer context");
    if (layerContext != NULL) {
        CGContextSetRGBFillColor(layerContext, 1, 0, 0, 1);
        CGContextFillRect(layerContext, CGRectMake(0, 0, 4, 4));
    }

    // The layer's lower left corner goes to (1, 0): columns 1...4 and, from the top, rows 4...7.
    CGContextDrawLayerAtPoint(context, CGPointMake(1, 0), layer);
    CHECK(isRed(data, 1, 7), "layer lower left pixel");
    CHECK(isRed(data, 4, 4), "layer upper right pixel");
    CHECK(isClear(data, 0, 7), "left of the layer is untouched");
    CHECK(isClear(data, 5, 7), "right of the layer is untouched");
    CHECK(isClear(data, 2, 3), "above the layer is untouched");

    CGLayerRelease(layer);
    CGContextRelease(context);
}

static void testTransparencyLayerWithTranslation(void) {
    unsigned char data[W * H * 4];
    CGContextRef context = makeContext(data);
    CHECK(context != NULL, "bitmap context");
    if (context == NULL)
        return;

    CGContextBeginTransparencyLayer(context, NULL);
    CGContextTranslateCTM(context, 3, 0);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 2, 2));
    CGContextEndTransparencyLayer(context);

    // Filled once at x = 3...4, rows 6 and 7 from the top.
    CHECK(isRed(data, 3, 7) && isRed(data, 4, 6), "translated fill lands once");
    CHECK(isClear(data, 6, 7) && isClear(data, 7, 6), "no second translation");
    CHECK(isClear(data, 0, 7), "nothing at the untranslated position");

    CGContextRelease(context);
}

int main(void) {
    testLayer();
    testTransparencyLayerWithTranslation();
    if (failures == 0)
        printf("PASS: layers on bitmap contexts\n");
    return failures ? 1 : 0;
}
