// Copyright (C) 2026 Lubos Dolezel
//
// CGContextSetOwnerIdentity (private, exported by CoreGraphics on macOS)
// takes a context and a task identity token. Observed on macOS 26.7.3
// x86_64: it accepts both TASK_ID_TOKEN_NULL and a token for the calling
// task, and the context keeps drawing normally afterwards.

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

typedef void (*SetOwnerFn)(CGContextRef, task_id_token_t);

int main(void) {
    SetOwnerFn setOwner = (SetOwnerFn) dlsym(RTLD_DEFAULT, "CGContextSetOwnerIdentity");
    CHECK(setOwner != NULL);
    if (!setOwner) { printf("FAILED\n"); return 1; }

    unsigned char pixels[4 * 4 * 4];
    memset(pixels, 0, sizeof(pixels));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, 4, 4, 8, 16, space,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CHECK(ctx != NULL);

    setOwner(ctx, TASK_ID_TOKEN_NULL);

    task_id_token_t token = TASK_ID_TOKEN_NULL;
    kern_return_t kr = task_create_identity_token(mach_task_self(), &token);
    CHECK(kr == KERN_SUCCESS);
    if (kr == KERN_SUCCESS)
        setOwner(ctx, token);

    // Drawing still lands in the caller's buffer.
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, 4, 4));
    CHECK(pixels[0] == 0 && pixels[1] == 0 && pixels[2] == 255 && pixels[3] == 255);

    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    if (token != TASK_ID_TOKEN_NULL)
        mach_port_deallocate(mach_task_self(), token);

    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
