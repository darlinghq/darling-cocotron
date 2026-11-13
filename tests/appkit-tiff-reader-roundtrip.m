// Copyright (C) 2026 Lubos Dolezel
//
// Decodes the data produced by -[NSBitmapImageRep TIFFRepresentation] (and
// the multi-representation form from -[NSImage TIFFRepresentation]) with
// +imageRepsWithData: and +imageRepWithData:, in images large enough that the
// reader needs several reads and seeks, and compares size and pixels. Garbage
// or truncated TIFF data must be rejected without a crash. The reader is
// driven by callbacks handed to the system libtiff; this fails when the
// callbacks do not match that library's types (as on i386).
#import <AppKit/AppKit.h>
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

static NSBitmapImageRep *makeRep(int w, int h) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL
                          pixelsWide: w
                          pixelsHigh: h
                       bitsPerSample: 8
                     samplesPerPixel: 4
                            hasAlpha: YES
                            isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace
                         bytesPerRow: w * 4
                        bitsPerPixel: 32] autorelease];
    unsigned char *d = [rep bitmapData];
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            unsigned char *p = d + y * w * 4 + x * 4;
            p[0] = (unsigned char) (x * 3);
            p[1] = (unsigned char) (y * 5);
            p[2] = (unsigned char) (x + y);
            p[3] = 255;
        }
    return rep;
}

static void checkPixels(NSBitmapImageRep *rep, int w, int h, const char *what) {
    CHECK([rep pixelsWide] == w && [rep pixelsHigh] == h,
          "%s: size %ldx%ld", what, (long) [rep pixelsWide],
          (long) [rep pixelsHigh]);
    if ([rep pixelsWide] != w || [rep pixelsHigh] != h ||
        [rep bitsPerSample] != 8 || [rep isPlanar] ||
        [rep samplesPerPixel] < 3)
        return;
    NSInteger bpp = [rep bitsPerPixel] / 8;
    int bad = 0;
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            const unsigned char *p =
                    [rep bitmapData] + y * [rep bytesPerRow] + x * bpp;
            if (p[0] != (unsigned char) (x * 3) ||
                p[1] != (unsigned char) (y * 5) ||
                p[2] != (unsigned char) (x + y))
                bad++;
        }
    CHECK(bad == 0, "%s: %d pixels differ", what, bad);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        static const int sizes[][2] = {{1, 1}, {7, 5}, {64, 48}, {300, 200}};
        for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
            int w = sizes[i][0], h = sizes[i][1];
            char what[64];
            snprintf(what, sizeof what, "%dx%d", w, h);
            NSData *tiff = [makeRep(w, h) TIFFRepresentation];
            CHECK([tiff length] > 8, "%s: no TIFF data", what);
            NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData: tiff];
            CHECK(rep != nil, "%s: not decoded", what);
            if (rep)
                checkPixels(rep, w, h, what);
            NSArray *reps = [NSBitmapImageRep imageRepsWithData: tiff];
            CHECK([reps count] == 1, "%s: %lu reps", what,
                  (unsigned long) [reps count]);
        }

        NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(40, 30)]
                autorelease];
        [image addRepresentation: makeRep(40, 30)];
        NSData *imageTIFF = [image TIFFRepresentation];
        NSImage *back = [[[NSImage alloc] initWithData: imageTIFF] autorelease];
        CHECK(back != nil, "NSImage did not decode its own TIFFRepresentation");

        // Truncated and corrupt data must fail cleanly.
        NSData *tiff = [makeRep(64, 48) TIFFRepresentation];
        NSData *cut = [tiff subdataWithRange: NSMakeRange(0, [tiff length] / 2)];
        (void) [NSBitmapImageRep imageRepWithData: cut];
        NSData *header = [tiff subdataWithRange: NSMakeRange(0, 6)];
        CHECK([NSBitmapImageRep imageRepWithData: header] == nil,
              "6-byte TIFF header decoded");
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
