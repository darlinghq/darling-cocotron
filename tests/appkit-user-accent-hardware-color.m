// Copyright (C) 2026 Lubos Dolezel
//
// NSUserAccentHasHardwareColor() and NSUserAccentColorGetHardwareAccentColorName(), exported by AppKit.
// Expected values from macOS 26.7.3 on a Mac without a coloured case: NO and nil.
// Build: clang -framework AppKit appkit-user-accent-hardware-color.m (no ARC)
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    bool (*has)(void) = dlsym(RTLD_DEFAULT, "NSUserAccentHasHardwareColor");
    NSString *(*name)(void) = dlsym(RTLD_DEFAULT, "NSUserAccentColorGetHardwareAccentColorName");
    CHECK(has != NULL);
    CHECK(name != NULL);
    if (has != NULL)
        CHECK(has() == false);
    if (name != NULL)
        CHECK(name() == nil);
    if (failures == 0)
        printf("PASS appkit-user-accent-hardware-color\n");
    [pool release];
    return failures != 0;
}
