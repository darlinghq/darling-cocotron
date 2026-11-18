// Copyright (C) 2026 Lubos Dolezel

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define SYM(n) dlsym(RTLD_DEFAULT, n)

typedef CGImageRef (*ArrFn)(CGRect, CFArrayRef, uint32_t);

int main(void) {
    ArrFn fromArray = (ArrFn) SYM("CGWindowListCreateImageFromArray");
    CHECK(fromArray != NULL);
    if (!fromArray) { printf("FAILED\n"); return 1; }

    // No windows: a fully transparent image of the requested size.
    CFArrayRef none = CFArrayCreate(NULL, NULL, 0, NULL);
    CGImageRef img = fromArray(CGRectMake(0, 0, 16, 16), none, 0);
    CHECK(img != NULL);
    if (img) {
        CHECK(CGImageGetWidth(img) == 16 && CGImageGetHeight(img) == 16);
        uint8_t px[16 * 16 * 4];
        memset(px, 0xff, sizeof(px));
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(px, 16, 16, 8, 16 * 4, rgb,
                kCGImageAlphaPremultipliedLast);
        CGContextClearRect(ctx, CGRectMake(0, 0, 16, 16));
        CGContextDrawImage(ctx, CGRectMake(0, 0, 16, 16), img);
        int nonzero = 0;
        for (size_t i = 3; i < sizeof(px); i += 4)
            nonzero += px[i] != 0;
        CHECK(nonzero == 0);
    }
    // A window that does not exist yields no image.
    CGWindowID bad = 0x7ffffff0;
    CFArrayRef missing = CFArrayCreate(NULL, (const void **) &bad, 1, NULL);
    CHECK(fromArray(CGRectMake(0, 0, 16, 16), missing, 0) == NULL);
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
