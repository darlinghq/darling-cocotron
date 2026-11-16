/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSPICTImageRep reads QuickDraw pictures (PICT version 2): it recognizes picture data with or
// without the 512 byte file header, NSImage and NSImageRep pick it for such data, and the
// bitmaps of the picture (16 and 32 bit direct pixels, 8 bit indexed pixels) are drawn.
// The pictures are built here from the format's documented layout. The expectations were
// checked on macOS 10.14 (Mojave, x86_64), where the class is the same. Mojave color manages
// the colors of a picture when it draws them, which moves saturated colors (a pure red comes
// out as 255, 37, 0), and its 5-bit to 8-bit scaling differs from ours by at most one level in
// some pixels. So the checks are on gray pixels, which keep their value, on the dominant
// channel of saturated colors and, for mid-tone colors, with a tolerance.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static void put16(NSMutableData *d, unsigned v) {
    unsigned char b[2] = {(unsigned char) (v >> 8), (unsigned char) v};
    [d appendBytes: b length: 2];
}

static void put32(NSMutableData *d, unsigned v) {
    put16(d, v >> 16);
    put16(d, v & 0xffff);
}

static void putRect(NSMutableData *d, int t, int l, int b, int r) {
    put16(d, t);
    put16(d, l);
    put16(d, b);
    put16(d, r);
}

// PackBits with one run per call: a literal run of `count` units or a repeated unit.
static void packLiteral(NSMutableData *d, const unsigned char *units, int count, int unit) {
    unsigned char n = (unsigned char) (count - 1);
    [d appendBytes: &n length: 1];
    [d appendBytes: units length: count * unit];
}

static void packRepeat(NSMutableData *d, const unsigned char *unitBytes, int count, int unit) {
    unsigned char n = (unsigned char) (1 - count);
    [d appendBytes: &n length: 1];
    [d appendBytes: unitBytes length: unit];
}

static NSMutableData *pictHeader(int width, int height) {
    NSMutableData *d = [NSMutableData data];

    put16(d, 0); // picture size, not used by version 2
    putRect(d, 0, 0, height, width);
    put16(d, 0x0011); // version opcode
    put16(d, 0x02ff);
    put16(d, 0x0c00); // header opcode
    put16(d, 0xfffe); // extended version 2
    put16(d, 0);
    put32(d, 72 << 16); // horizontal resolution
    put32(d, 72 << 16);
    putRect(d, 0, 0, height, width);
    put32(d, 0);
    put16(d, 0x001e); // DefHilite
    put16(d, 0x0001); // Clip, a rectangular region
    put16(d, 10);
    putRect(d, 0, 0, height, width);
    return d;
}

static void putPixMap(NSMutableData *d, int rowBytes, int width, int height, int packType,
                      int pixelSize, int cmpCount, int cmpSize) {
    put16(d, 0x8000 | rowBytes);
    putRect(d, 0, 0, height, width);
    put16(d, 0); // pixMap version
    put16(d, packType);
    put32(d, 0); // packed size
    put32(d, 72 << 16);
    put32(d, 72 << 16);
    put16(d, pixelSize >= 16 ? 0x10 : 0); // chunky RGB direct or indexed
    put16(d, pixelSize);
    put16(d, cmpCount);
    put16(d, cmpSize);
    put32(d, 0);
    put32(d, 0);
    put32(d, 0);
}

static NSData *finish(NSMutableData *d, BOOL withFileHeader) {
    put16(d, 0x00ff); // EndPic
    NSMutableData *result = [NSMutableData data];

    if (withFileHeader)
        [result appendData: [NSMutableData dataWithLength: 512]];
    [result appendData: d];
    return result;
}

// 4x2 pixels of 1-5-5-5: the top row is red, green, blue, white, the bottom row gray (16 of 31)
static NSData *directPicture16(BOOL withFileHeader) {
    NSMutableData *d = pictHeader(4, 2);

    put16(d, 0x009a);
    put32(d, 0xff); // base address
    putPixMap(d, 8, 4, 2, 3, 16, 3, 5);
    putRect(d, 0, 0, 2, 4);
    putRect(d, 0, 0, 2, 4);
    put16(d, 0); // copy
    static const unsigned char top[] = {0x7c, 0x00, 0x03, 0xe0, 0x00, 0x1f, 0x7f, 0xff};
    static const unsigned char gray[] = {0x42, 0x10};

    // a row is its length, then PackBits runs of two byte pixels
    NSMutableData *packed = [NSMutableData data];
    packLiteral(packed, top, 4, 2);
    unsigned char len = (unsigned char) [packed length];
    [d appendBytes: &len length: 1];
    [d appendData: packed];
    packed = [NSMutableData data];
    packRepeat(packed, gray, 4, 2);
    len = (unsigned char) [packed length];
    [d appendBytes: &len length: 1];
    [d appendData: packed];
    return finish(d, withFileHeader);
}

// 4x2 pixels of 32-bit RGB, stored as one plane per component in every row: grays on top
// (16, 86, 156, 226) and a mid-tone brown (200, 100, 50) below
static NSData *directPicture32(void) {
    NSMutableData *d = pictHeader(4, 2);

    put16(d, 0x009a);
    put32(d, 0xff);
    putPixMap(d, 16, 4, 2, 4, 32, 3, 8);
    putRect(d, 0, 0, 2, 4);
    putRect(d, 0, 0, 2, 4);
    put16(d, 0);
    for (int y = 0; y < 2; y++) {
        // red plane, green plane, blue plane
        unsigned char planes[12];

        for (int x = 0; x < 4; x++) {
            planes[x] = (unsigned char) (y ? 200 : 16 + x * 70);
            planes[4 + x] = (unsigned char) (y ? 100 : 16 + x * 70);
            planes[8 + x] = (unsigned char) (y ? 50 : 16 + x * 70);
        }
        NSMutableData *packed = [NSMutableData data];

        packLiteral(packed, planes, 12, 1);
        unsigned char len = (unsigned char) [packed length];
        [d appendBytes: &len length: 1];
        [d appendData: packed];
    }
    return finish(d, NO);
}

// 8x2 pixels of 8-bit indexes into a table of white, mid-gray and black
static NSData *indexedPicture(void) {
    NSMutableData *d = pictHeader(8, 2);

    put16(d, 0x0098);
    putPixMap(d, 8, 8, 2, 0, 8, 1, 8);
    put32(d, 0); // color table seed
    put16(d, 0); // flags
    put16(d, 2); // three entries
    static const unsigned short palette[3][3] = {
        {0xffff, 0xffff, 0xffff}, {0x8000, 0x8000, 0x8000}, {0x0000, 0x0000, 0x0000}};
    for (int i = 0; i < 3; i++) {
        put16(d, i);
        put16(d, palette[i][0]);
        put16(d, palette[i][1]);
        put16(d, palette[i][2]);
    }
    putRect(d, 0, 0, 2, 8);
    putRect(d, 0, 0, 2, 8);
    put16(d, 0);
    static const unsigned char row0[] = {0, 0, 0, 0, 1, 1, 1, 1};
    static const unsigned char row1[] = {2, 2, 2, 2, 2, 2, 2, 0};
    const unsigned char *rows[2] = {row0, row1};

    for (int y = 0; y < 2; y++) {
        NSMutableData *packed = [NSMutableData data];

        // four of one index as a run, then the rest as a literal run
        if (y == 0) {
            packRepeat(packed, rows[y], 4, 1);
            packRepeat(packed, rows[y] + 4, 4, 1);
        } else {
            packRepeat(packed, rows[y], 7, 1);
            packLiteral(packed, rows[y] + 7, 1, 1);
        }
        unsigned char len = (unsigned char) [packed length];
        [d appendBytes: &len length: 1];
        [d appendData: packed];
    }
    return finish(d, NO);
}

// The picture drawn at its own size into the top left corner of a 16x16 bitmap context: pixels as
// red, green, blue, alpha bytes. (An NSBitmapImageRep made here with its own pixels could not
// be made on macOS 10.14 in a process that did not load certain other frameworks, so a
// Core Graphics bitmap context is used.)
static unsigned char renderPixels[16 * 16 * 4];

static const unsigned char *render(NSData *pict, int width, int height) {
    NSImage *image = [[NSImage alloc] initWithData: pict];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    memset(renderPixels, 0, sizeof(renderPixels));
    CGContextRef context = CGBitmapContextCreate(renderPixels, 16, 16, 8, 16 * 4, space,
                                                 kCGImageAlphaPremultipliedLast);
    expect(context != NULL, "a bitmap context can be made to draw into");
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithGraphicsPort: context
                                                                                     flipped: NO]];
    [image drawInRect: NSMakeRect(0, 16 - height, width, height)
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    [image release];
    return renderPixels;
}

// A saturated color: the given channel (0 red, 1 green, 2 blue) is well above the other two.
static BOOL pixelDominantIs(const unsigned char *bitmap, int x, int y, int channel) {
    const unsigned char *p = bitmap + y * 16 * 4 + x * 4;

    for (int c = 0; c < 3; c++) {
        if (c != channel && p[channel] < p[c] + 100)
            return NO;
    }
    return p[3] == 255;
}

static BOOL pixelIs(const unsigned char *bitmap, int x, int y, int r, int g, int b) {
    const unsigned char *p = bitmap + y * 16 * 4 + x * 4;

    return abs(p[0] - r) <= 2 && abs(p[1] - g) <= 2 && abs(p[2] - b) <= 2 && p[3] == 255;
}

int main(void) {
    @autoreleasepool {
        NSData *withHeader = directPicture16(YES);
        NSData *bare = directPicture16(NO);

        // recognition and class selection
        expect([NSPICTImageRep canInitWithData: withHeader], "a picture with the file header is recognized");
        expect([NSPICTImageRep canInitWithData: bare], "a picture without the file header is recognized");
        expect(![NSPICTImageRep canInitWithData: [@"plain text, not a picture at all" dataUsingEncoding: NSASCIIStringEncoding]],
               "other data is not recognized");
        expect(![NSPICTImageRep canInitWithData: [NSData data]], "empty data is not recognized");
        expect([NSImageRep imageRepClassForData: withHeader] == [NSPICTImageRep class],
               "NSImageRep picks NSPICTImageRep for picture data");
        expect([[NSImageRep registeredImageRepClasses] containsObject: [NSPICTImageRep class]],
               "NSPICTImageRep is a registered image rep class");
        expect([[NSPICTImageRep imageUnfilteredFileTypes] containsObject: @"pict"] &&
                       [[NSPICTImageRep imageUnfilteredFileTypes] containsObject: @"pct"] &&
                       [[NSPICTImageRep imageUnfilteredFileTypes] containsObject: @"pic"],
               "the picture file name extensions are listed");
        expect([[NSImage imageTypes] containsObject: @"com.apple.pict"], "NSImage lists the picture type");
        expect([[NSPICTImageRep imageUnfilteredPasteboardTypes] containsObject: NSPICTPboardType],
               "the picture pasteboard type is listed");
        expect([NSPICTImageRep imageRepWithData: [@"hello world" dataUsingEncoding: NSASCIIStringEncoding]] == nil,
               "data that is not a picture gives no representation");

        // the representation
        NSPICTImageRep *rep = [NSPICTImageRep imageRepWithData: withHeader];
        expect(rep != nil, "a representation is made from a picture with the file header");
        expect(NSEqualRects([rep boundingBox], NSMakeRect(0, 0, 4, 2)), "the bounding box is the picture frame");
        expect(NSEqualSizes([rep size], NSMakeSize(4, 2)), "the size is the size of the picture frame");
        expect([[rep PICTRepresentation] length] == [withHeader length] - 512,
               "the representation leaves out the file header");
        expect([[rep PICTRepresentation] isEqualToData: bare], "the representation is the picture itself");
        NSPICTImageRep *fromBare = [NSPICTImageRep imageRepWithData: bare];
        expect(fromBare != nil && [[fromBare PICTRepresentation] isEqualToData: bare],
               "a picture without the file header keeps its bytes");
        NSImage *image = [[NSImage alloc] initWithData: withHeader];
        expect(image != nil && [[[image representations] firstObject] isKindOfClass: [NSPICTImageRep class]],
               "NSImage makes a NSPICTImageRep from picture data");
        expect(image != nil && NSEqualSizes([image size], NSMakeSize(4, 2)), "NSImage has the size of the picture");
        [image release];
        NSBitmapImageRep *notBitmap = [NSBitmapImageRep imageRepWithData: withHeader];
        expect(notBitmap == nil, "NSBitmapImageRep does not read picture data");

        // drawing: 16 bit pixels (red, green, blue, white; gray)
        const unsigned char *drawn = render(withHeader, 4, 2);

        expect(pixelDominantIs(drawn, 0, 0, 0), "16 bit: red pixel");
        expect(pixelDominantIs(drawn, 1, 0, 1), "16 bit: green pixel");
        expect(pixelDominantIs(drawn, 2, 0, 2), "16 bit: blue pixel");
        expect(pixelIs(drawn, 3, 0, 255, 255, 255), "16 bit: white pixel");
        expect(pixelIs(drawn, 0, 1, 131, 131, 131), "16 bit: the second row is below the first");
        expect(pixelDominantIs(render(bare, 4, 2), 1, 0, 1), "a picture without the file header draws the same");

        // 32 bit pixels in component planes
        const unsigned char *drawn32 = render(directPicture32(), 4, 2);

        expect(pixelIs(drawn32, 0, 0, 16, 16, 16), "32 bit: first pixel of the top row");
        expect(pixelIs(drawn32, 3, 0, 226, 226, 226), "32 bit: last pixel of the top row");
        expect(pixelIs(drawn32, 2, 1, 200, 100, 50), "32 bit: the bottom row");

        // indexed pixels through the color table
        const unsigned char *drawnIndexed = render(indexedPicture(), 8, 2);

        expect(pixelIs(drawnIndexed, 0, 0, 255, 255, 255), "indexed: color 0");
        expect(pixelIs(drawnIndexed, 5, 0, 128, 128, 128), "indexed: color 1");
        expect(pixelIs(drawnIndexed, 3, 1, 0, 0, 0), "indexed: color 2");
        expect(pixelIs(drawnIndexed, 7, 1, 255, 255, 255), "indexed: the last pixel of the second row");

        // A picture that stops short of its pixels is drawn as far as it goes, without raising.
        NSData *truncated = [withHeader subdataWithRange: NSMakeRange(0, 512 + 60)];
        (void) render(truncated, 4, 2);
    }
    printf("pict image rep: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
