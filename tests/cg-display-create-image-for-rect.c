// Copyright (C) 2026 Lubos Dolezel

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define SYM(n) dlsym(RTLD_DEFAULT, n)

typedef CGImageRef (*ForRectFn)(CGDirectDisplayID, CGRect);
typedef CGImageRef (*FullFn)(CGDirectDisplayID);

// Without screen recording permission the functions return NULL; with it
// they return an image of the display (or the requested part of it).
int main(void) {
    ForRectFn forRect = (ForRectFn) SYM("CGDisplayCreateImageForRect");
    FullFn full = (FullFn) SYM("CGDisplayCreateImage");
    CHECK(forRect != NULL);
    CHECK(full != NULL);
    if (!forRect || !full) { printf("FAILED\n"); return 1; }

    CGDirectDisplayID main = CGMainDisplayID();
    CGImageRef part = forRect(main, CGRectMake(0, 0, 16, 16));
    CGImageRef whole = full(main);
    if (!CGPreflightScreenCaptureAccess()) {
        CHECK(part == NULL);
        CHECK(whole == NULL);
    } else {
        CHECK(part != NULL && CGImageGetWidth(part) > 0);
        CHECK(whole != NULL);
    }
    // Empty and non-existent regions, and unknown displays, never yield an image.
    CHECK(forRect(main, CGRectMake(0, 0, 0, 0)) == NULL);
    CHECK(forRect(main, CGRectMake(-100000, -100000, 16, 16)) == NULL);
    CHECK(forRect(0xdeadbeef, CGRectMake(0, 0, 16, 16)) == NULL);
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
