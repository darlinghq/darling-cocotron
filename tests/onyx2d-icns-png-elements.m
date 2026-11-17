// Copyright (C) 2026 Lubos Dolezel
//
// An .icns file whose elements hold PNG images (the ic07 to ic14 types of current icon files) decodes
// through ImageIO and NSImage: one image per element, listed from the largest to the smallest in pixels.
// Checked on macOS 10.14.4 and 26.7.3 (vd-upstream mac-probes/ua7-icns-png.m); both list the same order.
//
// Build: clang -fobjc-arc -framework AppKit -framework ImageIO onyx2d-icns-png-elements.m
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSData *pngOfSide(int side) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, side, side, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, side, side));
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    NSData *png = [[[NSBitmapImageRep alloc] initWithCGImage:image] representationUsingType:NSPNGFileType properties:@{}];
    CGImageRelease(image);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    return png;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        struct { const char *type; int pixels; } elements[] = {
            {"ic12", 64}, {"ic07", 128}, {"ic11", 32}, {"ic13", 256}, {"ic08", 256}, {"ic10", 1024}};
        NSMutableData *body = [NSMutableData data];
        for (int i = 0; i < 6; i++) {
            NSData *png = pngOfSide(elements[i].pixels);
            uint32_t length = (uint32_t)[png length] + 8;
            unsigned char header[8] = {elements[i].type[0], elements[i].type[1], elements[i].type[2], elements[i].type[3],
                                       length >> 24, length >> 16, length >> 8, length};
            [body appendBytes:header length:8];
            [body appendData:png];
        }
        NSMutableData *file = [NSMutableData data];
        uint32_t total = (uint32_t)[body length] + 8;
        unsigned char header[8] = {'i', 'c', 'n', 's', total >> 24, total >> 16, total >> 8, total};
        [file appendBytes:header length:8];
        [file appendData:body];

        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)file, NULL);
        CHECK(source != NULL);
        CHECK(source != NULL && CGImageSourceGetCount(source) == 6);
        size_t expected[6] = {1024, 256, 256, 128, 64, 32};
        for (size_t i = 0; source != NULL && i < CGImageSourceGetCount(source) && i < 6; i++) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
            CHECK(image != NULL && CGImageGetWidth(image) == expected[i] && CGImageGetHeight(image) == expected[i]);
            CGImageRelease(image);
        }

        NSImage *image = [[NSImage alloc] initWithData:file];
        CHECK(image != nil);
        CHECK([[image representations] count] == 6);
        CHECK([image size].width >= 256);

        // Truncated and corrupt data is not a crash.
        (void)[[NSImage alloc] initWithData:[file subdataWithRange:NSMakeRange(0, 40)]];
        NSMutableData *corrupt = [file mutableCopy];
        [corrupt resetBytesInRange:NSMakeRange(8, 8 + 16)];
        (void)[[NSImage alloc] initWithData:corrupt];
        if (source != NULL) CFRelease(source);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
