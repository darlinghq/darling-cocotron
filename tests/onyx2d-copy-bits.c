// CGContextCopyBits, which NSCopyBits and -[NSView scrollRect:by:] are built on,
// copies the pixels of a rectangle to the rectangle of the same size at a
// destination point (user space), in whole device pixels. The destination may
// overlap the source, lie outside it, or run off the bitmap (that part is
// left out). Documented behaviour:
// https://developer.apple.com/documentation/appkit/nscopybits(_:_:_:)
// (copies the pixels of srcRect to destPoint) and
// https://developer.apple.com/documentation/appkit/nsview/scroll(_:by:)
// (lays the portion down again at the offset from the rectangle's origin).
// The expected pixels are computed here from that description. Not covered:
// the source graphics-state number (Darling keeps no states by number), and an
// overlap within one row, where memcpy and memmove cannot be told apart
// deterministically; the overlap between rows (case 1) is order dependent.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 12
#define H 10

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static uint32_t pixels[W * H];

static void fill(void)
{
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++)
            pixels[y * W + x] = 0xFF000000u | (uint32_t) (y << 8) | (uint32_t) x;
}

static CGContextRef makeContext(void)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, W, H, 8, W * 4, rgb,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(rgb);
    return context;
}

// The expected result for a copy of the device box [x0,x1) x [y0,y1) (rows from
// the top of the data) by (dx, dy) device pixels: every pixel of the box that is
// in the bitmap and lands in it is copied to where it lands, from the pixels as
// they were before the copy.
static void expected(uint32_t *out, long x0, long y0, long x1, long y1, long dx, long dy)
{
    uint32_t original[W * H];
    memcpy(original, out, sizeof original);
    for (long y = y0; y < y1; y++)
        for (long x = x0; x < x1; x++) {
            long tx = x + dx, ty = y + dy;
            if (x >= 0 && x < W && y >= 0 && y < H && tx >= 0 && tx < W && ty >= 0 && ty < H)
                out[ty * W + tx] = original[y * W + x];
        }
}

int main(void)
{
    CGContextRef context = makeContext();
    uint32_t want[W * H];

    // User space has its origin at the bottom left: user (x, y) is device
    // column x and device row H - y. A rectangle of user height h at user y
    // is device rows H - y - h up to H - y.

    // 1. Right by 2 and up by 1: user rect (1,2)-(7,7) to point (3,3).
    fill();
    memcpy(want, pixels, sizeof want);
    expected(want, 1, H - 7, 7, H - 2, 2, -1);
    CGContextCopyBits(context, CGRectMake(1, 2, 6, 5), CGPointMake(3, 3), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "right and up");

    // 2. Left by 3 and down by 2.
    fill();
    memcpy(want, pixels, sizeof want);
    expected(want, 2, H - 8, 10, H - 1, -3, 2);
    CGContextCopyBits(context, CGRectMake(2, 1, 8, 7), CGPointMake(-1, -1), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "left and down");

    // 3. No offset: nothing changes.
    fill();
    memcpy(want, pixels, sizeof want);
    CGContextCopyBits(context, CGRectMake(1, 1, 5, 5), CGPointMake(1, 1), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "zero offset");

    // 4. A destination that does not overlap the source: rect (1,1)-(5,5) to point (5,1).
    fill();
    memcpy(want, pixels, sizeof want);
    expected(want, 1, H - 5, 5, H - 1, 4, 0);
    CGContextCopyBits(context, CGRectMake(1, 1, 4, 4), CGPointMake(5, 1), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "destination beside the rectangle");

    // 4b. A destination partly off the bitmap: only the columns that exist are written.
    fill();
    memcpy(want, pixels, sizeof want);
    expected(want, 1, H - 5, 5, H - 1, 9, 0);
    CGContextCopyBits(context, CGRectMake(1, 1, 4, 4), CGPointMake(10, 1), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "destination partly off the bitmap");

    // 5. A rectangle partly off the bitmap: only what exists is moved, nothing crashes.
    fill();
    memcpy(want, pixels, sizeof want);
    // the device box is x -3..W+3, rows -3..H+3, moved right by 1
    expected(want, -3, -3, W + 3, H + 3, 1, 0);
    CGContextCopyBits(context, CGRectMake(-3, -3, W + 6, H + 6), CGPointMake(-2, -3), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "rectangle beyond the bitmap");

    // 6. Scaled user space: user units are 2 device pixels. User rect (1,1)-(4,3)
    // is device columns 2..8, rows H-6..H-2; point (2,1) is one user unit
    // (two device columns) to the right.
    fill();
    memcpy(want, pixels, sizeof want);
    expected(want, 2, H - 6, 8, H - 2, 2, 0);
    CGContextScaleCTM(context, 2, 2);
    CGContextCopyBits(context, CGRectMake(1, 1, 3, 2), CGPointMake(2, 1), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "scaled user space");

    // 7. Values that are not coordinates or are huge: NaN changes nothing, a huge
    // rectangle is clipped to the bitmap (shifted right by 1), neither crashes.
    fill();
    memcpy(want, pixels, sizeof want);
    CGContextCopyBits(context, CGRectMake(0, 0, 4, 4), CGPointMake(NAN, 0), 0);
    CGContextCopyBits(context, CGRectMake(NAN, 0, 4, 4), CGPointMake(1, 0), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "NaN coordinates");
    CGContextScaleCTM(context, 0.5, 0.5);
    expected(want, 0, 0, W, H, 1, 0);
    CGContextCopyBits(context, CGRectMake(0, 0, 1e300, 1e300), CGPointMake(1, 0), 0);
    CHECK(memcmp(pixels, want, sizeof want) == 0, "huge rectangle");

    CGContextRelease(context);
    if (failures == 0)
        puts("PASS: onyx2d-copy-bits");
    return failures != 0;
}
