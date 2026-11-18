// Copyright (C) 2026 Lubos Dolezel

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define SYM(n) dlsym(RTLD_DEFAULT, n)

typedef int (*RegFn)(void (*)(uint32_t, const CGRect *, void *), void *);
typedef void (*UnregFn)(void (*)(uint32_t, const CGRect *, void *), void *);

static void callback(uint32_t count, const CGRect *rects, void *info) {}

int main(void) {
    RegFn reg = (RegFn) SYM("CGRegisterScreenRefreshCallback");
    UnregFn unreg = (UnregFn) SYM("CGUnregisterScreenRefreshCallback");
    CHECK(reg != NULL);
    CHECK(unreg != NULL);
    if (!reg || !unreg) { printf("FAILED\n"); return 1; }

    CHECK(reg(callback, (void *) 1) == kCGErrorSuccess);
    // Registering the same pair again, and unregistering twice, are harmless.
    CHECK(reg(callback, (void *) 1) == kCGErrorSuccess);
    unreg(callback, (void *) 1);
    unreg(callback, (void *) 1);
    // Unregistering something never registered is harmless.
    unreg(callback, (void *) 2);
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
