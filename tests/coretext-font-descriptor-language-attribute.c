#include <CoreText/CoreText.h>
#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); return 1; \
} } while (0)

int main(void) {
    CHECK(kCTFontDescriptorLanguageAttribute != NULL);
    CHECK(CFGetTypeID(kCTFontDescriptorLanguageAttribute) == CFStringGetTypeID());
    CHECK(!CFEqual(kCTFontDescriptorLanguageAttribute, kCTFontLanguagesAttribute));

    CFStringRef keys[1] = { kCTFontDescriptorLanguageAttribute };
    CFStringRef values[1] = { CFSTR("ja") };
    CFDictionaryRef attrs = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 1,
                                               &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CHECK(CFDictionaryGetValue(attrs, kCTFontDescriptorLanguageAttribute) != NULL);
    CFRelease(attrs);
    puts("PASS");
    return 0;
}
