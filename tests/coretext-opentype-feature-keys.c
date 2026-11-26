/* Copyright (C) 2026 Lubos Dolezel */
/* kCTFontOpenTypeFeatureTag and kCTFontOpenTypeFeatureValue (CTFont.h, macOS
 * 10.10): the keys of a feature setting that names an OpenType feature by its
 * tag, which a font descriptor keeps in its kCTFontFeatureSettingsAttribute. */
#include <CoreText/CoreText.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    CHECK(kCTFontOpenTypeFeatureTag != NULL && kCTFontOpenTypeFeatureValue != NULL);
    CHECK(!CFEqual(kCTFontOpenTypeFeatureTag, kCTFontOpenTypeFeatureValue));
    CHECK(!CFEqual(kCTFontOpenTypeFeatureTag, kCTFontFeatureTypeIdentifierKey));
    CHECK(!CFEqual(kCTFontOpenTypeFeatureValue, kCTFontFeatureSelectorIdentifierKey));

    /* a setting that turns small capitals ('smcp') on */
    int one = 1;
    CFNumberRef value = CFNumberCreate(NULL, kCFNumberIntType, &one);
    const void *keys[] = { kCTFontOpenTypeFeatureTag, kCTFontOpenTypeFeatureValue };
    const void *values[] = { CFSTR("smcp"), value };
    CFDictionaryRef setting = CFDictionaryCreate(NULL, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef settings = CFArrayCreate(NULL, (const void **) &setting, 1, &kCFTypeArrayCallBacks);
    const void *attributeKeys[] = { kCTFontNameAttribute, kCTFontFeatureSettingsAttribute };
    const void *attributeValues[] = { CFSTR("Helvetica"), settings };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, attributeKeys, attributeValues, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(attributes);
    CHECK(descriptor != NULL);

    CFArrayRef kept = descriptor ? CTFontDescriptorCopyAttribute(descriptor, kCTFontFeatureSettingsAttribute) : NULL;
    CHECK(kept != NULL && CFGetTypeID(kept) == CFArrayGetTypeID() && CFArrayGetCount(kept) == 1);
    if (kept != NULL && CFArrayGetCount(kept) == 1) {
        CFDictionaryRef keptSetting = CFArrayGetValueAtIndex(kept, 0);
        CHECK(CFEqual(CFDictionaryGetValue(keptSetting, kCTFontOpenTypeFeatureTag), CFSTR("smcp")));
        CHECK(CFEqual(CFDictionaryGetValue(keptSetting, kCTFontOpenTypeFeatureValue), value));
    }

    if (kept != NULL) CFRelease(kept);
    if (descriptor != NULL) CFRelease(descriptor);
    CFRelease(attributes);
    CFRelease(settings);
    CFRelease(setting);
    CFRelease(value);

    if (failures == 0) puts("PASS");
    return failures != 0;
}
