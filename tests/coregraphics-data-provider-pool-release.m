// Copyright (C) 2026 Lubos Dolezel
//
// A data provider that is released gives back what it held at once, not when the autorelease
// pool the code was running in drains: applications that create many images inside one
// long-running pool (a nib load, a loader loop) would otherwise keep every provider's data
// (and every file provider's open file) alive until the pool ends. Bitmap contexts hand out
// a copy of their pixels in a provider each time CGBitmapContextCreateImage is called.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <fcntl.h>
#include <malloc/malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

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

static size_t bytesInUse(void) {
    malloc_statistics_t stats;
    malloc_zone_statistics(NULL, &stats);
    return stats.size_in_use;
}

static int openDescriptors(void) {
    int count = 0;
    for (int fd = 0; fd < 1024; fd++) {
        if (fcntl(fd, F_GETFD) != -1)
            count++;
    }
    return count;
}

int main(void) {
    @autoreleasepool {
        enum { Rounds = 20, Size = 4 << 20 };
        static char pixels[Size];
        const size_t limit = 3 * (size_t) Size;

        // Providers of CFData, released inside one pool.
        size_t before = bytesInUse();
        for (int i = 0; i < Rounds; i++) {
            NSData *data = [[NSData alloc] initWithBytes: pixels length: Size];
            CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef) data);
            CGDataProviderRelease(provider);
            [data release];
        }
        size_t grown = bytesInUse() - before;
        CHECK(grown < limit, "released CFData providers kept %zu bytes in the pool (%d x %d)", grown, Rounds, Size);

        // Images that bitmap contexts make of their pixels.
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 1024, 1024, 8, 0, space, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        CHECK(context != NULL, "bitmap context");
        before = bytesInUse();
        for (int i = 0; i < Rounds; i++) {
            CGImageRef image = CGBitmapContextCreateImage(context);
            CGImageRelease(image);
        }
        grown = bytesInUse() - before;
        CHECK(grown < limit, "released bitmap context images kept %zu bytes in the pool", grown);
        CGContextRelease(context);

        // Providers of files, released inside one pool.
        char path[] = "/tmp/provider-pool-release.XXXXXX";
        int fd = mkstemp(path);
        CHECK(fd >= 0, "temporary file");
        if (fd >= 0) {
            write(fd, pixels, 4096);
            close(fd);
            int descriptors = openDescriptors();
            for (int i = 0; i < 300; i++) {
                CGDataProviderRef provider = CGDataProviderCreateWithFilename(path);
                CHECK(provider != NULL, "file provider");
                if (provider != NULL) {
                    CFDataRef data = CGDataProviderCopyData(provider);
                    CHECK(data != NULL && CFDataGetLength(data) == 4096, "file provider data");
                    if (data != NULL)
                        CFRelease(data);
                }
                CGDataProviderRelease(provider);
            }
            int leaked = openDescriptors() - descriptors;
            CHECK(leaked < 10, "released file providers kept %d descriptors open in the pool", leaked);
            unlink(path);
        }
    }
    if (failures != 0) {
        printf("data provider pool release: FAIL (%d)\n", failures);
        return 1;
    }
    printf("data provider pool release: PASS\n");
    return 0;
}
