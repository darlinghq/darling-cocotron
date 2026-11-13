/* Copyright (C) 2026 Lubos Dolezel */
/* Descriptor copies that change symbolic traits, one feature or one variation
 * axis, keeping everything else. */
#include <CoreText/CoreText.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static CFNumberRef intNumber(int v) { return CFNumberCreate(NULL, kCFNumberIntType, &v); }

int main(void) {
    unsigned initial = kCTFontTraitItalic | kCTFontTraitBold;
    double weight = 0.25;
    CFNumberRef symbolic = CFNumberCreate(NULL, kCFNumberIntType, &initial);
    CFNumberRef weightNumber = CFNumberCreate(NULL, kCFNumberDoubleType, &weight);
    const void *traitKeys[] = {kCTFontSymbolicTrait, kCTFontWeightTrait};
    const void *traitValues[] = {symbolic, weightNumber};
    CFDictionaryRef traits = CFDictionaryCreate(NULL, traitKeys, traitValues, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    const void *keys[] = {kCTFontNameAttribute, kCTFontTraitsAttribute};
    const void *values[] = {CFSTR("TestFont"), traits};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef original = CTFontDescriptorCreateWithAttributes(attributes);
    CHECK(original != NULL);

    CHECK(CTFontDescriptorGetSymbolicTraits(original) == initial);
    CTFontDescriptorRef changed = CTFontDescriptorCreateCopyWithSymbolicTraits(
            original, kCTFontTraitMonoSpace, kCTFontTraitBold | kCTFontTraitMonoSpace);
    CHECK(CTFontDescriptorGetSymbolicTraits(original) == initial);
    CHECK(CTFontDescriptorGetSymbolicTraits(changed) == (kCTFontTraitItalic | kCTFontTraitMonoSpace));
    CFDictionaryRef changedTraits = CTFontDescriptorCopyAttribute(changed, kCTFontTraitsAttribute);
    CHECK(changedTraits != NULL && CFDictionaryContainsKey(changedTraits, kCTFontWeightTrait));
    CFStringRef name = CTFontDescriptorCopyAttribute(changed, kCTFontNameAttribute);
    CHECK(name != NULL && CFEqual(name, CFSTR("TestFont")));
    CHECK(CTFontDescriptorGetSymbolicTraits(NULL) == 0);
    CHECK(CTFontDescriptorCreateCopyWithSymbolicTraits(NULL, 0, 0) == NULL);

    // Features: a new selector for a type replaces the old one; other types stay.
    CFNumberRef type6 = intNumber(6), sel0 = intNumber(0), sel1 = intNumber(1);
    CFNumberRef type35 = intNumber(35), sel2 = intNumber(2);
    CTFontDescriptorRef f0 = CTFontDescriptorCreateCopyWithFeature(changed, type6, sel0);
    CTFontDescriptorRef f1 = CTFontDescriptorCreateCopyWithFeature(f0, type6, sel1);
    CTFontDescriptorRef f2 = CTFontDescriptorCreateCopyWithFeature(f1, type35, sel2);
    CFArrayRef settings = CTFontDescriptorCopyAttribute(f2, kCTFontFeatureSettingsAttribute);
    CHECK(settings != NULL && CFArrayGetCount(settings) == 2);
    CFDictionaryRef first = CFArrayGetValueAtIndex(settings, 0);
    CHECK(CFEqual(CFDictionaryGetValue(first, kCTFontFeatureTypeIdentifierKey), type6));
    CHECK(CFEqual(CFDictionaryGetValue(first, kCTFontFeatureSelectorIdentifierKey), sel1));
    CHECK(CTFontDescriptorCreateCopyWithFeature(changed, NULL, sel0) == NULL);

    // Variations: one axis changes, others stay.
    CFNumberRef wght = intNumber(0x77676874), wdth = intNumber(0x77647468);
    CTFontDescriptorRef v0 = CTFontDescriptorCreateCopyWithVariation(f2, wght, 0.25);
    CTFontDescriptorRef v1 = CTFontDescriptorCreateCopyWithVariation(v0, wdth, 0.75);
    CTFontDescriptorRef v2 = CTFontDescriptorCreateCopyWithVariation(v1, wght, 0.5);
    CFDictionaryRef axes = CTFontDescriptorCopyAttribute(v2, kCTFontVariationAttribute);
    CHECK(axes != NULL && CFDictionaryGetCount(axes) == 2);
    double value = 0;
    CFNumberGetValue(CFDictionaryGetValue(axes, wght), kCFNumberDoubleType, &value);
    CHECK(value == 0.5);
    CHECK(CTFontDescriptorCreateCopyWithVariation(f2, NULL, 1) == NULL);

    puts(failures ? "FAILED" : "PASS");
    return failures != 0;
}
