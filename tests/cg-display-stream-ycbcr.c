// Copyright (C) 2026 Lubos Dolezel

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define SYM(n) dlsym(RTLD_DEFAULT, n)

static void check(const char *symbol, const char *value) {
    CFStringRef *p = (CFStringRef *) SYM(symbol);
    CHECK(p != NULL);
    if (!p) return;
    char buf[100] = "";
    CHECK(*p != NULL && CFStringGetCString(*p, buf, sizeof(buf), kCFStringEncodingUTF8));
    CHECK(strcmp(buf, value) == 0);
}

int main(void) {
    check("kCGDisplayStreamYCbCrMatrix", "kCGDisplayStreamYCbCrMatrix");
    check("kCGDisplayStreamYCbCrMatrix_ITU_R_601_4", "ITU_R_601_4");
    check("kCGDisplayStreamYCbCrMatrix_ITU_R_709_2", "ITU_R_709_2");
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
