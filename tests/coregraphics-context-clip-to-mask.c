// Copyright (C) 2026 Lubos Dolezel
//
// CGContextClipToMask on a bitmap context: which samples of the mask image let a fill through,
// the area outside the mask rectangle, the user transform, successive masks and the graphics
// state stack. Expected values are the ones observed on macOS 26.7.3 and 10.14.4.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 40
#define H 10

static int g_failures;
#define CHECK(condition) do { if (!(condition)) { \
    printf("FAIL line %d: %s\n", __LINE__, #condition); g_failures++; } } while (0)
#define NEAR(value, expected) (abs((int) (value) - (int) (expected)) <= 2)

static CGContextRef make_context(void)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, W, H, 8, W * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    return c;
}

// Alpha of the pixel at column x, middle row.
static int alpha_at(CGContextRef c, int x)
{
    unsigned char *p = CGBitmapContextGetData(c);
    return p[(H / 2) * W * 4 + x * 4 + 3];
}

static void fill_red(CGContextRef c)
{
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
}

// Image whose left half has the sample values left[] and right half right[] (bytes per pixel = comps).
static CGImageRef make_image(CGColorSpaceRef cs, size_t comps, CGBitmapInfo info,
                             const unsigned char *left, const unsigned char *right, int is_mask)
{
    unsigned char *buf = malloc(W * H * comps);
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++)
            memcpy(buf + (y * W + x) * comps, x < W / 2 ? left : right, comps);
    CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, buf, W * H * comps, NULL);
    CGImageRef img = is_mask
        ? CGImageMaskCreate(W, H, 8, 8 * comps, W * comps, dp, NULL, false)
        : CGImageCreate(W, H, 8, 8 * comps, W * comps, cs, info, dp, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(dp);
    return img;
}

static void test_gray_image(void)
{
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    unsigned char black[1] = {0}, white[1] = {255}, half[1] = {128};
    CGImageRef img = make_image(gray, 1, kCGImageAlphaNone, black, white, 0);
    CGContextRef c = make_context();
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), img);
    fill_red(c);
    CHECK(alpha_at(c, 5) == 0);
    CHECK(alpha_at(c, 30) == 255);
    CGContextRelease(c);
    CGImageRelease(img);

    // The gray value is the coverage.
    img = make_image(gray, 1, kCGImageAlphaNone, half, white, 0);
    c = make_context();
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), img);
    fill_red(c);
    CHECK(NEAR(alpha_at(c, 5), 128));
    CHECK(alpha_at(c, 30) == 255);
    CGContextRelease(c);
    CGImageRelease(img);
    CGColorSpaceRelease(gray);
}

static void test_image_mask_is_inverted(void)
{
    unsigned char black[1] = {0}, white[1] = {255};
    CGImageRef img = make_image(NULL, 1, 0, black, white, 1);
    CGContextRef c = make_context();
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), img);
    fill_red(c);
    CHECK(alpha_at(c, 5) == 255);
    CHECK(alpha_at(c, 30) == 0);
    CGContextRelease(c);
    CGImageRelease(img);
}

static void test_rgba_image_uses_alpha(void)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    // Left transparent, right opaque white: only the alpha counts.
    unsigned char transparent[4] = {255, 255, 255, 0}, opaque_white[4] = {255, 255, 255, 255};
    CGImageRef img = make_image(rgb, 4, kCGImageAlphaPremultipliedLast, transparent, opaque_white, 0);
    CGContextRef c = make_context();
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), img);
    fill_red(c);
    CHECK(alpha_at(c, 5) == 0);
    CHECK(alpha_at(c, 30) == 255);
    CGContextRelease(c);
    CGImageRelease(img);

    // Opaque everywhere: the colors do not matter.
    unsigned char opaque_black[4] = {0, 0, 0, 255};
    img = make_image(rgb, 4, kCGImageAlphaPremultipliedLast, opaque_white, opaque_black, 0);
    c = make_context();
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), img);
    fill_red(c);
    CHECK(alpha_at(c, 5) == 255);
    CHECK(alpha_at(c, 30) == 255);
    CGContextRelease(c);
    CGImageRelease(img);
    CGColorSpaceRelease(rgb);
}

static void test_mask_rectangle_and_transform(void)
{
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    unsigned char white[1] = {255};
    CGImageRef img = make_image(gray, 1, kCGImageAlphaNone, white, white, 0);

    // Nothing is painted outside the rectangle the mask is placed in.
    CGContextRef c = make_context();
    CGContextClipToMask(c, CGRectMake(10, 0, 20, H), img);
    fill_red(c);
    CHECK(alpha_at(c, 5) == 0);
    CHECK(alpha_at(c, 15) == 255);
    CHECK(alpha_at(c, 35) == 0);
    CGContextRelease(c);

    // The rectangle is in user space.
    c = make_context();
    CGContextTranslateCTM(c, 20, 0);
    CGContextClipToMask(c, CGRectMake(0, 0, 10, H), img);
    CGContextTranslateCTM(c, -20, 0);
    fill_red(c);
    CHECK(alpha_at(c, 10) == 0);
    CHECK(alpha_at(c, 25) == 255);
    CHECK(alpha_at(c, 35) == 0);
    CGContextRelease(c);
    CGImageRelease(img);
    CGColorSpaceRelease(gray);
}

static void test_successive_masks_and_state_stack(void)
{
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    unsigned char black[1] = {0}, white[1] = {255};
    CGImageRef left_off = make_image(gray, 1, kCGImageAlphaNone, black, white, 0);   // right half
    CGImageRef right_off = make_image(gray, 1, kCGImageAlphaNone, white, black, 0);  // left half

    CGContextRef c = make_context();
    CGContextSaveGState(c);
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), left_off);
    fill_red(c);
    CHECK(alpha_at(c, 5) == 0);
    CHECK(alpha_at(c, 30) == 255);
    // A second mask intersects with the first.
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), right_off);
    CGContextSetRGBFillColor(c, 0, 1, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    CHECK(alpha_at(c, 5) == 0);
    CHECK(alpha_at(c, 30) == 255); // still the red from before; nothing new gets through
    unsigned char *p = CGBitmapContextGetData(c);
    CHECK(p[(H / 2) * W * 4 + 30 * 4 + 0] == 255 && p[(H / 2) * W * 4 + 30 * 4 + 1] == 0);
    CGContextRestoreGState(c);

    // After the restore the whole context is paintable again.
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    CHECK(alpha_at(c, 5) == 255);
    CGContextRelease(c);
    CGImageRelease(left_off);
    CGImageRelease(right_off);
    CGColorSpaceRelease(gray);
}

static void test_translucent_fill_and_path_fill(void)
{
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    unsigned char black[1] = {0}, white[1] = {255};
    CGImageRef img = make_image(gray, 1, kCGImageAlphaNone, black, white, 0);
    CGContextRef c = make_context();
    CGContextClipToMask(c, CGRectMake(0, 0, W, H), img);
    CGContextSetRGBFillColor(c, 1, 0, 0, 0.5);
    CGContextBeginPath(c);
    CGContextAddEllipseInRect(c, CGRectMake(0, 0, W, H));
    CGContextFillPath(c);
    CHECK(alpha_at(c, 5) == 0);
    CHECK(alpha_at(c, 30) > 100 && alpha_at(c, 30) < 140);
    CGContextRelease(c);
    CGImageRelease(img);
    CGColorSpaceRelease(gray);
}

int main(void)
{
    test_gray_image();
    test_image_mask_is_inverted();
    test_rgba_image_uses_alpha();
    test_mask_rectangle_and_transform();
    test_successive_masks_and_state_stack();
    test_translucent_fill_and_path_fill();
    if (g_failures == 0)
        printf("PASS\n");
    return g_failures != 0;
}
