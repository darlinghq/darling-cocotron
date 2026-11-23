// Decoding a JPEG that libjpeg rejects must fail cleanly through ImageIO:
// CGImageSourceCopyPropertiesAtIndex and CGImageSourceCreateImageAtIndex both
// return NULL and the process keeps running. The failure path of the decoder
// used to release a pixel buffer it never allocated and crashed. A valid JPEG
// still decodes to the documented size and pixel values afterwards.
#include <ImageIO/ImageIO.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

// A complete baseline JPEG, 3x2 pixels, one component, uniform grey 0x50
// (checked with djpeg: PGM maxval 255, every sample 0x50).
static const unsigned char kGreyJPEG[] = {
    0xff, 0xd8, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x03, 0x02, 0x02, 0x03, 0x02,
    0x02, 0x03, 0x03, 0x03, 0x03, 0x04, 0x03, 0x03, 0x04, 0x05, 0x08, 0x05,
    0x05, 0x04, 0x04, 0x05, 0x0a, 0x07, 0x07, 0x06, 0x08, 0x0c, 0x0a, 0x0c,
    0x0c, 0x0b, 0x0a, 0x0b, 0x0b, 0x0d, 0x0e, 0x12, 0x10, 0x0d, 0x0e, 0x11,
    0x0e, 0x0b, 0x0b, 0x10, 0x16, 0x10, 0x11, 0x13, 0x14, 0x15, 0x15, 0x15,
    0x0c, 0x0f, 0x17, 0x18, 0x16, 0x14, 0x18, 0x12, 0x14, 0x15, 0x14, 0xff,
    0xc0, 0x00, 0x0b, 0x08, 0x00, 0x02, 0x00, 0x03, 0x01, 0x01, 0x11, 0x00,
    0xff, 0xc4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0xff, 0xc4,
    0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xda, 0x00, 0x08,
    0x01, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x3f, 0xbf, 0xff, 0xd9,
};

// Start of image and end of image with nothing between them: libjpeg reports
// that the datastream contains no image.
static const unsigned char kNoImage[] = { 0xff, 0xd8, 0xff, 0xd9 };

// Runs the properties and the image calls on corrupt data; both must fail.
static void checkRejected(const char *name, const unsigned char *bytes, size_t length) {
    CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex) length);
    CGImageSourceRef source = CGImageSourceCreateWithData(data, NULL);
    CHECK(source != NULL, name);
    if (source != NULL) {
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        CHECK(properties == NULL, name);
        if (properties != NULL)
            CFRelease(properties);
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CHECK(image == NULL, name);
        if (image != NULL)
            CGImageRelease(image);
        // A second attempt on the same source must fail the same way.
        image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CHECK(image == NULL, name);
        if (image != NULL)
            CGImageRelease(image);
        CFRelease(source);
    }
    CFRelease(data);
    printf("%s: rejected without crashing\n", name);
    fflush(stdout);
}

int main(void) {
    checkRejected("no image (SOI, EOI)", kNoImage, sizeof(kNoImage));
    // The valid file cut inside its first Huffman table: no complete header. macOS 10.14.4 gives no
    // properties and no image for it; 26.7.3 gives the properties of the part it could parse but no image.
    checkRejected("header truncated at 100 bytes", kGreyJPEG, 100);

    CFDataRef data = CFDataCreate(NULL, kGreyJPEG, sizeof(kGreyJPEG));
    CGImageSourceRef source = CGImageSourceCreateWithData(data, NULL);
    CHECK(source != NULL, "valid source");
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    CHECK(image != NULL, "valid image");
    if (image != NULL) {
        CHECK(CGImageGetWidth(image) == 3, "width");
        CHECK(CGImageGetHeight(image) == 2, "height");
        CFDataRef pixels = CGDataProviderCopyData(CGImageGetDataProvider(image));
        CHECK(pixels != NULL, "pixel data");
        if (pixels != NULL) {
            size_t rowBytes = CGImageGetBytesPerRow(image);
            size_t pixelBytes = CGImageGetBitsPerPixel(image) / 8;
            // A grey JPEG decodes to one grey component per pixel on macOS (8 bits per pixel on 10.14.4 and
            // 26.7.3); an RGB layout carries the grey in all three colour components.
            size_t colorBytes = pixelBytes >= 3 ? 3 : 1;
            CHECK(pixelBytes >= 1 && CFDataGetLength(pixels) >= (CFIndex) (rowBytes + 3 * pixelBytes),
                  "pixel layout");
            const unsigned char *p = CFDataGetBytePtr(pixels);
            for (size_t y = 0; y < 2 && pixelBytes >= 1; y++) {
                for (size_t x = 0; x < 3; x++) {
                    const unsigned char *px = p + y * rowBytes + x * pixelBytes;
                    for (size_t c = 0; c < colorBytes; c++)
                        CHECK(px[c] == 0x50, "grey pixel value");
                }
            }
            CFRelease(pixels);
        }
        CGImageRelease(image);
    }
    if (source != NULL)
        CFRelease(source);
    CFRelease(data);

    if (failures == 0)
        puts("PASS corrupt JPEG decode fails cleanly, valid JPEG decodes");
    return failures != 0;
}
