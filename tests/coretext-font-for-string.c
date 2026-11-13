/* Copyright (C) 2026 Lubos Dolezel */
/* CTFontCreateForString / CTFontCreateForStringWithLanguage: the current font
 * is returned when it covers the string, explicit cascade-list descriptors are
 * tried in order, then the system substitute; the cascade list is reported by
 * CTFontCopyAttribute. Where the host has no font for the CJK sample, the
 * substitution checks are skipped. */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); failures++; } } while (0)

static CFStringRef copyName(CTFontRef font) {
    return CTFontCopyPostScriptName(font);
}

static CTFontDescriptorRef descriptorNamed(CFStringRef name) {
    const void *keys[1] = { kCTFontNameAttribute };
    const void *values[1] = { name };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(attributes);
    CFRelease(attributes);
    return descriptor;
}

static CTFontRef createWithCascade(CFStringRef base, CFArrayRef cascade) {
    const void *keys[2] = { kCTFontNameAttribute, kCTFontCascadeListAttribute };
    const void *values[2] = { base, cascade };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(attributes);
    CFRelease(attributes);
    CTFontRef font = CTFontCreateWithFontDescriptor(descriptor, 14, NULL);
    CFRelease(descriptor);
    return font;
}

static bool covers(CTFontRef font, CFStringRef text) {
    UniChar characters[8];
    CGGlyph glyphs[8];
    CFIndex length = CFStringGetLength(text);
    CFStringGetCharacters(text, CFRangeMake(0, length), characters);
    return CTFontGetGlyphsForCharacters(font, characters, glyphs, length);
}

int main(void) {
    CFStringRef latin = CFSTR("Abc");
    CFStringRef cjk = CFSTR("中文");
    CTFontRef base = CTFontCreateWithName(CFSTR("Helvetica"), 14, NULL);
    CHECK(base != NULL);

    // A font that covers the string is returned as is.
    CTFontRef same = CTFontCreateForString(base, latin, CFRangeMake(0, 3));
    CHECK(same == base);
    if (same != NULL)
        CFRelease(same);

    // An empty range keeps the current font.
    same = CTFontCreateForString(base, latin, CFRangeMake(1, 0));
    CHECK(same == base);
    if (same != NULL)
        CFRelease(same);

    // Invalid arguments give NULL.
    CHECK(CTFontCreateForString(NULL, latin, CFRangeMake(0, 1)) == NULL);
    CHECK(CTFontCreateForString(base, NULL, CFRangeMake(0, 1)) == NULL);
    CHECK(CTFontCreateForString(base, latin, CFRangeMake(2, 5)) == NULL);
    CHECK(CTFontCreateForString(base, latin, CFRangeMake(-1, 1)) == NULL);
    UniChar lone = 0xD800;
    CFStringRef loneString = CFStringCreateWithCharacters(NULL, &lone, 1);
    CHECK(CTFontCreateForString(base, loneString, CFRangeMake(0, 1)) == NULL);
    CFRelease(loneString);

    // Only the requested range matters: the CJK prefix is outside it.
    CFStringRef mixed = CFSTR("中Abc");
    same = CTFontCreateForString(base, mixed, CFRangeMake(1, 3));
    CHECK(same == base);
    if (same != NULL)
        CFRelease(same);

    // Substitution for a string the base font lacks.
    CTFontRef substitute = CTFontCreateForString(base, cjk, CFRangeMake(0, 2));
    if (substitute == NULL) {
        puts("SKIP substitution: no font covering the CJK sample on this host");
    } else {
        CHECK(substitute != base);
        CHECK(covers(substitute, cjk));
        CHECK(CTFontGetSize(substitute) == 14);

        CTFontRef withLanguage = CTFontCreateForStringWithLanguage(
                base, cjk, CFRangeMake(0, 2), CFSTR("zh-Hans"));
        CHECK(withLanguage != NULL && covers(withLanguage, cjk));
        if (withLanguage != NULL)
            CFRelease(withLanguage);

        // Cascade list: the descriptors are tried in order and one that does
        // not cover the string is skipped.
        CFStringRef substituteName = copyName(substitute);
        CTFontRef again = substituteName != NULL
                ? CTFontCreateWithName(substituteName, 14, NULL) : NULL;
        if (again == NULL || !covers(again, cjk)) {
            puts("SKIP cascade order: substitute is not creatable by name");
        } else {
            CTFontDescriptorRef latinOnly = descriptorNamed(CFSTR("Courier"));
            CTFontDescriptorRef covering = descriptorNamed(substituteName);
            const void *order1[2] = { latinOnly, covering };
            CFArrayRef cascade1 = CFArrayCreate(NULL, order1, 2, &kCFTypeArrayCallBacks);
            CTFontRef withCascade = createWithCascade(CFSTR("Helvetica"), cascade1);
            CHECK(withCascade != NULL);

            // The attribute reports the list in the order it was given.
            CFArrayRef reported = CTFontCopyAttribute(withCascade, kCTFontCascadeListAttribute);
            CHECK(reported != NULL && CFArrayGetCount(reported) == 2);
            if (reported != NULL && CFArrayGetCount(reported) == 2) {
                CFStringRef first = CTFontDescriptorCopyAttribute(
                        (CTFontDescriptorRef) CFArrayGetValueAtIndex(reported, 0), kCTFontNameAttribute);
                CHECK(first != NULL && CFEqual(first, CFSTR("Courier")));
                if (first != NULL)
                    CFRelease(first);
            }
            if (reported != NULL)
                CFRelease(reported);

            CTFontRef picked = CTFontCreateForString(withCascade, cjk, CFRangeMake(0, 2));
            CHECK(picked != NULL && covers(picked, cjk));
            if (picked != NULL) {
                CFStringRef pickedName = copyName(picked);
                CHECK(pickedName != NULL && CFEqual(pickedName, substituteName));
                if (pickedName != NULL)
                    CFRelease(pickedName);
                CFRelease(picked);
            }

            // A copy of the font keeps the list.
            CTFontRef copy = CTFontCreateCopyWithAttributes(withCascade, 20, NULL, NULL);
            CFArrayRef copied = copy != NULL
                    ? CTFontCopyAttribute(copy, kCTFontCascadeListAttribute) : NULL;
            CHECK(copied != NULL && CFArrayGetCount(copied) == 2);
            if (copied != NULL)
                CFRelease(copied);
            if (copy != NULL)
                CFRelease(copy);

            CFRelease(withCascade);
            CFRelease(cascade1);
            CFRelease(latinOnly);
            CFRelease(covering);
        }
        if (again != NULL)
            CFRelease(again);
        if (substituteName != NULL)
            CFRelease(substituteName);
        CFRelease(substitute);
    }

    // A font without a cascade list reports none.
    CFArrayRef none = CTFontCopyAttribute(base, kCTFontCascadeListAttribute);
    CHECK(none == NULL);

    CFRelease(base);
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
