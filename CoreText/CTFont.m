/* Copyright (c) 2008 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreText/CTFont.h>
#import <CoreText/CoreText.h>
#import <CoreText/KTFont.h>
#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGFont.h>
#import <Onyx2D/O2Font.h>
#import <Onyx2D/O2Font_freetype.h>
#import <objc/runtime.h>
#import "KTFontDescriptor.h"

// CTFontRef and NSFont are toll-free bridged. AppKit's NSFont wraps a
// KTFont, so an NSFont passed to these functions is unwrapped first.
static KTFont *ktFont(CTFontRef font) {
    id object = (id) font;
    if (object != nil && ![object isKindOfClass: [KTFont class]] &&
        [object respondsToSelector: @selector(_coreTextFont)])
        return (KTFont *) [object performSelector: @selector(_coreTextFont)];
    return (KTFont *) object;
}

// The explicit cascade list (kCTFontCascadeListAttribute) a font was created
// with: an array of font descriptors, kept with the font object.
static char fontCascadeKey;

static NSArray *fontCascade(CTFontRef font) {
    return objc_getAssociatedObject(ktFont(font), &fontCascadeKey);
}

static CTFontRef fontWithCascade(CTFontRef font, id cascade) {
    if (font != NULL && [cascade isKindOfClass: [NSArray class]] && [cascade count] > 0)
        objc_setAssociatedObject(ktFont(font), &fontCascadeKey, cascade,
                                 OBJC_ASSOCIATION_COPY);
    return font;
}

static id cascadeOfAttributes(CTFontDescriptorRef attributes) {
    if (attributes == NULL)
        return nil;
    return [(id) CTFontDescriptorCopyAttribute(attributes, kCTFontCascadeListAttribute)
            autorelease];
}

static CTFontRef createFont(CGFontRef graphicsFont, CGFloat size) {
    // A size of 0 means the default size of 12 points.
    if (size == 0)
        size = 12;
    return (CTFontRef) [[KTFont alloc] initWithFont: graphicsFont size: size];
}

uint32_t CTGetCoreTextVersion(void)
{
    return 0x000B0000;
}

const CFStringRef kCTFontCopyrightNameKey = CFSTR("CTFontCopyrightName");
const CFStringRef kCTFontFamilyNameKey = CFSTR("CTFontFamilyName");
const CFStringRef kCTFontSubFamilyNameKey = CFSTR("CTFontSubFamilyName");
const CFStringRef kCTFontStyleNameKey = CFSTR("CTFontSubFamilyName");
const CFStringRef kCTFontUniqueNameKey = CFSTR("CTFontUniqueName");
const CFStringRef kCTFontFullNameKey = CFSTR("CTFontFullName");
const CFStringRef kCTFontVersionNameKey = CFSTR("CTFontVersionName");
const CFStringRef kCTFontPostScriptNameKey = CFSTR("CTFontPostScriptName");
const CFStringRef kCTFontTrademarkNameKey = CFSTR("CTFontTrademarkName");
const CFStringRef kCTFontManufacturerNameKey = CFSTR("CTFontManufacturerName");
const CFStringRef kCTFontDesignerNameKey = CFSTR("CTFontDesignerName");
const CFStringRef kCTFontDescriptionNameKey = CFSTR("CTFontDescriptionName");
const CFStringRef kCTFontVendorURLNameKey = CFSTR("CTFontVendorURLName");
const CFStringRef kCTFontDesignerURLNameKey = CFSTR("CTFontDesignerURLName");
const CFStringRef kCTFontLicenseNameKey = CFSTR("CTFontLicenseNameName");
const CFStringRef kCTFontLicenseURLNameKey = CFSTR("CTFontLicenseURLName");
const CFStringRef kCTFontSampleTextNameKey = CFSTR("CTFontSampleTextName");
const CFStringRef kCTFontPostScriptCIDNameKey = CFSTR("CTFontPostScriptCIDName");

const CFStringRef kCTFontVariationAxisIdentifierKey = CFSTR("NSCTVariationAxisIdentifier");
const CFStringRef kCTFontVariationAxisMinimumValueKey = CFSTR("NSCTVariationAxisMinimumValue");
const CFStringRef kCTFontVariationAxisMaximumValueKey = CFSTR("NSCTVariationAxisMaximumValue");
const CFStringRef kCTFontVariationAxisDefaultValueKey = CFSTR("NSCTVariationAxisDefaultValue");
const CFStringRef kCTFontVariationAxisNameKey = CFSTR("NSCTVariationAxisName");
const CFStringRef kCTFontVariationAxisHiddenKey = CFSTR("NSCTVariationAxisHidden");

const CFStringRef kCTFontFeatureTypeIdentifierKey = CFSTR("CTFeatureTypeIdentifier");
const CFStringRef kCTFontFeatureTypeNameKey = CFSTR("CTFeatureTypeName");
const CFStringRef kCTFontFeatureTypeExclusiveKey = CFSTR("CTFeatureTypeExclusive");
const CFStringRef kCTFontFeatureTypeSelectorsKey = CFSTR("CTFeatureTypeSelectors");
const CFStringRef kCTFontFeatureSelectorIdentifierKey = CFSTR("CTFeatureSelectorIdentifier");
const CFStringRef kCTFontFeatureSelectorNameKey = CFSTR("CTFeatureSelectorName");
const CFStringRef kCTFontFeatureSelectorDefaultKey = CFSTR("CTFeatureSelectorDefault");
const CFStringRef kCTFontFeatureSelectorSettingKey = CFSTR("CTFeatureSelectorSetting");
const CFStringRef kCTFontFeatureSampleTextKey = CFSTR("CTFeatureSampleText");
const CFStringRef kCTFontFeatureTooltipTextKey = CFSTR("CTFeatureTooltipText");

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const CGAffineTransform *matrix)
{
    if (name == NULL)
        return NULL;
    CGFontRef graphicsFont = CGFontCreateWithFontName(name);
    if (graphicsFont == NULL)
        return NULL;
    CTFontRef result = createFont(graphicsFont, size);
    CGFontRelease(graphicsFont);
    return result;
}

CTFontRef CTFontCreateWithNameAndOptions(CFStringRef name, CGFloat size,
                                         const CGAffineTransform *matrix,
                                         CTFontOptions options)
{
    return CTFontCreateWithName(name, size, matrix);
}

CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size,
                                         const CGAffineTransform *matrix)
{
    if (descriptor == NULL)
        return NULL;

    if (size == 0) {
        CFTypeRef value = CTFontDescriptorCopyAttribute(descriptor, kCTFontSizeAttribute);
        if (value != NULL) {
            if (CFGetTypeID(value) == CFNumberGetTypeID())
                CFNumberGetValue((CFNumberRef) value, kCFNumberCGFloatType, &size);
            CFRelease(value);
        }
    }

    // A descriptor from CTFontManagerCreateFontDescriptorFromData names a
    // face that is not installed; make the font from its data.
    CFDataRef data = KTFontDescriptorGetFontData(descriptor);
    if (data != NULL) {
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
        CGFontRef graphicsFont = CGFontCreateWithDataProvider(provider);
        CGDataProviderRelease(provider);
        if (graphicsFont != NULL) {
            CTFontRef result = createFont(graphicsFont, size);
            CGFontRelease(graphicsFont);
            return fontWithCascade(result, cascadeOfAttributes(descriptor));
        }
    }

    CFStringRef name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
    if (name == NULL)
        name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute);
    if (name == NULL)
        return NULL;
    CTFontRef result = CTFontCreateWithName(name, size, matrix);
    CFRelease(name);
    return fontWithCascade(result, cascadeOfAttributes(descriptor));
}

CTFontRef CTFontCreateWithFontDescriptorAndOptions(CTFontDescriptorRef descriptor, CGFloat size,
                                                   const CGAffineTransform *matrix,
                                                   CTFontOptions options)
{
    return CTFontCreateWithFontDescriptor(descriptor, size, matrix);
}

CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType uiFontType,
                                        CGFloat size, CFStringRef language)
{
    return (CTFontRef)[[KTFont alloc] initWithUIFontType: uiFontType
                                         size: size
                                     language: (NSString*)language];
}

CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size,
                                         const CGAffineTransform *matrix,
                                         CTFontDescriptorRef attributes)
{
    KTFont *object = ktFont(font);
    if (object == nil)
        return NULL;
    if (size == 0)
        size = [object pointSize];

    // The copy keeps the cascade list unless the attributes supply another.
    id cascade = cascadeOfAttributes(attributes) ?: fontCascade(font);

    if (attributes != NULL) {
        CFStringRef name = CTFontDescriptorCopyAttribute(attributes, kCTFontNameAttribute);
        if (name != NULL) {
            CTFontRef result = CTFontCreateWithName(name, size, matrix);
            CFRelease(name);
            if (result != NULL)
                return fontWithCascade(result, cascade);
        }
    }

    CGFontRef graphicsFont = [object copyGraphicsFont];
    CTFontRef result = createFont(graphicsFont, size);
    CGFontRelease(graphicsFont);
    return fontWithCascade(result, cascade);
}

CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size,
                                             const CGAffineTransform *matrix,
                                             CTFontSymbolicTraits symTraitValue, 
                                             CTFontSymbolicTraits symTraitMask)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateCopyWithFamily(CTFontRef font, CGFloat size,
                                     const CGAffineTransform *matrix, CFStringRef family)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateForString(CTFontRef currentFont, CFStringRef string, CFRange range)
{
    return CTFontCreateForStringWithLanguage(currentFont, string, range, NULL);
}

// Whether the font has a glyph for every character of the UTF-16 text.
static bool fontCoversText(CTFontRef font, const UniChar *characters, CFIndex count) {
    CGGlyph *glyphs = calloc((size_t) count, sizeof(*glyphs));
    if (glyphs == NULL)
        return false;
    bool covers = CTFontGetGlyphsForCharacters(font, characters, glyphs, count);
    free(glyphs);
    return covers;
}

CTFontRef CTFontCreateForStringWithLanguage(CTFontRef currentFont, CFStringRef string,
                                            CFRange range, CFStringRef language)
{
    CFIndex length = string != NULL ? CFStringGetLength(string) : 0;
    if (ktFont(currentFont) == nil || string == NULL || range.location < 0 ||
        range.length < 0 || range.location > length ||
        range.length > length - range.location)
        return NULL;
    if (range.length == 0)
        return (CTFontRef) CFRetain(currentFont);
    if ((size_t) range.length > SIZE_MAX / sizeof(uint32_t))
        return NULL;

    UniChar *characters = calloc((size_t) range.length, sizeof(*characters));
    uint32_t *codePoints = calloc((size_t) range.length, sizeof(*codePoints));
    if (characters == NULL || codePoints == NULL) {
        free(characters);
        free(codePoints);
        return NULL;
    }
    CFStringGetCharacters(string, range, characters);

    // The code points to cover; text with an unpaired surrogate has none.
    size_t count = 0;
    for (CFIndex i = 0; i < range.length; i++) {
        uint32_t scalar = characters[i];
        if (scalar >= 0xD800 && scalar <= 0xDBFF && i + 1 < range.length &&
            characters[i + 1] >= 0xDC00 && characters[i + 1] <= 0xDFFF) {
            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (characters[++i] - 0xDC00);
        } else if (scalar >= 0xD800 && scalar <= 0xDFFF) {
            free(characters);
            free(codePoints);
            return NULL;
        }
        codePoints[count++] = scalar;
    }

    CTFontRef result = NULL;
    if (fontCoversText(currentFont, characters, range.length)) {
        result = (CTFontRef) CFRetain(currentFont);
        goto done;
    }

    // Explicit cascade descriptors are tried in the order given. A candidate
    // must cover the text itself; its own cascade list is not followed.
    for (id descriptor in fontCascade(currentFont)) {
        CTFontRef candidate = CTFontCreateWithFontDescriptor(
                (CTFontDescriptorRef) descriptor, CTFontGetSize(currentFont), NULL);
        if (candidate == NULL)
            continue;
        if (fontCoversText(candidate, characters, range.length)) {
            result = candidate;
            goto done;
        }
        CFRelease(candidate);
    }

    // Otherwise ask the font system for any face covering the text, ranked by
    // the style of the current font and the language, if one is given.
    CGFontRef graphicsFont = [ktFont(currentFont) copyGraphicsFont];
    FT_Face baseFace = NULL;
    if ([(id) graphicsFont isKindOfClass: [O2Font_freetype class]])
        baseFace = [(O2Font_freetype *) graphicsFont face];
    const char *languageName = NULL;
    if (language != NULL && CFGetTypeID(language) == CFStringGetTypeID())
        languageName = [(NSString *) language UTF8String];
    O2FontRef substitute = O2FontCreateWithCodePointCoverage(codePoints, count, baseFace,
                                                              languageName);
    CGFontRelease(graphicsFont);
    if (substitute != nil) {
        result = createFont((CGFontRef) substitute, CTFontGetSize(currentFont));
        O2FontRelease(substitute);
    }

done:
    free(characters);
    free(codePoints);
    return result;
}

CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef font)
{
    KTFont *object = ktFont(font);
    if (object == nil)
        return NULL;

    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSString *name = (NSString *) CTFontCopyPostScriptName(font);
    NSString *family = (NSString *) CTFontCopyFamilyName(font);
    NSDictionary *traits = (NSDictionary *) CTFontCopyTraits(font);
    if (name != nil)
        [attributes setObject: name forKey: (NSString *) kCTFontNameAttribute];
    if (family != nil)
        [attributes setObject: family forKey: (NSString *) kCTFontFamilyNameAttribute];
    if (traits != nil)
        [attributes setObject: traits forKey: (NSString *) kCTFontTraitsAttribute];
    [attributes setObject: [NSNumber numberWithDouble: [object pointSize]]
                   forKey: (NSString *) kCTFontSizeAttribute];
    NSArray *cascade = fontCascade(font);
    if (cascade != nil)
        [attributes setObject: cascade forKey: (NSString *) kCTFontCascadeListAttribute];
    [name release];
    [family release];
    [traits release];
    return CTFontDescriptorCreateWithAttributes((CFDictionaryRef) attributes);
}

CFTypeRef CTFontCopyAttribute(CTFontRef font, CFStringRef attribute)
{
    CTFontDescriptorRef descriptor = CTFontCopyFontDescriptor(font);
    if (descriptor == NULL)
        return NULL;
    CFTypeRef value = CTFontDescriptorCopyAttribute(descriptor, attribute);
    CFRelease(descriptor);
    return value;
}

CGFloat CTFontGetSize(CTFontRef self) {
    return [ktFont(self) pointSize];
}

CGAffineTransform CTFontGetMatrix(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return CGAffineTransformIdentity;
}

static uint16_t readUInt16(const UInt8 *bytes) {
    return (uint16_t) ((bytes[0] << 8) | bytes[1]);
}

// Traits from the OS/2 table (weight and width class, fsSelection) and the
// post table (italic angle, fixed pitch) of the face, as in the OpenType
// specification.
static CTFontSymbolicTraits fontTraits(CTFontRef font, CGFloat *weight,
                                       CGFloat *width, CGFloat *slant)
{
    // The NSFontWeight values of the nine OS/2 weight classes.
    static const CGFloat weights[] = { -0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4,
                                       0.56, 0.62 };
    unsigned int weightClass = 400, widthClass = 5;
    CTFontSymbolicTraits traits = 0;
    double italicAngle = 0;

    CFDataRef table = CTFontCopyTable(font, 'OS/2', kCTFontTableOptionNoOptions);
    if (table != NULL && CFDataGetLength(table) >= 64) {
        const UInt8 *bytes = CFDataGetBytePtr(table);
        weightClass = readUInt16(bytes + 4);
        widthClass = readUInt16(bytes + 6);
        uint16_t selection = readUInt16(bytes + 62);
        if (selection & 0x0001)
            traits |= kCTFontTraitItalic;
        if (selection & 0x0020)
            traits |= kCTFontTraitBold;
    }
    if (table != NULL)
        CFRelease(table);

    table = CTFontCopyTable(font, 'post', kCTFontTableOptionNoOptions);
    if (table != NULL && CFDataGetLength(table) >= 16) {
        const UInt8 *bytes = CFDataGetBytePtr(table);
        int32_t fixed = (int32_t) (((uint32_t) readUInt16(bytes + 4) << 16) |
                                   readUInt16(bytes + 6));
        italicAngle = fixed / 65536.0;
        if (bytes[12] || bytes[13] || bytes[14] || bytes[15])
            traits |= kCTFontTraitMonoSpace;
    }
    if (table != NULL)
        CFRelease(table);

    if (weightClass < 100)
        weightClass = 100;
    if (weightClass > 900)
        weightClass = 900;
    unsigned int index = weightClass / 100 - 1;
    *weight = weights[index];
    if (index < 8)
        *weight += (weights[index + 1] - weights[index]) * (weightClass % 100) / 100.0;
    if (weightClass >= 700)
        traits |= kCTFontTraitBold;

    if (widthClass < 1 || widthClass > 9)
        widthClass = 5;
    *width = ((CGFloat) widthClass - 5) / 4;
    if (widthClass < 5)
        traits |= kCTFontTraitCondensed;
    if (widthClass > 5)
        traits |= kCTFontTraitExpanded;

    // The slant trait is 1.0 for 30 degrees clockwise; the post table
    // gives the angle counter-clockwise from vertical.
    *slant = -italicAngle / 30.0;
    if (*slant > 1)
        *slant = 1;
    if (*slant < -1)
        *slant = -1;
    if (italicAngle != 0)
        traits |= kCTFontTraitItalic;

    return traits;
}

CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef font)
{
    CGFloat weight, width, slant;
    if (ktFont(font) == nil)
        return 0;
    return fontTraits(font, &weight, &width, &slant);
}

CFDictionaryRef CTFontCopyTraits(CTFontRef font)
{
    if (ktFont(font) == nil)
        return NULL;
    CGFloat weight, width, slant;
    CTFontSymbolicTraits symbolic = fontTraits(font, &weight, &width, &slant);
    NSDictionary *traits = [[NSDictionary alloc] initWithObjectsAndKeys:
            [NSNumber numberWithUnsignedInt: symbolic], (NSString *) kCTFontSymbolicTrait,
            [NSNumber numberWithDouble: weight], (NSString *) kCTFontWeightTrait,
            [NSNumber numberWithDouble: width], (NSString *) kCTFontWidthTrait,
            [NSNumber numberWithDouble: slant], (NSString *) kCTFontSlantTrait,
            nil];
    return (CFDictionaryRef) traits;
}

CFArrayRef CTFontCopyDefaultCascadeListForLanguages(CTFontRef font, CFArrayRef languagePrefList)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringRef CTFontCopyPostScriptName(CTFontRef font)
{
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return NULL;
    CFStringRef name = CGFontCopyPostScriptName(graphicsFont);
    CGFontRelease(graphicsFont);
    return name;
}

CFStringRef CTFontCopyFamilyName(CTFontRef font)
{
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return NULL;
    CFStringRef name = O2FontCopyFamilyName((O2FontRef) graphicsFont);
    CGFontRelease(graphicsFont);
    return name;
}

static CFStringRef copyStyleName(CTFontRef font)
{
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return NULL;
    CFStringRef name = O2FontCopyStyleName((O2FontRef) graphicsFont);
    CGFontRelease(graphicsFont);
    return name;
}

CFStringRef CTFontCopyFullName(CTFontRef self) {
    KTFont *object = ktFont(self);
    return object ? [object copyName] : NULL;
}

CFStringRef CTFontCopyDisplayName(CTFontRef font)
{
    return CTFontCopyFullName(font);
}

CFStringRef _Nullable CTFontCopyName(CTFontRef font, CFStringRef nameKey)
{
    if (ktFont(font) == nil || nameKey == NULL)
        return NULL;
    if (CFEqual(nameKey, kCTFontPostScriptNameKey))
        return CTFontCopyPostScriptName(font);
    if (CFEqual(nameKey, kCTFontFamilyNameKey))
        return CTFontCopyFamilyName(font);
    if (CFEqual(nameKey, kCTFontFullNameKey))
        return CTFontCopyFullName(font);
    if (CFEqual(nameKey, kCTFontStyleNameKey))
        return copyStyleName(font);
    return NULL;
}

CFStringRef CTFontCopyLocalizedName(CTFontRef font, CFStringRef nameKey,
                                    CFStringRef  _Nullable *actualLanguage)
{
    // Only the canonical name is available and its language is unknown; callers
    // such as Chromium read *actualLanguage whenever it is non-NULL.
    if (actualLanguage) *actualLanguage = NULL;
    if (!font || !nameKey) return NULL;
    return CTFontCopyName(font, nameKey);
}

CFCharacterSetRef CTFontCopyCharacterSet(CTFontRef font)
{
    if (font == NULL)
        return NULL;
    return [ktFont(font) copyCharacterSet];
}

CFStringEncoding CTFontGetStringEncoding(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return CFStringGetSystemEncoding();
}

CFArrayRef CTFontCopySupportedLanguages(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CGFloat CTFontGetAscent(CTFontRef self) {
    return [ktFont(self) ascender];
}

CGFloat CTFontGetDescent(CTFontRef self) {
    return [ktFont(self) descender];
}

CGFloat CTFontGetLeading(CTFontRef self) {
    return [ktFont(self) leading];
}

unsigned int CTFontGetUnitsPerEm(CTFontRef font)
{
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return 0;
    unsigned int units = CGFontGetUnitsPerEm(graphicsFont);
    CGFontRelease(graphicsFont);
    return units;
}

CFIndex CTFontGetGlyphCount(CTFontRef font) {
    return [ktFont(font) numberOfGlyphs];
}

CGRect CTFontGetBoundingBox(CTFontRef self) {
    return [ktFont(self) boundingRect];
}

CGFloat CTFontGetUnderlinePosition(CTFontRef self) {
    return [ktFont(self) underlinePosition];
}

CGFloat CTFontGetUnderlineThickness(CTFontRef self) {
    return [ktFont(self) underlineThickness];
}

CGFloat CTFontGetSlantAngle(CTFontRef self) {
    return [ktFont(self) italicAngle];
}

CGFloat CTFontGetCapHeight(CTFontRef self) {
    return [ktFont(self) capHeight];
}

CGFloat CTFontGetXHeight(CTFontRef self) {
    return [ktFont(self) xHeight];
}

CGPathRef CTFontCreatePathForGlyph(CTFontRef self, CGGlyph glyph,
                                   CGAffineTransform *xform)
{
    return (CGPathRef) [ktFont(self) createPathForGlyph: glyph transform: xform];
}

CFStringRef CTFontCopyNameForGlyph(CTFontRef font, CGGlyph glyph)
{
    if (font == NULL)
        return NULL;
    CGFontRef cgFont = [ktFont(font) copyGraphicsFont];
    if (cgFont == NULL)
        return NULL;
    CFStringRef name = glyph < CGFontGetNumberOfGlyphs(cgFont)
            ? CGFontCopyGlyphNameForGlyph(cgFont, glyph)
            : NULL;
    CGFontRelease(cgFont);
    return name;
}

CGGlyph CTFontGetGlyphWithName(CTFontRef font, CFStringRef glyphName)
{
    if (font == NULL || glyphName == NULL)
        return CGNullGlyph;
    CGFontRef cgFont = [ktFont(font) copyGraphicsFont];
    if (cgFont == NULL)
        return CGNullGlyph;
    CGGlyph glyph = CGFontGetGlyphWithGlyphName(cgFont, glyphName);
    CGFontRelease(cgFont);
    return glyph;
}

CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef font, CTFontOrientation orientation,
                                       const CGGlyph *glyphs, CGRect *boundingRects,
                                       CFIndex count)
{
    if (glyphs == NULL || count <= 0)
        return CGRectZero;
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return CGRectZero;

    int units = CGFontGetUnitsPerEm(graphicsFont);
    CGFloat scale = units > 0 ? CTFontGetSize(font) / units : 0;
    CGRect total = CGRectNull;
    for (CFIndex i = 0; i < count; i++) {
        O2Rect bounds = [(O2Font *) graphicsFont boundingRectForGlyph: glyphs[i]];
        CGRect rect = CGRectMake(bounds.origin.x * scale, bounds.origin.y * scale,
                                 bounds.size.width * scale,
                                 bounds.size.height * scale);
        if (boundingRects != NULL)
            boundingRects[i] = rect;
        total = CGRectUnion(total, rect);
    }
    CGFontRelease(graphicsFont);
    return total;
}

double CTFontGetAdvancesForGlyphs(CTFontRef font, CTFontOrientation orientation,
                                const CGGlyph *glyphs, CGSize *advances,
                                CFIndex count)
{
    KTFont *object = ktFont(font);
    if (object == nil || glyphs == NULL || count <= 0)
        return 0;

    // The advances array is optional; the total is returned either way.
    double sum = 0;
    for (CFIndex i = 0; i < count; i++) {
        CGSize advance;
        [object getAdvancements: &advance forGlyphs: &glyphs[i] count: 1];
        if (advances != NULL)
            advances[i] = advance;
        sum += advance.width;
    }

    return sum;
}

CGRect CTFontGetOpticalBoundsForGlyphs(CTFontRef font, const CGGlyph *glyphs,
                                       CGRect *boundingRects, CFIndex count,
                                       CFOptionFlags options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return CGRectMake(0, 0, 0, 0);
}

void CTFontGetVerticalTranslationsForGlyphs(CTFontRef font, const CGGlyph *glyphs,
                                            CGSize *translations, CFIndex count)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

CFArrayRef CTFontCopyVariationAxes(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFDictionaryRef CTFontCopyVariation(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopyFeatures(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopyFeatureSettings(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

bool CTFontGetGlyphsForCharacters(CTFontRef font, const UniChar *characters,
                                  CGGlyph *glyphs, CFIndex count)
{
    if (count < 0)
        return false;
    if (count == 0)
        return true;
    if (font == NULL || characters == NULL || glyphs == NULL)
        return false;

    [ktFont(font) getGlyphs: glyphs forCharacters: characters length: count];

    // The result says whether every character has a glyph. The low half of a
    // surrogate pair is reported with glyph 0 (UTF-16 indexing is kept), so it
    // is not a missing glyph.
    bool convertedAll = true;
    for (CFIndex i = 0; i < count; i++) {
        bool paired = characters[i] >= 0xD800 && characters[i] <= 0xDBFF &&
                i + 1 < count && characters[i + 1] >= 0xDC00 &&
                characters[i + 1] <= 0xDFFF;
        if (glyphs[i] == 0)
            convertedAll = false;
        if (paired)
            i++;
    }
    return convertedAll;
}

void CTFontDrawGlyphs(CTFontRef font, const CGGlyph *glyphs, const CGPoint *positions,
                      size_t count, CGContextRef context)
{
    if (context == NULL || glyphs == NULL || positions == NULL || count == 0)
        return;
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return;
    CGContextSaveGState(context);
    CGContextSetFont(context, graphicsFont);
    CGContextSetFontSize(context, CTFontGetSize(font));
    CGContextShowGlyphsAtPositions(context, glyphs, positions, count);
    CGContextRestoreGState(context);
    // QUIRK: the font and size used for drawing stay set in the context
    // afterwards; the text matrix and text position are left as they were.
    // Not documented. Evidence: black-box observation on macOS 26.7.3
    // (tier 2, MC12: a plain CGContextShowGlyphsAtPositions after
    // CTFontDrawGlyphs draws with the CTFont's font and size).
    // Test: coretext-draw-glyphs-state.m (test_quirk_font_and_size_stay_set)
    CGContextSetFont(context, graphicsFont);
    CGContextSetFontSize(context, CTFontGetSize(font));
    CGFontRelease(graphicsFont);
}

CFIndex CTFontGetLigatureCaretPositions(CTFontRef font, CGGlyph glyph, CGFloat *positions,
                                        CFIndex maxPositions)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return -1;
}

CGFontRef CTFontCopyGraphicsFont(CTFontRef font, CTFontDescriptorRef _Nullable *attributes)
{
    if (attributes != NULL)
        *attributes = NULL;
    KTFont *object = ktFont(font);
    if (object == nil)
        return NULL;
    return [object copyGraphicsFont];
}

CTFontRef
CTFontCreateWithGraphicsFont(CGFontRef cgFont, CGFloat size,
                             CGAffineTransform *xform,
                             CTFontDescriptorRef attributes)
{
    if (cgFont == NULL)
        return NULL;
    return fontWithCascade(createFont(cgFont, size), cascadeOfAttributes(attributes));
}

ATSFontRef CTFontGetPlatformFont(CTFontRef font, CTFontDescriptorRef  _Nullable *attributes)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return 0;
}

CTFontRef CTFontCreateWithPlatformFont(ATSFontRef platformFont, CGFloat size,
                                       const CGAffineTransform *matrix,
                                       CTFontDescriptorRef attributes)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateWithQuickdrawInstance(ConstStr255Param name, int16_t identifier,
                                            uint8_t style, CGFloat size)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopyAvailableTables(CTFontRef font, CTFontTableOptions options)
{
    // Only native tables exist, so excluding synthetic ones changes nothing.
    if (options & ~kCTFontTableOptionExcludeSynthetic)
        return NULL;
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return NULL;
    CFArrayRef tags = CGFontCopyTableTags(graphicsFont);
    CGFontRelease(graphicsFont);
    return tags;
}

CFDataRef CTFontCopyTable(CTFontRef font, CTFontTableTag table, CTFontTableOptions options)
{
    if (options & ~kCTFontTableOptionExcludeSynthetic)
        return NULL;
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return NULL;
    CFDataRef data = CGFontCopyTableForTag(graphicsFont, table);
    CGFontRelease(graphicsFont);
    return data;
}

CFTypeID CTFontGetTypeID(void)
{
    return (CFTypeID) [KTFont self];
}
