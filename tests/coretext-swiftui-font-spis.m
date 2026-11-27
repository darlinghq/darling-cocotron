// Copyright (C) 2026 Lubos Dolezel
//
// CoreText SPI functions and constants that SwiftUI imports. Expected values are from macOS 26.7.3
// (black-box: dlsym and calling them):
//  - the string values of the constants;
//  - CTFontGetWeight of the system font is 0 and of a font created with weight 0.4 it is 0.4;
//    CTFontDescriptorGetWeight gives the weight trait, and 0 for a descriptor without one;
//  - CTFontGetClippingMetrics returns true with the ascent and descent of the font;
//  - CTParagraphStyleGetCompositionLanguageForLanguage gives 1 for NULL, "en" and "ko", 2 for "ja" and "ja-JP",
//    3 for "zh-Hans", "zh_Hans", "zh-CN" and "zh-Hans-CN", 4 for "zh-Hant", "zh-TW" and "zh-HK".
// Build: clang -framework CoreText -framework Foundation coretext-swiftui-font-spis.m (no ARC)
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void constant(const char *symbol, NSString *value) {
    CFStringRef *p = dlsym(RTLD_DEFAULT, symbol);
    if (p == NULL || *p == NULL || ![(NSString *) *p isEqualToString: value]) {
        fprintf(stderr, "FAIL %s is %s, expected %s\n", symbol, p && *p ? [(NSString *) *p UTF8String] : "(missing)", [value UTF8String]);
        failures++;
    }
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    constant("kCTFontLegibilityWeightAttribute", @"CTFontLegibilityWeightAttribute");
    constant("kCTFontLanguageAwareLineHeightRatioAttribute", @"CTFontLanguageAwareLineHeightRatioAttribute");
    constant("kCTTextScaleRatioAttributeName", @"NSTextScaleRatio");
    constant("kCTFontUIFontDesignCompact", @"NSCTFontUIFontDesignCompact");
    constant("kCTFontUIFontDesignCompactRounded", @"NSCTFontUIFontDesignCompactRounded");
    constant("kCTFontUIFontDesignSoft", @"NSCTFontUIFontDesignSoft");
    constant("kCTFontUIFontDesignCompactSoft", @"NSCTFontUIFontDesignCompactSoft");
    constant("kCTUIFontTextStyleCallout", @"UICTFontTextStyleCallout");
    constant("kCTUIFontTextStyleFootnote2", @"UICTFontTextStyleFootnote2");
    constant("kCTFontContentSizeCategoryXS", @"UICTContentSizeCategoryXS");
    constant("kCTFontContentSizeCategoryS", @"UICTContentSizeCategoryS");
    constant("kCTFontContentSizeCategoryM", @"UICTContentSizeCategoryM");
    constant("kCTFontContentSizeCategoryL", @"UICTContentSizeCategoryL");
    constant("kCTFontContentSizeCategoryXL", @"UICTContentSizeCategoryXL");
    constant("kCTFontContentSizeCategoryXXL", @"UICTContentSizeCategoryXXL");
    constant("kCTFontContentSizeCategoryXXXL", @"UICTContentSizeCategoryXXXL");
    constant("kCTFontContentSizeCategoryAccessibilityM", @"UICTContentSizeCategoryAccessibilityM");
    constant("kCTFontContentSizeCategoryAccessibilityL", @"UICTContentSizeCategoryAccessibilityL");
    constant("kCTFontContentSizeCategoryAccessibilityXL", @"UICTContentSizeCategoryAccessibilityXL");
    constant("kCTFontContentSizeCategoryAccessibilityXXL", @"UICTContentSizeCategoryAccessibilityXXL");
    constant("kCTFontContentSizeCategoryAccessibilityXXXL", @"UICTContentSizeCategoryAccessibilityXXXL");

    CGFloat (*fontWeight)(CTFontRef) = dlsym(RTLD_DEFAULT, "CTFontGetWeight");
    CGFloat (*descriptorWeight)(CTFontDescriptorRef) = dlsym(RTLD_DEFAULT, "CTFontDescriptorGetWeight");
    bool (*clipping)(CTFontRef, CGFloat *, CGFloat *) = dlsym(RTLD_DEFAULT, "CTFontGetClippingMetrics");
    bool (*outsets)(CTFontRef, CGFloat *, CGFloat *, CGFloat *, CGFloat *) = dlsym(RTLD_DEFAULT, "CTFontGetLanguageAwareOutsets");
    CFCharacterSetRef (*excessive)(void) = dlsym(RTLD_DEFAULT, "CTFontCopySystemUIFontExcessiveLineHeightCharacterSet");
    CFStringRef (*tallest)(CFStringRef) = dlsym(RTLD_DEFAULT, "CTFontCopyTallestTextStyleLanguageForString");
    uint8_t (*composition)(CFStringRef) = dlsym(RTLD_DEFAULT, "CTParagraphStyleGetCompositionLanguageForLanguage");
    CHECK(fontWeight && descriptorWeight && clipping && outsets && excessive && tallest && composition);
    if (!(fontWeight && descriptorWeight && clipping && outsets && excessive && tallest && composition))
        return 1;

    CTFontRef system = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 13, NULL);
    CHECK(system != NULL);
    CHECK(fabs(fontWeight(system)) < 0.001);
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSDictionary dictionaryWithObject: [NSNumber numberWithDouble: 0.4] forKey: (id) kCTFontWeightTrait],
            (id) kCTFontTraitsAttribute, @"Helvetica Neue", (id) kCTFontFamilyNameAttribute, nil];
    CTFontDescriptorRef heavy = CTFontDescriptorCreateWithAttributes((CFDictionaryRef) attributes);
    CHECK(fabs(descriptorWeight(heavy) - 0.4) < 0.001);
    CTFontDescriptorRef plain = CTFontDescriptorCreateWithAttributes((CFDictionaryRef)
            [NSDictionary dictionaryWithObject: @"Helvetica" forKey: (id) kCTFontFamilyNameAttribute]);
    CHECK(fabs(descriptorWeight(plain)) < 0.001);
    CGFloat ascent = -1, descent = -1;
    CHECK(clipping(system, &ascent, &descent));
    CHECK(fabs(ascent - CTFontGetAscent(system)) < 0.001 && fabs(descent - CTFontGetDescent(system)) < 0.001);
    CGFloat o[4] = {-1, -1, -1, -1};
    (void) outsets(system, &o[0], &o[1], &o[2], &o[3]);
    CFCharacterSetRef set = excessive();
    CHECK(set != NULL);
    if (set != NULL) {
        CHECK(!CFCharacterSetIsCharacterMember(set, 'a'));
        CFRelease(set);
    }
    CFStringRef language = tallest(CFSTR("abc"));
    CHECK(language == NULL);

    struct { CFStringRef language; int value; } languages[] = {
        { NULL, 1 }, { CFSTR("en"), 1 }, { CFSTR("ko"), 1 }, { CFSTR("ja"), 2 }, { CFSTR("ja-JP"), 2 },
        { CFSTR("zh-Hans"), 3 }, { CFSTR("zh_Hans"), 3 }, { CFSTR("zh-CN"), 3 }, { CFSTR("zh-Hans-CN"), 3 },
        { CFSTR("zh-Hant"), 4 }, { CFSTR("zh-TW"), 4 }, { CFSTR("zh-HK"), 4 },
    };
    for (size_t i = 0; i < sizeof languages / sizeof languages[0]; i++) {
        int got = composition(languages[i].language);
        if (got != languages[i].value) {
            fprintf(stderr, "FAIL composition language of %s is %d, expected %d\n",
                    languages[i].language ? [(NSString *) languages[i].language UTF8String] : "NULL", got, languages[i].value);
            failures++;
        }
    }
    if (failures == 0)
        printf("PASS coretext-swiftui-font-spis\n");
    [pool release];
    return failures != 0;
}
