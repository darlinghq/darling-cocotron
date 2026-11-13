#import <Foundation/NSAutoreleasePool.h>
#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGImage.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    void *bytes;
    size_t size;
    unsigned calls;
    int argumentsMatch;
} ReleaseRecord;

static void releaseBytes(void *info, const void *data, size_t size) {
    ReleaseRecord *record = info;
    record->calls++;
    record->argumentsMatch = data == record->bytes && size == record->size;
    memset(record->bytes, 0xee, record->size);
    free(record->bytes);
}

#define CHECK(condition, code) do { \
    if (!(condition)) { \
        fprintf(stderr, "data-provider check failed at line %d\n", __LINE__); \
        return code; \
    } \
} while (0)

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const unsigned char expected[] = { 0x12, 0x00, 0x34, 0xff };
    ReleaseRecord record = { malloc(sizeof(expected)), sizeof(expected), 0, 0 };
    CHECK(record.bytes != NULL, 1);
    memcpy(record.bytes, expected, sizeof(expected));
    CGDataProviderRef provider = CGDataProviderCreateWithData(
            &record, record.bytes, record.size, releaseBytes);
    CHECK(provider != NULL, 2);
    CFDataRef snapshot = CGDataProviderCopyData(provider);
    CHECK(snapshot != NULL && CFDataGetLength(snapshot) == sizeof(expected), 3);
    CHECK(memcmp(CFDataGetBytePtr(snapshot), expected, sizeof(expected)) == 0, 4);
    CHECK(CGDataProviderRetain(provider) == provider, 6);
    CGDataProviderRelease(provider);
    CHECK(record.calls == 0, 7);
    CGDataProviderRelease(provider);
    CHECK(record.calls == 1 && record.argumentsMatch, 8);
    [pool drain];
    CHECK(record.calls == 1, 9);
    CHECK(memcmp(CFDataGetBytePtr(snapshot), expected, sizeof(expected)) == 0, 10);
    CFRelease(snapshot);

    pool = [[NSAutoreleasePool alloc] init];
    ReleaseRecord pixel = { malloc(4), 4, 0, 0 };
    CHECK(pixel.bytes != NULL, 11);
    memcpy(pixel.bytes, expected, 4);
    provider = CGDataProviderCreateWithData(&pixel, pixel.bytes, 4, releaseBytes);
    CHECK(provider != NULL, 12);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CHECK(space != NULL, 13);
    CGImageRef image = CGImageCreate(1, 1, 8, 32, 4, space,
            kCGImageAlphaPremultipliedLast, provider, NULL, false,
            kCGRenderingIntentDefault);
    CHECK(image != NULL, 14);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    CHECK(pixel.calls == 0, 15);
    CGImageRelease(image);
    CHECK(pixel.calls == 1 && pixel.argumentsMatch, 16);
    [pool drain];
    CHECK(pixel.calls == 1, 17);

    pool = [[NSAutoreleasePool alloc] init];
    provider = CGDataProviderCreateWithData(NULL, expected, sizeof(expected), NULL);
    CHECK(provider != NULL, 18);
    snapshot = CGDataProviderCopyData(provider);
    CGDataProviderRelease(provider);
    CHECK(snapshot != NULL && CFDataGetLength(snapshot) == sizeof(expected), 19);
    CHECK(memcmp(CFDataGetBytePtr(snapshot), expected, sizeof(expected)) == 0, 20);
    CFRelease(snapshot);
    [pool drain];
    puts("data-provider snapshot and callback lifetime passed");
    return 0;
}
