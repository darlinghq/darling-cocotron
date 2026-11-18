// Copyright (C) 2026 Lubos Dolezel

#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define SYM(n) dlsym(RTLD_DEFAULT, n)

typedef CFDataRef (*CopyFn)(CGColorSpaceRef);
typedef CGColorSpaceRef (*CreateFn)(CFDataRef);

static void roundTrip(CFStringRef name, size_t components, CGColorSpaceModel model, const char *space) {
    CopyFn copy = (CopyFn) SYM("CGColorSpaceCopyICCProfile");
    CreateFn create = (CreateFn) SYM("CGColorSpaceCreateWithICCProfile");
    CHECK(copy != NULL && create != NULL);
    if (!copy || !create) return;

    CGColorSpaceRef cs = CGColorSpaceCreateWithName(name);
    CFDataRef data = copy(cs);
    CHECK(data != NULL);
    if (!data) return;
    const UInt8 *p = CFDataGetBytePtr(data);
    CHECK(CFDataGetLength(data) > 128);
    CHECK(memcmp(p + 36, "acsp", 4) == 0);
    CHECK(memcmp(p + 16, space, 4) == 0);

    CGColorSpaceRef back = create(data);
    CHECK(back != NULL);
    if (!back) return;
    CHECK(CGColorSpaceGetNumberOfComponents(back) == components);
    CHECK(CGColorSpaceGetModel(back) == model);
    CFDataRef again = copy(back);
    CHECK(again != NULL && CFEqual(data, again));
    CFStringRef n = CGColorSpaceCopyName(back);
    CHECK(n != NULL && CFEqual(n, name));
}

int main(void) {
    CopyFn copy = (CopyFn) SYM("CGColorSpaceCopyICCProfile");
    CreateFn create = (CreateFn) SYM("CGColorSpaceCreateWithICCProfile");

    roundTrip(kCGColorSpaceSRGB, 3, kCGColorSpaceModelRGB, "RGB ");
    roundTrip(kCGColorSpaceDisplayP3, 3, kCGColorSpaceModelRGB, "RGB ");

    if (copy && create) {
        // Device spaces have no profile.
        CGColorSpaceRef dev = CGColorSpaceCreateDeviceRGB();
        CHECK(copy(dev) == NULL);
        // Data that is not an ICC profile is rejected.
        UInt8 junk[200] = {1, 2, 3};
        CFDataRef j = CFDataCreate(NULL, junk, sizeof(junk));
        CHECK(create(j) == NULL);
        CFDataRef empty = CFDataCreate(NULL, junk, 0);
        CHECK(create(empty) == NULL);
        CHECK(create(NULL) == NULL);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
