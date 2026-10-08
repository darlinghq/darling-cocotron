#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <ImageIO/CGImageSource.h>
#import <ImageIO/CGImageProperties.h>
#include <stdint.h>
#include <dlfcn.h>
#include <stdio.h>

#define CHECK(condition, code) do { \
    if (!(condition)) { \
        fprintf(stderr, "JPEG property check failed at line %d\n", __LINE__); \
        return code; \
    } \
} while (0)

static int numberEquals(CFDictionaryRef properties, CFStringRef key,
                        int64_t expected) {
    CFTypeRef value = CFDictionaryGetValue(properties, key);
    int64_t number;
    return value != NULL && CFGetTypeID(value) == CFNumberGetTypeID() &&
            CFNumberGetValue(value, kCFNumberSInt64Type, &number) &&
            number == expected;
}

int main(int argc, const char **argv) {
    CHECK(argc == 2, 1);
    const char *names[] = { "plain.jpg", "exif.jpg", "large-header.jpg" };
    for (unsigned i = 0; i < 3; i++) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *path = [[NSString stringWithUTF8String: argv[1]]
                stringByAppendingPathComponent: [NSString stringWithUTF8String: names[i]]];
        NSData *bytes = [NSData dataWithContentsOfFile: path];
        CHECK(bytes != nil, 2);
        CGImageSourceRef source = i == 0
                ? CGImageSourceCreateWithURL((CFURLRef) [NSURL fileURLWithPath: path], NULL)
                : CGImageSourceCreateWithData((CFDataRef) bytes, NULL);
        CHECK(source != NULL, 3);
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        CHECK(properties != NULL, 4);
        int64_t dimension = i == 2 ? 60000 : 3;
        CHECK(numberEquals(properties, kCGImagePropertyPixelWidth, dimension), 5);
        CHECK(numberEquals(properties, kCGImagePropertyPixelHeight, i == 2 ? 60000 : 2), 6);
        if (i == 1)
            CHECK(numberEquals(properties, kCGImagePropertyOrientation, 6), 7);
        CHECK(CGImageSourceCopyPropertiesAtIndex(source, 1, NULL) == NULL, 8);
        CHECK(CGImageSourceCopyPropertiesAtIndex(source, SIZE_MAX, NULL) == NULL, 9);
        CFRelease(source);
        [pool drain];
        CHECK(numberEquals(properties, kCGImagePropertyPixelWidth, dimension), 10);
        CFRelease(properties);
    }

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *path = [[NSString stringWithUTF8String: argv[1]]
            stringByAppendingPathComponent: @"malformed.jpg"];
    NSData *malformed = [NSData dataWithContentsOfFile: path];
    CHECK(malformed != nil, 11);
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
    path = [[NSString stringWithUTF8String: argv[1]]
            stringByAppendingPathComponent: @"soi-only.jpg"];
    NSData *soi = [NSData dataWithContentsOfFile: path];
    CHECK(soi != nil, 22);
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
