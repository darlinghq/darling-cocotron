#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <ImageIO/CGImageSource.h>
#import <ImageIO/CGImageProperties.h>
#include <stdint.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition, code) do { \
    if (!(condition)) { \
        fprintf(stderr, "JPEG property check failed at line %d\n", __LINE__); \
        return code; \
    } \
} while (0)



// A complete baseline JPEG, 3x2 pixels, one component, uniform grey.
static const unsigned char kPlainJPEG[] = {
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

// An APP1 Exif segment holding one IFD0 entry: Orientation = 6 (big-endian TIFF).
static const unsigned char kExifSegment[] = {
    0xff, 0xe1, 0x00, 0x22, 'E', 'x', 'i', 'f', 0, 0,
    'M', 'M', 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08,
    0x00, 0x01, 0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x06, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
};

static NSData *plainJPEG(void) {
    return [NSData dataWithBytes: kPlainJPEG length: sizeof(kPlainJPEG)];
}

// SOI, the Exif segment, then the rest of the plain JPEG.
static NSData *exifJPEG(void) {
    NSMutableData *data = [NSMutableData dataWithBytes: kPlainJPEG length: 2];
    [data appendBytes: kExifSegment length: sizeof(kExifSegment)];
    [data appendBytes: kPlainJPEG + 2 length: sizeof(kPlainJPEG) - 2];
    return data;
}

// The plain JPEG cut after the scan header, with 60000x60000 in the frame
// header: a header without entropy data, not a complete image.
static NSData *largeHeaderJPEG(void) {
    NSMutableData *data = [NSMutableData dataWithBytes: kPlainJPEG length: sizeof(kPlainJPEG)];
    unsigned char *bytes = [data mutableBytes];
    size_t length = sizeof(kPlainJPEG);
    for (size_t i = 2; i + 4 < length;) {
        size_t segment = 2 + (bytes[i + 2] << 8 | bytes[i + 3]);
        if (bytes[i + 1] == 0xc0) {
            bytes[i + 5] = bytes[i + 7] = 60000 >> 8;
            bytes[i + 6] = bytes[i + 8] = 60000 & 0xff;
        } else if (bytes[i + 1] == 0xda) {
            [data setLength: i + segment];
            return data;
        }
        i += segment;
    }
    return nil;
}

static int numberEquals(CFDictionaryRef properties, CFStringRef key,
                        int64_t expected) {
    CFTypeRef value = CFDictionaryGetValue(properties, key);
    int64_t number;
    return value != NULL && CFGetTypeID(value) == CFNumberGetTypeID() &&
            CFNumberGetValue(value, kCFNumberSInt64Type, &number) &&
            number == expected;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *plainPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingString: @".jpg"]];
    CHECK([plainJPEG() writeToFile: plainPath atomically: NO], 2);
    NSData *images[3] = { nil, exifJPEG(), largeHeaderJPEG() };
    for (unsigned i = 0; i < 3; i++) {
        NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
        // The first image goes through a file URL, the others through data.
        CGImageSourceRef source = i == 0
                ? CGImageSourceCreateWithURL((CFURLRef) [NSURL fileURLWithPath: plainPath], NULL)
                : CGImageSourceCreateWithData((CFDataRef) images[i], NULL);
        CHECK(source != NULL, 3);
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        CHECK(properties != NULL, 4);
        CHECK(numberEquals(properties, kCGImagePropertyPixelWidth, i == 2 ? 60000 : 3), 5);
        CHECK(numberEquals(properties, kCGImagePropertyPixelHeight, i == 2 ? 60000 : 2), 6);
        if (i == 1)
            CHECK(numberEquals(properties, kCGImagePropertyOrientation, 6), 7);
        CHECK(CGImageSourceCopyPropertiesAtIndex(source, 1, NULL) == NULL, 8);
        CHECK(CGImageSourceCopyPropertiesAtIndex(source, SIZE_MAX, NULL) == NULL, 9);
        CFRelease(source);
        [inner drain];
        // The properties are owned by the caller: they outlive source and pool.
        CHECK(numberEquals(properties, kCGImagePropertyPixelWidth, i == 2 ? 60000 : 3), 10);
        CFRelease(properties);
    }
    [[NSFileManager defaultManager] removeItemAtPath: plainPath error: NULL];

    // Truncated headers: a frame header with no body, and a lone SOI marker.
    static const unsigned char kMalformed[] = { 0xff, 0xd8, 0xff, 0xc0, 0x00, 0x02 };
    static const unsigned char kSOIOnly[] = { 0xff, 0xd8 };
    NSData *malformed = [NSData dataWithBytes: kMalformed length: sizeof(kMalformed)];
    NSData *soi = [NSData dataWithBytes: kSOIOnly length: sizeof(kSOIOnly)];
    BOOL (*getDimensions)(CFDataRef, size_t *, size_t *) =
            dlsym(RTLD_DEFAULT, "O2JPEGGetDimensions");
    CHECK(getDimensions != NULL, 12);
    size_t width = 17, height = 19;
    CHECK(!getDimensions((CFDataRef) malformed, &width, &height), 12);
    CHECK(width == 17 && height == 19, 13);
    CHECK(!getDimensions(NULL, &width, &height), 14);
    CHECK(width == 17 && height == 19, 15);
    CHECK(!getDimensions((CFDataRef) malformed, NULL, &height), 18);
    CHECK(height == 19, 19);
    CHECK(!getDimensions((CFDataRef) malformed, &width, NULL), 20);
    CHECK(width == 17, 21);
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef) malformed, NULL);
    CHECK(source != NULL, 16);
    CHECK(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) == NULL, 17);
    CFRelease(source);
    CHECK(!getDimensions((CFDataRef) soi, &width, &height), 23);
    CHECK(width == 17 && height == 19, 24);
    source = CGImageSourceCreateWithData((CFDataRef) soi, NULL);
    CHECK(source != NULL, 25);
    CHECK(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) == NULL, 26);
    CFRelease(source);
    [pool drain];
    puts("JPEG header dimensions and owned properties passed");
    return 0;
}
