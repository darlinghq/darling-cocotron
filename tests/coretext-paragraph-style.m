#import <CoreText/CoreText.h>
#import <Foundation/NSAutoreleasePool.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "failure line %d\n", __LINE__); return 20; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    CTParagraphStyleRef style = CTParagraphStyleCreate(NULL, 0);
    if (style == NULL) { fprintf(stderr, "missing paragraph creation behavior\n"); return 10; }
    CFTypeID (*paragraphType)(void) = dlsym(RTLD_DEFAULT, "CTParagraphStyleGetTypeID");
    CTParagraphStyleRef (*copyStyle)(CTParagraphStyleRef) = dlsym(RTLD_DEFAULT, "CTParagraphStyleCreateCopy");
    CTTextTabRef (*createTab)(CTTextAlignment, double, CFDictionaryRef) = dlsym(RTLD_DEFAULT, "CTTextTabCreate");
    CFTypeID (*tabType)(void) = dlsym(RTLD_DEFAULT, "CTTextTabGetTypeID");
    CTTextAlignment (*tabAlignment)(CTTextTabRef) = dlsym(RTLD_DEFAULT, "CTTextTabGetAlignment");
    double (*tabLocation)(CTTextTabRef) = dlsym(RTLD_DEFAULT, "CTTextTabGetLocation");
    CFDictionaryRef (*tabOptions)(CTTextTabRef) = dlsym(RTLD_DEFAULT, "CTTextTabGetOptions");
    CHECK(paragraphType && copyStyle && createTab && tabType && tabAlignment && tabLocation && tabOptions);
    CHECK(CFGetTypeID(style) == paragraphType() && paragraphType() != tabType());
    CTTextAlignment alignment;
    CTWritingDirection direction;
    CTLineBreakMode mode;
    CTLineBoundsOptions bounds;
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 0, sizeof(alignment), &alignment) && alignment == kCTTextAlignmentNatural);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 6, sizeof(mode), &mode) && mode == kCTLineBreakByWordWrapping);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 13, sizeof(direction), &direction) && direction == kCTWritingDirectionNatural);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 17, sizeof(bounds), &bounds) && bounds == 0);
    for (unsigned spec = 1; spec <= 12; ++spec) {
        if (spec == 4 || spec == 6) continue;
        CGFloat number = 123;
        CHECK(CTParagraphStyleGetValueForSpecifier(style, spec, sizeof(number), &number) && number == 0);
    }
    CFArrayRef tabs = NULL;
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 4, sizeof(tabs), &tabs) && CFArrayGetCount(tabs) == 12);
    for (CFIndex i = 0; i < 12; ++i) {
        CTTextTabRef tab = CFArrayGetValueAtIndex(tabs, i);
        CHECK(CFGetTypeID(tab) == tabType() && tabAlignment(tab) == kCTTextAlignmentLeft);
        CHECK(tabLocation(tab) == (i + 1) * 28.0 && tabOptions(tab) == NULL);
    }
    unsigned char buffer[16];
    memset(buffer, 0x5a, sizeof(buffer));
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 0, sizeof(buffer), buffer));
    CHECK(buffer[0] == kCTTextAlignmentNatural && buffer[1] == 0x5a && buffer[15] == 0x5a);
    CHECK(!CTParagraphStyleGetValueForSpecifier(style, 0, 0, buffer) && buffer[1] == 0x5a);
    CHECK(!CTParagraphStyleGetValueForSpecifier(style, 99, sizeof(buffer), buffer));
    for (size_t i = 0; i < sizeof(buffer); ++i) CHECK(buffer[i] == 0);
    for (unsigned spec = 14; spec <= 16; ++spec) {
        CGFloat number = 99;
        CHECK(!CTParagraphStyleGetValueForSpecifier(style, spec, sizeof(number), &number) && number == 99);
        CTParagraphStyleSetting unsupported = {spec, sizeof(number), &number};
        CHECK(CTParagraphStyleCreate(&unsupported, 1) == NULL);
    }
    CFRelease(style);
    for (unsigned spec = 1; spec <= 12; ++spec) {
        if (spec == 4 || spec == 6) continue;
        CGFloat number = spec + 0.25, result = 0;
        CTParagraphStyleSetting setting = {spec, sizeof(number), &number};
        style = CTParagraphStyleCreate(&setting, 1);
        CHECK(style && CTParagraphStyleGetValueForSpecifier(style, spec, sizeof(result), &result) && result == number);
        CFRelease(style);
    }
    const unsigned nonnegative[] = {1, 2, 8, 9, 10, 11};
    for (size_t i = 0; i < sizeof(nonnegative) / sizeof(*nonnegative); ++i) {
        CGFloat negative = -1;
        CTParagraphStyleSetting setting = {nonnegative[i], sizeof(negative), &negative};
        CHECK(CTParagraphStyleCreate(&setting, 1) == NULL);
    }
    NSAutoreleasePool *rawPool = [NSAutoreleasePool new];
    CFStringRef rawKey = CFStringCreateWithCString(NULL, "AuthoredRawKey", kCFStringEncodingUTF8);
    CFStringRef rawValue = CFStringCreateWithCString(NULL, "owned raw value", kCFStringEncodingUTF8);
    CFDictionaryRef rawOptions = CFDictionaryCreate(NULL, (const void **)&rawKey, (const void **)&rawValue, 1, NULL, NULL);
    CTTextTabRef rawTab = createTab(kCTTextAlignmentLeft, 99, rawOptions);
    CFRelease(rawOptions); CFRelease(rawKey); CFRelease(rawValue);
    [rawPool drain];
    CHECK(rawTab && CFEqual(CFDictionaryGetValue(tabOptions(rawTab), CFSTR("AuthoredRawKey")), CFSTR("owned raw value")));
    CFArrayRef rawInput = CFArrayCreate(NULL, (const void **)&rawTab, 1, NULL);
    CTParagraphStyleSetting rawSetting = {4, sizeof(rawInput), &rawInput};
    style = CTParagraphStyleCreate(&rawSetting, 1);
    CHECK(style);
    CFRelease(rawInput); CFRelease(rawTab);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 4, sizeof(tabs), &tabs));
    CHECK(CFArrayGetCount(tabs) == 1 && tabLocation(CFArrayGetValueAtIndex(tabs, 0)) == 99);
    CFRelease(style);
    NSAutoreleasePool *inner = [NSAutoreleasePool new];
    CFMutableDictionaryRef options = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(options, CFSTR("AuthoredOption"), CFSTR("original"));
    CTTextTabRef tab = createTab(kCTTextAlignmentRight, 42, options);
    CHECK(tab && tabLocation(tab) == 42 && tabAlignment(tab) == kCTTextAlignmentRight);
    CFDictionarySetValue(options, CFSTR("AuthoredOption"), CFSTR("mutated"));
    CFMutableArrayRef inputTabs = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    CFArrayAppendValue(inputTabs, tab);
    CGFloat tail = -17.5;
    alignment = kCTTextAlignmentCenter;
    direction = kCTWritingDirectionRightToLeft;
    mode = kCTLineBreakByTruncatingTail;
    bounds = kCTLineBoundsExcludeTypographicLeading;
    CTParagraphStyleSetting settings[] = {{0, sizeof(alignment), &alignment}, {3, sizeof(tail), &tail}, {4, sizeof(inputTabs), &inputTabs}, {6, sizeof(mode), &mode}, {13, sizeof(direction), &direction}, {17, sizeof(bounds), &bounds}, {99, 0, NULL}};
    style = CTParagraphStyleCreate(settings, 7);
    CHECK(style);
    CTParagraphStyleRef copy = copyStyle(style);
    CHECK(copy && CFGetTypeID(copy) == paragraphType());
    tail = 1; alignment = kCTTextAlignmentLeft;
    CFArrayRemoveAllValues(inputTabs);
    CFRelease(inputTabs); CFRelease(options); CFRelease(tab); CFRelease(style);
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, (const void *[]){kCTParagraphStyleAttributeName}, (const void *[]){copy}, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef text = CFAttributedStringCreate(NULL, CFSTR("authored paragraph"), attributes);
    CHECK(text);
    CFRelease(attributes);
    CFRelease(copy);
    [inner drain];
    attributes = CFAttributedStringGetAttributes(text, 0, NULL);
    style = CFDictionaryGetValue(attributes, kCTParagraphStyleAttributeName);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 0, sizeof(alignment), &alignment) && alignment == kCTTextAlignmentCenter);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 3, sizeof(tail), &tail) && tail == -17.5);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 6, sizeof(mode), &mode) && mode == kCTLineBreakByTruncatingTail);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 13, sizeof(direction), &direction) && direction == kCTWritingDirectionRightToLeft);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 17, sizeof(bounds), &bounds) && bounds == kCTLineBoundsExcludeTypographicLeading);
    CHECK(CTParagraphStyleGetValueForSpecifier(style, 4, sizeof(tabs), &tabs) && CFArrayGetCount(tabs) == 1);
    tab = CFArrayGetValueAtIndex(tabs, 0);
    CHECK(tabLocation(tab) == 42 && CFEqual(CFDictionaryGetValue(tabOptions(tab), CFSTR("AuthoredOption")), CFSTR("original")));
    CHECK(!CTParagraphStyleGetValueForSpecifier(NULL, 0, sizeof(alignment), &alignment));
    CHECK(!CTParagraphStyleGetValueForSpecifier(style, 0, sizeof(alignment), NULL));
    CFRelease(text);
    CHECK(createTab(99, 0, NULL) == NULL && createTab(kCTTextAlignmentLeft, NAN, NULL) == NULL);
    CGFloat number = 1;
    CTParagraphStyleSetting wrong = {1, 1, &number};
    CHECK(CTParagraphStyleCreate(&wrong, 1) == NULL && CTParagraphStyleCreate(NULL, 1) == NULL);
    CTParagraphStyleSetting duplicate[] = {{1, sizeof(number), &number}, {1, sizeof(number), &number}};
    CHECK(CTParagraphStyleCreate(duplicate, 2) == NULL);
    [pool drain];
    puts("paragraph defaults, typed values, snapshots, CF identities and retained lifetime pass");
    return 0;
}
