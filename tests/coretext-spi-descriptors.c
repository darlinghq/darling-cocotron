/* Copyright (C) 2026 Lubos Dolezel */
/* CoreText descriptor functions that macOS exports but the SDK does not declare:
 * UI type and text style descriptors round-trip to system UI fonts, descriptor
 * options are kept, the generic CSS families and the last resort resolve to
 * installed faces, the PostScript name attribute is the font name, and NULL
 * arguments give NULL, 0 or false.
 *
 * The text style sizes are the macOS ones of Apple's Human Interface
 * Guidelines (public documentation). The UI type round trip, the CSS family
 * resolution and the options follow the documented contracts of the
 * functions they build on; the details checked for the Darling fonts (which
 * face a family resolves to) are Darling's. */
#include <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>

typedef uint32_t CTFontDescriptorOptions;
enum { kCTFontDescriptorOptionSystemUIFont = 1 << 1 };
typedef uint32_t CTFontTextStylePlatform;
enum { kCTFontTextStylePlatformDefault = (CTFontTextStylePlatform) -1,
       kCTFontTextStylePlatformPhone = 0, kCTFontTextStylePlatformMac = 3 };

extern bool CTFontDescriptorIsSystemUIFont(CTFontDescriptorRef);
extern bool CTFontIsSystemUIFont(CTFontRef);
extern CTFontUIFontType CTFontGetUIFontType(CTFontRef);
extern CTFontDescriptorRef CTFontDescriptorCreateForUIType(CTFontUIFontType, CGFloat, CFStringRef);
extern CTFontDescriptorRef CTFontDescriptorCreateWithTextStyle(CFStringRef, CFStringRef, CFStringRef);
extern CGFloat CTFontDescriptorGetTextStyleSize(CFStringRef, CFTypeRef, CTFontTextStylePlatform, CGFloat *, CGFloat *);
extern CTFontDescriptorRef CTFontDescriptorCreateForCSSFamily(CFStringRef, CFStringRef);
extern CTFontDescriptorRef CTFontDescriptorCreateLastResort(void);
extern CTFontDescriptorRef CTFontDescriptorCreateWithAttributesAndOptions(CFDictionaryRef, CTFontDescriptorOptions);
extern CTFontDescriptorOptions CTFontDescriptorGetOptions(CTFontDescriptorRef);
extern const CFStringRef kCTUIFontTextStyleBody, kCTUIFontTextStyleHeadline,
        kCTUIFontTextStyleTitle0, kCTUIFontTextStyleCaption1, kCTUIFontTextStyleShortCaption1;
extern const CFStringRef kCTFontDescriptorTextStyleAttribute, kCTFontContentSizeCategoryL;
extern const CFStringRef kCTFontCSSFamilySerif, kCTFontCSSFamilySansSerif, kCTFontCSSFamilyMonospace;
extern const CFStringRef kCTFontPostScriptNameAttribute, kCTFontCSSWeightAttribute;
extern const CGFloat kCTFontWeightRegular, kCTFontWeightBold;

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static CFDictionaryRef dictionary1(CFStringRef key, CFTypeRef value) {
    return CFDictionaryCreate(NULL, (const void **) &key, (const void **) &value, 1,
                              &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

static void testUIType(void) {
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateForUIType(kCTFontUIFontSystem, 15, CFSTR("en"));
    CHECK(descriptor != NULL);
    if (descriptor == NULL)
        return;
    CHECK(CTFontDescriptorIsSystemUIFont(descriptor));
    CHECK(CTFontDescriptorGetOptions(descriptor) & kCTFontDescriptorOptionSystemUIFont);
    CFTypeRef language = CTFontDescriptorCopyAttribute(descriptor, kCTFontDescriptorLanguageAttribute);
    CHECK(language != NULL && CFEqual(language, CFSTR("en")));
    if (language) CFRelease(language);

    /* the font made from it is the UI font of the type, at the size */
    CTFontRef font = CTFontCreateWithFontDescriptor(descriptor, 0, NULL);
    CTFontRef direct = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 15, NULL);
    CHECK(font != NULL && direct != NULL);
    if (font != NULL && direct != NULL) {
        CHECK(CTFontGetSize(font) == 15);
        CHECK(CTFontIsSystemUIFont(font) && CTFontIsSystemUIFont(direct));
        CHECK(CTFontGetUIFontType(font) == kCTFontUIFontSystem);
        CHECK(CTFontGetUIFontType(direct) == kCTFontUIFontSystem);
        CFStringRef a = CTFontCopyPostScriptName(font), b = CTFontCopyPostScriptName(direct);
        CHECK(a != NULL && b != NULL && CFEqual(a, b));
        if (a) CFRelease(a);
        if (b) CFRelease(b);
        /* a copy at another size is still that UI font */
        CTFontRef bigger = CTFontCreateCopyWithAttributes(font, 30, NULL, NULL);
        CHECK(bigger != NULL && CTFontIsSystemUIFont(bigger) && CTFontGetUIFontType(bigger) == kCTFontUIFontSystem);
        if (bigger) CFRelease(bigger);
    }
    if (font) CFRelease(font);
    if (direct) CFRelease(direct);
    CFRelease(descriptor);

    /* the user font has a type but is no system UI font */
    CTFontRef user = CTFontCreateUIFontForLanguage(kCTFontUIFontUser, 12, NULL);
    CHECK(user != NULL && !CTFontIsSystemUIFont(user) && CTFontGetUIFontType(user) == kCTFontUIFontUser);
    if (user) CFRelease(user);

    /* a font made by name is neither */
    CTFontRef named = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
    CHECK(named == NULL || (!CTFontIsSystemUIFont(named) && CTFontGetUIFontType(named) == kCTFontUIFontNone));
    if (named) CFRelease(named);

    CHECK(CTFontDescriptorCreateForUIType((CTFontUIFontType) 500, 12, NULL) == NULL);
    CHECK(!CTFontIsSystemUIFont(NULL));
    CHECK(CTFontGetUIFontType(NULL) == kCTFontUIFontNone);
}

static void testTextStyles(void) {
    /* observed on macOS 26.7.3 (default and Mac platforms; the size category
     * does not matter on them) */
    CGFloat weight = -100, lineSpacing = -100;
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleBody, kCTFontContentSizeCategoryL,
                                           kCTFontTextStylePlatformDefault, &weight, &lineSpacing) == 13);
    CHECK(weight == kCTFontWeightRegular && lineSpacing == 16);
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleHeadline, NULL,
                                           kCTFontTextStylePlatformDefault, &weight, NULL) == 13);
    CHECK(weight == kCTFontWeightBold);
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleTitle0, NULL,
                                           kCTFontTextStylePlatformDefault, NULL, &lineSpacing) == 26);
    CHECK(lineSpacing == 32);
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleCaption1, NULL,
                                           kCTFontTextStylePlatformDefault, NULL, NULL) == 10);
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleCaption2, NULL,
                                           kCTFontTextStylePlatformMac, &weight, &lineSpacing) == 10);
    CHECK(weight == kCTFontWeightMedium && lineSpacing == 13);
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleShortBody, NULL,
                                           kCTFontTextStylePlatformMac, NULL, &lineSpacing) == 13);
    CHECK(lineSpacing == 14);
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleTitle4, NULL,
                                           kCTFontTextStylePlatformMac, &weight, &lineSpacing) == 38);
    CHECK(weight == kCTFontWeightHeavy && lineSpacing == 48);
    /* the phone platform, at the default size category (observed likewise) */
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleBody, kCTFontContentSizeCategoryL,
                                           kCTFontTextStylePlatformPhone, &weight, &lineSpacing) == 17);
    CHECK(weight == kCTFontWeightRegular && lineSpacing == 22);
    CHECK(CTFontDescriptorGetTextStyleSize(kCTUIFontTextStyleHeadline, kCTFontContentSizeCategoryL,
                                           kCTFontTextStylePlatformPhone, &weight, NULL) == 17);
    CHECK(weight == kCTFontWeightSemibold);
    /* unknown and NULL styles: 0, outputs untouched */
    weight = -100;
    CHECK(CTFontDescriptorGetTextStyleSize(CFSTR("NoSuchStyle"), NULL,
                                           kCTFontTextStylePlatformDefault, &weight, NULL) == 0);
    CHECK(weight == -100);
    CHECK(CTFontDescriptorGetTextStyleSize(NULL, NULL, kCTFontTextStylePlatformDefault, NULL, NULL) == 0);

    CTFontDescriptorRef body = CTFontDescriptorCreateWithTextStyle(kCTUIFontTextStyleBody,
                                                                   kCTFontContentSizeCategoryL, NULL);
    CHECK(body != NULL);
    if (body != NULL) {
        CFTypeRef style = CTFontDescriptorCopyAttribute(body, kCTFontDescriptorTextStyleAttribute);
        CHECK(style != NULL && CFEqual(style, kCTUIFontTextStyleBody));
        if (style) CFRelease(style);
        CHECK(CTFontDescriptorIsSystemUIFont(body));
        CTFontRef font = CTFontCreateWithFontDescriptor(body, 0, NULL);
        CHECK(font != NULL && CTFontGetSize(font) == 13 && CTFontIsSystemUIFont(font));
        CHECK(font != NULL && !(CTFontGetSymbolicTraits(font) & kCTFontTraitBold));
        if (font) CFRelease(font);
        CFRelease(body);
    }
    CTFontDescriptorRef headline = CTFontDescriptorCreateWithTextStyle(kCTUIFontTextStyleHeadline, NULL, NULL);
    CHECK(headline != NULL);
    if (headline != NULL) {
        CTFontRef font = CTFontCreateWithFontDescriptor(headline, 0, NULL);
        CHECK(font != NULL && (CTFontGetSymbolicTraits(font) & kCTFontTraitBold));
        if (font) CFRelease(font);
        CFRelease(headline);
    }
    CTFontDescriptorRef shortCaption = CTFontDescriptorCreateWithTextStyle(kCTUIFontTextStyleShortCaption1, NULL, NULL);
    CHECK(shortCaption != NULL);
    if (shortCaption) CFRelease(shortCaption);
    CHECK(CTFontDescriptorCreateWithTextStyle(CFSTR("NoSuchStyle"), NULL, NULL) == NULL);
    CHECK(CTFontDescriptorCreateWithTextStyle(NULL, NULL, NULL) == NULL);
}

static void testOptions(void) {
    CFDictionaryRef attributes = dictionary1(kCTFontNameAttribute, CFSTR("Helvetica"));
    CTFontDescriptorRef plain = CTFontDescriptorCreateWithAttributesAndOptions(attributes, 0);
    CTFontDescriptorRef system = CTFontDescriptorCreateWithAttributesAndOptions(
            attributes, kCTFontDescriptorOptionSystemUIFont);
    CHECK(plain != NULL && system != NULL);
    CHECK(CTFontDescriptorGetOptions(plain) == 0 && !CTFontDescriptorIsSystemUIFont(plain));
    CHECK(CTFontDescriptorGetOptions(system) == kCTFontDescriptorOptionSystemUIFont);
    CHECK(CTFontDescriptorIsSystemUIFont(system));
    /* the options are not attributes, and a copy keeps them */
    CFDictionaryRef copied = CTFontDescriptorCopyAttributes(system);
    CHECK(copied != NULL && CFEqual(copied, attributes));
    if (copied) CFRelease(copied);
    double points = 20;
    CFNumberRef pointsNumber = CFNumberCreate(NULL, kCFNumberDoubleType, &points);
    CFDictionaryRef size = dictionary1(kCTFontSizeAttribute, pointsNumber);
    CFRelease(pointsNumber);
    CTFontDescriptorRef copy = CTFontDescriptorCreateCopyWithAttributes(system, size);
    CHECK(copy != NULL && CTFontDescriptorGetOptions(copy) == kCTFontDescriptorOptionSystemUIFont);
    if (copy) CFRelease(copy);
    CHECK(!CFEqual(plain, system));
    CFRelease(size);
    CFRelease(plain);
    CFRelease(system);
    CFRelease(attributes);
    CHECK(CTFontDescriptorCreateWithAttributesAndOptions(NULL, 0) == NULL);
    CHECK(CTFontDescriptorGetOptions(NULL) == 0);
}

static void testCSSFamilies(void) {
    CFStringRef families[] = { kCTFontCSSFamilySerif, kCTFontCSSFamilySansSerif, kCTFontCSSFamilyMonospace };
    for (int i = 0; i < 3; i++) {
        CTFontDescriptorRef descriptor = CTFontDescriptorCreateForCSSFamily(families[i], CFSTR("en-US"));
        CHECK(descriptor != NULL);
        if (descriptor == NULL)
            continue;
        CFStringRef family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute);
        CHECK(family != NULL && CFGetTypeID(family) == CFStringGetTypeID() && CFStringGetLength(family) > 0);
        if (family) CFRelease(family);
        CTFontRef font = CTFontCreateWithFontDescriptor(descriptor, 12, NULL);
        CHECK(font != NULL);
        if (font) CFRelease(font);
        CFRelease(descriptor);
    }
    /* the monospace family is fixed pitch */
    CTFontDescriptorRef mono = CTFontDescriptorCreateForCSSFamily(kCTFontCSSFamilyMonospace, NULL);
    CTFontRef monoFont = mono ? CTFontCreateWithFontDescriptor(mono, 12, NULL) : NULL;
    CHECK(monoFont != NULL && (CTFontGetSymbolicTraits(monoFont) & kCTFontTraitMonoSpace));
    if (monoFont) CFRelease(monoFont);
    if (mono) CFRelease(mono);
    CHECK(CTFontDescriptorCreateForCSSFamily(CFSTR("Helvetica"), NULL) == NULL);
    CHECK(CTFontDescriptorCreateForCSSFamily(NULL, NULL) == NULL);

    CTFontDescriptorRef lastResort = CTFontDescriptorCreateLastResort();
    CHECK(lastResort != NULL);
    if (lastResort != NULL) {
        CTFontRef font = CTFontCreateWithFontDescriptor(lastResort, 12, NULL);
        CHECK(font != NULL);
        if (font) CFRelease(font);
        CFRelease(lastResort);
    }
}

static void testPostScriptName(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("DejaVu Sans"), 12, NULL);
    CHECK(font != NULL);
    if (font == NULL)
        return;
    CFStringRef name = CTFontCopyPostScriptName(font);
    /* the PostScript name attribute is the documented meaning of the name attribute */
    CFDictionaryRef attributes = dictionary1(kCTFontPostScriptNameAttribute, name);
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(attributes);
    CFTypeRef asName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
    CHECK(asName != NULL && CFEqual(asName, name));
    if (asName) CFRelease(asName);
    CTFontRef fromDescriptor = CTFontCreateWithFontDescriptor(descriptor, 12, NULL);
    CFStringRef fromName = fromDescriptor ? CTFontCopyPostScriptName(fromDescriptor) : NULL;
    CHECK(fromName != NULL && CFEqual(fromName, name));
    if (fromName) CFRelease(fromName);
    if (fromDescriptor) CFRelease(fromDescriptor);
    /* matching on it, with it mandatory */
    CFSetRef mandatory = CFSetCreate(NULL, (const void **) &kCTFontPostScriptNameAttribute, 1, &kCFTypeSetCallBacks);
    CTFontDescriptorRef match = CTFontDescriptorCreateMatchingFontDescriptor(descriptor, mandatory);
    CHECK(match != NULL);
    if (match) CFRelease(match);
    CFRelease(mandatory);
    CFRelease(descriptor);
    CFRelease(attributes);

    /* and the font's descriptor answers it, and its CSS weight (OS/2 usWeightClass scale) */
    CTFontDescriptorRef own = CTFontCopyFontDescriptor(font);
    CFTypeRef ps = CTFontDescriptorCopyAttribute(own, kCTFontPostScriptNameAttribute);
    CHECK(ps != NULL && CFEqual(ps, name));
    if (ps) CFRelease(ps);
    CFNumberRef cssWeight = CTFontDescriptorCopyAttribute(own, kCTFontCSSWeightAttribute);
    double value = 0;
    CHECK(cssWeight != NULL && CFNumberGetValue(cssWeight, kCFNumberDoubleType, &value) && fabs(value - 400) < 1);
    if (cssWeight) CFRelease(cssWeight);
    CFRelease(own);
    CFRelease(name);
    CFRelease(font);
}

int main(void) {
    testUIType();
    testTextStyles();
    testOptions();
    testCSSFamilies();
    testPostScriptName();
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
