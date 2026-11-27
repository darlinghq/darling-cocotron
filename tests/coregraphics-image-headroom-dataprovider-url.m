// Copyright (C) 2026 Lubos Dolezel
//
// CGImageGetHeadroom(image, &headroom) and CGDataProviderCreateWithURL. Expected values from macOS 26.7.3:
//  - CGImageGetHeadroom of an 8-bit RGBA bitmap image returns true and 1.0 (CGImageGetContentHeadroom of it
//    is 1.0); of NULL it returns false and stores 0;
//  - CGDataProviderCreateWithURL of a file URL gives a provider that reads the file; of NULL, a URL that is
//    not a file URL or a missing file it gives NULL.
// Build: clang -framework CoreGraphics -framework Foundation coregraphics-image-headroom-dataprovider-url.m (no ARC)
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>

// Looked up at run time: the SDK headers do not declare it (it is deprecated there).
static CGDataProviderRef (*CreateWithURL)(CFURLRef url);

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    bool (*headroom)(CGImageRef, float *) = dlsym(RTLD_DEFAULT, "CGImageGetHeadroom");
    CHECK(headroom != NULL);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 4, 4, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
    CGImageRef image = CGBitmapContextCreateImage(context);
    if (headroom != NULL) {
        float value = -123;
        CHECK(headroom(image, &value) == true);
        CHECK(value == 1.0f);
        value = -123;
        CHECK(headroom(NULL, &value) == false);
        CHECK(value == 0.0f);
        CHECK(headroom(image, NULL) == true);
    }
    CGImageRelease(image);
    CGContextRelease(context);
    CGColorSpaceRelease(rgb);

    char path[] = "/tmp/cgdp-url-XXXXXX";
    int fd = mkstemp(path);
    CHECK(fd >= 0);
    const char text[] = "hello provider";
    CHECK(write(fd, text, sizeof text) == (ssize_t) sizeof text);
    close(fd);
    NSURL *url = [NSURL fileURLWithPath: [NSString stringWithUTF8String: path]];
    CreateWithURL = dlsym(RTLD_DEFAULT, "CGDataProviderCreateWithURL");
    CHECK(CreateWithURL != NULL);
    if (CreateWithURL == NULL)
        return 1;
    CGDataProviderRef provider = CreateWithURL((CFURLRef) url);
    CHECK(provider != NULL);
    if (provider != NULL) {
        CFDataRef data = CGDataProviderCopyData(provider);
        CHECK(data != NULL && CFDataGetLength(data) == (CFIndex) sizeof text);
        if (data != NULL) {
            CHECK(memcmp(CFDataGetBytePtr(data), text, sizeof text) == 0);
            CFRelease(data);
        }
        CGDataProviderRelease(provider);
    }
    CHECK(CreateWithURL(NULL) == NULL);
    CHECK(CreateWithURL((CFURLRef) [NSURL URLWithString: @"http://example.invalid/x"]) == NULL);
    unlink(path);
    CHECK(CreateWithURL((CFURLRef) url) == NULL);
    if (failures == 0)
        printf("PASS coregraphics-image-headroom-dataprovider-url\n");
    [pool release];
    return failures != 0;
}
