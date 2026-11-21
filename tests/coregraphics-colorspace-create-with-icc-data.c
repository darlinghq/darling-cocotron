// CGColorSpaceCreateWithICCData makes a colour space from the ICC profile in a
// CFData, as CGColorSpaceCreateWithICCProfile does:
// https://developer.apple.com/documentation/coregraphics/cgcolorspace/init(iccdata:)
// A profile that CGColorSpaceCopyICCData returned for a named space gives a
// space of the same model and number of components; data that is no profile,
// NULL and an object that is not data give NULL.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void roundTrip(CFStringRef name, CGColorSpaceModel model, size_t components)
{
    CGColorSpaceRef named = CGColorSpaceCreateWithName(name);
    CFDataRef profile = named ? CGColorSpaceCopyICCData(named) : NULL;
    CHECK(profile != NULL, "a profile for the named space");
    if (profile == NULL)
        return;

    CGColorSpaceRef space = CGColorSpaceCreateWithICCData(profile);
    CHECK(space != NULL, "a space from the profile");
    if (space != NULL) {
        CHECK(CGColorSpaceGetModel(space) == model, "model %d, expected %d", (int) CGColorSpaceGetModel(space), (int) model);
        CHECK(CGColorSpaceGetNumberOfComponents(space) == components, "components");
        CFDataRef again = CGColorSpaceCopyICCData(space);
        CHECK(again != NULL && CFEqual(again, profile), "the profile comes back");
        if (again != NULL)
            CFRelease(again);
        CGColorSpaceRef viaProfile = CGColorSpaceCreateWithICCProfile(profile);
        CHECK(viaProfile != NULL && CGColorSpaceGetModel(viaProfile) == CGColorSpaceGetModel(space),
              "same as CGColorSpaceCreateWithICCProfile");
        if (viaProfile != NULL)
            CGColorSpaceRelease(viaProfile);
        CGColorSpaceRelease(space);
    }
    CFRelease(profile);
    CGColorSpaceRelease(named);
}

int main(void)
{
    roundTrip(kCGColorSpaceSRGB, kCGColorSpaceModelRGB, 3);
    roundTrip(kCGColorSpaceGenericGrayGamma2_2, kCGColorSpaceModelMonochrome, 1);

    CHECK(CGColorSpaceCreateWithICCData(NULL) == NULL, "NULL data");

    UInt8 junk[200];
    memset(junk, 7, sizeof junk);
    CFDataRef notAProfile = CFDataCreate(NULL, junk, sizeof junk);
    CHECK(CGColorSpaceCreateWithICCData(notAProfile) == NULL, "data that is no profile");
    CFRelease(notAProfile);

    CHECK(CGColorSpaceCreateWithICCData(CFSTR("not data")) == NULL, "an object that is not data");

    // QUIRK (observed on macOS 26.7.3): a data provider over the profile is accepted too.
    CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CFDataRef profile = sRGB ? CGColorSpaceCopyICCData(sRGB) : NULL;
    CHECK(profile != NULL, "a profile for the provider case");
    if (profile != NULL) {
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(profile);
        CGColorSpaceRef fromProvider = CGColorSpaceCreateWithICCData(provider);
        CHECK(fromProvider != NULL, "a space from a provider over the profile");
        if (fromProvider != NULL) {
            CHECK(CGColorSpaceGetModel(fromProvider) == kCGColorSpaceModelRGB, "model of the space from a provider");
            CGColorSpaceRelease(fromProvider);
        }
        CGDataProviderRelease(provider);
        CFRelease(profile);
    }
    CGColorSpaceRelease(sRGB);

    if (failures == 0)
        puts("PASS: coregraphics-colorspace-create-with-icc-data");
    return failures != 0;
}
