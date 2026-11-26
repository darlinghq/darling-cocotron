// CGColorSpaceCopyPropertyList and CGColorSpaceCreateWithPropertyList (Apple's
// CGColorSpace reference, macOS 10.12): a space's property list makes an
// equivalent space again. What the list holds is not documented; these checks
// only rely on the round trip, and on NULL for no list.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } else printf("PASS %s\n", #cond); } while (0)

int main(void) {
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFPropertyListRef list = CGColorSpaceCopyPropertyList(srgb);
    CHECK(list != NULL);
    CGColorSpaceRef again = CGColorSpaceCreateWithPropertyList(list);
    CHECK(again != NULL);
    CHECK(again != NULL && CFEqual(CGColorSpaceGetName(again), kCGColorSpaceSRGB));
    CHECK(again != NULL && CGColorSpaceGetNumberOfComponents(again) == 3);

    CHECK(CGColorSpaceCreateWithPropertyList(NULL) == NULL);
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &(int){ 1 });
    CHECK(CGColorSpaceCreateWithPropertyList(number) == NULL);
    CHECK(CGColorSpaceCopyPropertyList(NULL) == NULL);

    CFRelease(number);
    if (again != NULL)
        CGColorSpaceRelease(again);
    CFRelease(list);
    CGColorSpaceRelease(srgb);
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
