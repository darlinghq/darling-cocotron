// Copyright (C) 2026 Lubos Dolezel
//
// Photoshop documents (PSD) are readable through ImageIO and NSImage: the flattened image, 8 bit
// RGB, gray and indexed, raw or PackBits compressed, with and without a transparency channel, as
// macOS reads them (black-box observation of macOS 10.14.4: type com.adobe.photoshop-image, one
// image, bitmap representation). Colours are compared with tolerance since macOS colour manages
// the picture; alpha is compared exactly. Truncated and malformed files give no image.
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>

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

static void put16(NSMutableData *d, unsigned v) {
    unsigned char b[2] = {v >> 8, v};
    [d appendBytes: b length: 2];
}
static void put32(NSMutableData *d, unsigned v) {
    unsigned char b[4] = {v >> 24, v >> 16, v >> 8, v};
    [d appendBytes: b length: 4];
}

// Planes: `channels` arrays of w*h bytes (8 bit). compression 0 raw, 1 PackBits (every row as one
// literal run, which is valid PackBits and keeps the writer trivial; a run of equal bytes is
// written as a repeat when the row is uniform, to exercise both kinds of packets).
static NSData *makePSD(int w, int h, int channels, int mode, int compression, const unsigned char *const *planes,
                       const unsigned char *palette) {
    NSMutableData *d = [NSMutableData data];
    [d appendBytes: "8BPS" length: 4];
    put16(d, 1);
    unsigned char zeros[6] = {0};
    [d appendBytes: zeros length: 6];
    put16(d, channels);
    put32(d, h);
    put32(d, w);
    put16(d, 8);
    put16(d, mode);
    if (palette) {
        put32(d, 768);
        [d appendBytes: palette length: 768];
    } else {
        put32(d, 0);
    }
    put32(d, 0); // image resources
    put32(d, 0); // layer and mask information
    put16(d, compression);
    if (compression == 0) {
        for (int c = 0; c < channels; c++)
            [d appendBytes: planes[c] length: w * h];
    } else {
        NSMutableData *rows = [NSMutableData data];
        NSMutableData *counts = [NSMutableData data];
        for (int c = 0; c < channels; c++) {
            for (int y = 0; y < h; y++) {
                const unsigned char *row = planes[c] + y * w;
                int uniform = 1;
                for (int x = 1; x < w; x++)
                    uniform &= row[x] == row[0];
                NSUInteger before = [rows length];
                if (uniform && w >= 2) {
                    unsigned char pkt[2] = {(unsigned char) (1 - w), row[0]}; // repeat w times
                    [rows appendBytes: pkt length: 2];
                } else {
                    unsigned char hdr = w - 1; // literal run of w bytes
                    [rows appendBytes: &hdr length: 1];
                    [rows appendBytes: row length: w];
                }
                put16(counts, (unsigned) ([rows length] - before));
            }
        }
        [d appendData: counts];
        [d appendData: rows];
    }
    return d;
}

// The decoded bytes of an image (what its data provider holds, rows of bytesPerRow bytes).
static NSData *rawOf(CGImageRef image) {
    return [(NSData *) CGDataProviderCopyData(CGImageGetDataProvider(image)) autorelease];
}

static const unsigned char *pixelOf(NSData *raw, CGImageRef image, int x, int y) {
    return (const unsigned char *) [raw bytes] + y * CGImageGetBytesPerRow(image) + x * (CGImageGetBitsPerPixel(image) / 8);
}

static CGImageRef decode(NSData *data, const char *name) {
    CGImageSourceRef src = CGImageSourceCreateWithData((CFDataRef) data, NULL);
    CHECK(src != NULL, "%s: no image source", name);
    if (src == NULL)
        return NULL;
    CHECK(CFEqual(CGImageSourceGetType(src), CFSTR("com.adobe.photoshop-image")), "%s: type is %s", name,
          [(NSString *) CGImageSourceGetType(src) UTF8String]);
    CHECK(CGImageSourceGetCount(src) == 1, "%s: count %zu", name, CGImageSourceGetCount(src));
    CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
    CHECK(image != NULL, "%s: no image", name);
    CFRelease(src);
    return image;
}

int main(void) {
    @autoreleasepool {
        // 4x2: pixel (x, y) has red = 60 * x, green = 100 * y, blue = 200, alpha = 255 - 40 * x
        enum { W = 4, H = 2 };
        unsigned char r[W * H], g[W * H], b[W * H], a[W * H];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                r[y * W + x] = 60 * x;
                g[y * W + x] = 100 * y;
                b[y * W + x] = 200;
                a[y * W + x] = 255 - 40 * x;
            }
        const unsigned char *rgb[] = {r, g, b};
        const unsigned char *rgba[] = {r, g, b, a};

        // 8 bit RGB, raw and PackBits: four bytes per pixel, the fourth skipped (macOS: kCGImageAlphaNoneSkipLast)
        for (int compression = 0; compression < 2; compression++) {
            char name[64];
            snprintf(name, sizeof name, "rgb compression %d", compression);
            CGImageRef image = decode(makePSD(W, H, 3, 3, compression, rgb, NULL), name);
            if (image != NULL) {
                CHECK(CGImageGetWidth(image) == W && CGImageGetHeight(image) == H, "%s: size %zux%zu", name,
                      CGImageGetWidth(image), CGImageGetHeight(image));
                CHECK(CGImageGetAlphaInfo(image) == kCGImageAlphaNoneSkipLast, "%s: alpha info %d", name,
                      CGImageGetAlphaInfo(image));
                CHECK(CGImageGetBitsPerPixel(image) == 32 && CGImageGetBitsPerComponent(image) == 8, "%s: bpp", name);
                NSData *raw = rawOf(image);
                const unsigned char *p = pixelOf(raw, image, 3, 1);
                CHECK(p[0] == 180 && p[1] == 100 && p[2] == 200, "%s: pixel %d %d %d", name, p[0], p[1], p[2]);
                p = pixelOf(raw, image, 0, 0);
                CHECK(p[0] == 0 && p[1] == 0 && p[2] == 200, "%s: pixel0 %d %d %d", name, p[0], p[1], p[2]);
                CGImageRelease(image);
            }
        }

        // a fourth channel is transparency; the pixels come out premultiplied (raw storage; macOS reads
        // the transparency of a PackBits compressed document as opaque, which is not asserted here)
        {
            CGImageRef image = decode(makePSD(W, H, 4, 3, 0, rgba, NULL), "rgba");
            if (image != NULL) {
                // (macOS labels these bytes kCGImageAlphaLast although they are premultiplied; the label is not asserted)
                CHECK(CGImageGetAlphaInfo(image) != kCGImageAlphaNone && CGImageGetAlphaInfo(image) != kCGImageAlphaNoneSkipLast,
                      "rgba: alpha info %d", CGImageGetAlphaInfo(image));
                NSData *raw = rawOf(image);
                const unsigned char *p = pixelOf(raw, image, 3, 1);
                CHECK(abs(p[0] - 95) <= 1 && abs(p[1] - 53) <= 1 && abs(p[2] - 106) <= 1 && p[3] == 135,
                      "rgba: pixel %d %d %d %d", p[0], p[1], p[2], p[3]);
                p = pixelOf(raw, image, 0, 0);
                CHECK(p[0] == 0 && p[1] == 0 && p[2] == 200 && p[3] == 255, "rgba: pixel0 %d %d %d %d", p[0], p[1], p[2], p[3]);
                CGImageRelease(image);
            }
        }

        // gray without transparency stays a one component image
        {
            const unsigned char *gray[] = {r};
            CGImageRef image = decode(makePSD(W, H, 1, 1, 0, gray, NULL), "gray");
            if (image != NULL) {
                CHECK(CGImageGetBitsPerPixel(image) == 8 && CGImageGetAlphaInfo(image) == kCGImageAlphaNone,
                      "gray: bpp %zu alpha %d", CGImageGetBitsPerPixel(image), CGImageGetAlphaInfo(image));
                CHECK(CGColorSpaceGetNumberOfComponents(CGImageGetColorSpace(image)) == 1, "gray: color space");
                NSData *raw = rawOf(image);
                const unsigned char *p = pixelOf(raw, image, 2, 1);
                CHECK(p[0] == 120, "gray: pixel %d", p[0]);
                CGImageRelease(image);
            }
        }

        // indexed: the palette is 256 reds, then 256 greens, then 256 blues; checked through a drawing
        {
            unsigned char pal[768] = {0};
            unsigned char idx[W * H];
            for (int i = 0; i < 256; i++) {
                pal[i] = 255 - i;
                pal[256 + i] = i;
            }
            for (int i = 0; i < W * H; i++)
                idx[i] = i * 30;
            const unsigned char *planes[] = {idx};
            CGImageRef image = decode(makePSD(W, H, 1, 2, 0, planes, pal), "indexed");
            if (image != NULL) {
                CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
                unsigned char buf[W * H * 4];
                CGContextRef ctx = CGBitmapContextCreate(buf, W, H, 8, W * 4, space, kCGImageAlphaPremultipliedLast);
                CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), image);
                const unsigned char *p = buf + 3 * 4; // top row (row 0 of the data), pixel 3: index 90
                CHECK(abs(p[0] - 165) <= 8 && abs(p[1] - 90) <= 8 && p[2] <= 8, "indexed: pixel %d %d %d", p[0], p[1], p[2]);
                CGContextRelease(ctx);
                CGColorSpaceRelease(space);
                CGImageRelease(image);
            }
        }

        // NSImage reads the same data, as one bitmap representation
        {
            NSData *data = makePSD(W, H, 3, 3, 1, rgb, NULL);
            NSImage *image = [[NSImage alloc] initWithData: data];
            CHECK(image != nil, "NSImage: nil");
            if (image != nil) {
                CHECK([image size].width == W && [image size].height == H, "NSImage: size %g x %g", [image size].width,
                      [image size].height);
                CHECK([[image representations] count] == 1 &&
                              [[[image representations] objectAtIndex: 0] isKindOfClass: [NSBitmapImageRep class]],
                      "NSImage: representations %lu", (unsigned long) [[image representations] count]);
            }
            [image release];
        }

        // a document that ends inside the header or has no channels gives no usable image
        {
            NSData *good = makePSD(W, H, 3, 3, 0, rgb, NULL);
            NSMutableData *bad = [NSMutableData dataWithData: good];
            ((unsigned char *) [bad mutableBytes])[13] = 0; // 0 channels
            NSData *cases[] = {[good subdataWithRange: NSMakeRange(0, 26)], bad};
            const char *names[] = {"header only", "zero channels"};
            for (int i = 0; i < 2; i++) {
                CGImageSourceRef src = CGImageSourceCreateWithData((CFDataRef) cases[i], NULL);
                CGImageRef image = src != NULL && CGImageSourceGetCount(src) > 0
                                           ? CGImageSourceCreateImageAtIndex(src, 0, NULL)
                                           : NULL;
                CHECK(image == NULL, "%s: got an image", names[i]);
                if (image != NULL)
                    CGImageRelease(image);
                if (src != NULL)
                    CFRelease(src);
            }
        }

        // the type identifier is listed
        {
            CFArrayRef ids = CGImageSourceCopyTypeIdentifiers();
            CHECK(CFArrayContainsValue(ids, CFRangeMake(0, CFArrayGetCount(ids)), CFSTR("com.adobe.photoshop-image")),
                  "type identifier not listed");
            CFRelease(ids);
        }
    }
    if (failures == 0)
        printf("photoshop image source: PASS\n");
    return failures != 0;
}
