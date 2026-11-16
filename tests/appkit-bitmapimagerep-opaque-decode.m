// Copyright (C) 2026 Lubos Dolezel
//
// A picture without an alpha channel decodes to a bitmap without alpha:
//  - TIFF with 3 samples per pixel (RGB) gives 3 samples, 24 bits per pixel, rows of 3 * width bytes;
//    TIFF with 1 sample per pixel (gray) gives 1 sample, 8 bits per pixel;
//  - PNG and JPEG without alpha give 3 samples with 32 bits per pixel (a padding byte), rows of
//    4 * width bytes;
//  - pictures with an alpha channel keep 4 samples and hasAlpha.
// macOS 10.14.4 (black-box observation) gives exactly these layouts; the colors are compared with
// tolerance since encoders and color management change them a little.
#import <AppKit/AppKit.h>
#import <objc/message.h>
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

enum { W = 16, H = 8 };

static BOOL near(CGFloat a, int b, int tolerance) {
    int v = (int) (a * 255 + 0.5);
    return v - b <= tolerance && b - v <= tolerance;
}

// Creates a bitmap of the given layout. The BOOL arguments of the initializer are passed as full
// words through a cast message send: a 1 byte BOOL stored in a stack argument slot is not
// widened by the compiler this test is cross-built with, and macOS 10.14.4's initializer
// sometimes read garbage from the rest of the slot and refused the call ("Inconsistent set of
// values"), which made results depend on the stack contents.
static NSBitmapImageRep *newBitmap(long width, long height, long samples, long alpha, NSString *space) {
    typedef id (*InitFunction)(id, SEL, unsigned char **, long, long, long, long, long, long, NSString *, long, long);
    return ((InitFunction) objc_msgSend)([NSBitmapImageRep alloc],
                                         @selector(initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:),
                                         NULL, width, height, 8, samples, alpha, 0, space, 0, samples * 8);
}

// Left half red, right half blue (gray: dark and light), fully opaque.
static NSBitmapImageRep *makeSource(int samples, BOOL alpha, NSString *space) {
    NSBitmapImageRep *rep = newBitmap(W, H, samples, alpha, space);
    unsigned char *data = [rep bitmapData];
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            unsigned char *px = data + y * [rep bytesPerRow] + x * samples;
            if (samples >= 3) {
                px[0] = x < W / 2 ? 255 : 0;
                px[1] = 0;
                px[2] = x < W / 2 ? 0 : 255;
            } else {
                px[0] = x < W / 2 ? 40 : 200;
            }
            if (alpha)
                px[samples - 1] = 255;
        }
    return rep;
}

// A little-endian TIFF with one 8 bit gray sample per pixel (BlackIsZero, one uncompressed strip),
// built by hand: the encoder is not what is under test here.
static NSData *grayTIFF(void) {
    NSMutableData *data = [NSMutableData data];
    unsigned char header[8] = {'I', 'I', 42, 0, 8, 0, 0, 0};
    [data appendBytes: header length: 8];
    // tag, type (3 SHORT, 4 LONG), count, value
    unsigned entries[][4] = {{256, 3, 1, W}, {257, 3, 1, H}, {258, 3, 1, 8}, {259, 3, 1, 1}, {262, 3, 1, 1},
                             {273, 4, 1, 8 + 2 + 9 * 12 + 4}, {277, 3, 1, 1}, {278, 3, 1, H}, {279, 4, 1, W * H}};
    unsigned short count = 9;
    [data appendBytes: &count length: 2];
    for (int i = 0; i < 9; i++) {
        unsigned short tag = entries[i][0], type = entries[i][1];
        unsigned n = entries[i][2], value = entries[i][3];
        [data appendBytes: &tag length: 2];
        [data appendBytes: &type length: 2];
        [data appendBytes: &n length: 4];
        [data appendBytes: &value length: 4];
    }
    unsigned next = 0;
    [data appendBytes: &next length: 4];
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            unsigned char v = x < W / 2 ? 40 : 200;
            [data appendBytes: &v length: 1];
        }
    return data;
}

static void checkLayout(const char *name, NSBitmapImageRep *rep, NSInteger samples, NSInteger bitsPerPixel, BOOL alpha, NSInteger rowBytes) {
    CHECK(rep != nil, "%s: no bitmap", name);
    if (rep == nil)
        return;
    CHECK([rep samplesPerPixel] == samples, "%s: samples per pixel %ld, expected %ld", name, (long) [rep samplesPerPixel], (long) samples);
    CHECK([rep bitsPerSample] == 8, "%s: bits per sample %ld", name, (long) [rep bitsPerSample]);
    CHECK([rep bitsPerPixel] == bitsPerPixel, "%s: bits per pixel %ld, expected %ld", name, (long) [rep bitsPerPixel], (long) bitsPerPixel);
    CHECK([rep hasAlpha] == alpha, "%s: hasAlpha %d", name, (int) [rep hasAlpha]);
    CHECK([rep bytesPerRow] == rowBytes, "%s: bytes per row %ld, expected %ld", name, (long) [rep bytesPerRow], (long) rowBytes);
    CHECK(![rep isPlanar], "%s: planar", name);
    CHECK([rep bitmapFormat] == 0, "%s: bitmap format 0x%lx", name, (unsigned long) [rep bitmapFormat]);
    CHECK([rep pixelsWide] == W && [rep pixelsHigh] == H, "%s: size %ldx%ld", name, (long) [rep pixelsWide], (long) [rep pixelsHigh]);
}

static void checkRedBlue(const char *name, NSBitmapImageRep *rep, int tolerance) {
    if (rep == nil)
        return;
    NSColor *left = [[rep colorAtX: 2 y: 3] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    NSColor *right = [[rep colorAtX: W - 3 y: 3] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    CHECK(near([left redComponent], 255, tolerance) && near([left greenComponent], 0, tolerance) && near([left blueComponent], 0, tolerance),
          "%s: left pixel %g %g %g", name, [left redComponent], [left greenComponent], [left blueComponent]);
    CHECK(near([right redComponent], 0, tolerance) && near([right greenComponent], 0, tolerance) && near([right blueComponent], 255, tolerance),
          "%s: right pixel %g %g %g", name, [right redComponent], [right greenComponent], [right blueComponent]);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSBitmapImageRep *rgb = makeSource(3, NO, NSDeviceRGBColorSpace);
        NSBitmapImageRep *rgba = makeSource(4, YES, NSDeviceRGBColorSpace);
        
        // TIFF
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData: [rgb TIFFRepresentation]];
        checkLayout("rgb tiff", rep, 3, 24, NO, W * 3);
        checkRedBlue("rgb tiff", rep, 6);
        if (rep != nil) {
            // the bytes are R, G, B per pixel
            const unsigned char *d = [rep bitmapData];
            const unsigned char *left = d + 3 * [rep bytesPerRow] + 2 * 3, *right = d + 3 * [rep bytesPerRow] + (W - 3) * 3;
            CHECK(near(left[0] / 255.0, 255, 6) && left[1] < 6 && left[2] < 6, "rgb tiff left bytes %d %d %d", left[0], left[1], left[2]);
            CHECK(right[0] < 6 && right[1] < 6 && near(right[2] / 255.0, 255, 6), "rgb tiff right bytes %d %d %d", right[0], right[1], right[2]);
        }
        rep = [NSBitmapImageRep imageRepWithData: grayTIFF()];
        checkLayout("gray tiff", rep, 1, 8, NO, W);
        if (rep != nil)
            CHECK([rep bitmapData][3] == 40 && [rep bitmapData][W - 3] == 200, "gray tiff bytes %d %d", [rep bitmapData][3], [rep bitmapData][W - 3]);
        rep = [NSBitmapImageRep imageRepWithData: [rgba TIFFRepresentation]];
        checkLayout("rgba tiff", rep, 4, 32, YES, W * 4);
        checkRedBlue("rgba tiff", rep, 6);

        // The image of an opaque picture drawn onto a bitmap keeps its pixels.
        NSImage *image = [[NSImage alloc] initWithData: [rgb TIFFRepresentation]];
        NSBitmapImageRep *target = newBitmap(W, H, 4, YES, NSDeviceRGBColorSpace);
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: target]];
        [image drawInRect: NSMakeRect(0, 0, W, H)];
        [NSGraphicsContext restoreGraphicsState];
        checkRedBlue("drawn rgb tiff", target, 8);
        CHECK([[target colorAtX: 2 y: 3] alphaComponent] > 0.99, "drawn rgb tiff is not opaque");

        // PNG
        rep = [NSBitmapImageRep imageRepWithData: [rgb representationUsingType: NSPNGFileType properties: @{}]];
        checkLayout("rgb png", rep, 3, 32, NO, W * 4);
        checkRedBlue("rgb png", rep, 8);
        rep = [NSBitmapImageRep imageRepWithData: [rgba representationUsingType: NSPNGFileType properties: @{}]];
        CHECK(rep != nil && [rep samplesPerPixel] == 4 && [rep hasAlpha] && [rep bitsPerPixel] == 32, "rgba png layout");
        checkRedBlue("rgba png", rep, 8);

        // JPEG
        rep = [NSBitmapImageRep imageRepWithData: [rgb representationUsingType: NSJPEGFileType
                                                                    properties: @{NSImageCompressionFactor: @1.0}]];
        checkLayout("rgb jpeg", rep, 3, 32, NO, W * 4);
        checkRedBlue("rgb jpeg", rep, 40);

        [target release];
        [image release];
        [rgb release];
        [rgba release];
    }
    if (failures == 0)
        printf("opaque picture decode: PASS\n");
    return failures != 0;
}
