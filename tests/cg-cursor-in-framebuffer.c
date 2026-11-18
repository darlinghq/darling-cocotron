// Copyright (C) 2026 Lubos Dolezel

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define SYM(n) dlsym(RTLD_DEFAULT, n)

typedef int (*CursorFn)(void);

int main(void) {
    CursorFn drawn = (CursorFn) SYM("CGCursorIsDrawnInFramebuffer");
    CHECK(drawn != NULL);
    if (!drawn) { printf("FAILED\n"); return 1; }
    // The cursor is reported as part of the frame buffer contents.
    CHECK(drawn() == 1);
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
