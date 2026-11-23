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
#import "CTFontSPI.h"
#import "KTCoreTextInternal.h"
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

// The vertical-orientation trait a copy was asked for by CTFontCreateCopyWithSymbolicTraits. A face
// does not carry it (the traits come from the font tables), so it is kept with the font object.
static char fontVerticalKey;

static CTFontRef fontWithVertical(CTFontRef font, BOOL vertical) {
    if (font != NULL && vertical)
        objc_setAssociatedObject(ktFont(font), &fontVerticalKey, (id) kCFBooleanTrue,
                                 OBJC_ASSOCIATION_RETAIN);
    return font;
}

static id cascadeOfAttributes(CTFontDescriptorRef attributes) {
    if (attributes == NULL)
        return nil;
    return [(id) CTFontDescriptorCopyAttribute(attributes, kCTFontCascadeListAttribute)
            autorelease];
}

// The transformation matrix a font was created with, kept with the font object as the bytes of a
// CGAffineTransform. A font made without one has none stored and reads as the identity matrix.
static char fontMatrixKey;

static CGAffineTransform fontMatrix(CTFontRef font) {
    CGAffineTransform matrix = CGAffineTransformIdentity;
    NSData *data = objc_getAssociatedObject(ktFont(font), &fontMatrixKey);
    if ([data length] == sizeof(matrix))
        [data getBytes: &matrix length: sizeof(matrix)];
    return matrix;
}

// Observed on macOS 10.14.4 (x86_64, i386) and 26.7.3 (black-box, tier 2; probe 8 of the cristim
// batch10b evidence): CTFontGetMatrix returns the matrix the font was created with without its
// translation (tx and ty read 0). Test: coretext-font-matrix.
static CTFontRef fontWithMatrix(CTFontRef font, const CGAffineTransform *matrix) {
    if (font != NULL && matrix != NULL) {
        CGAffineTransform linear = *matrix;
        linear.tx = linear.ty = 0;
        if (!CGAffineTransformIsIdentity(linear))
            objc_setAssociatedObject(ktFont(font), &fontMatrixKey,
                                     [NSData dataWithBytes: &linear length: sizeof(linear)],
                                     OBJC_ASSOCIATION_RETAIN);
    }
    return font;
}

static O2Font_freetype *copyFreeTypeFont(CTFontRef font) {
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if ([(id) graphicsFont isKindOfClass: [O2Font_freetype class]])
        return (O2Font_freetype *) graphicsFont;
    if (graphicsFont != NULL)
        CGFontRelease(graphicsFont);
    return nil;
}

static CTFontRef createFont(CGFontRef graphicsFont, CGFloat size);

// Applies the kCTFontVariationAttribute of a descriptor to a font that is
// owned by the caller. Returns the font itself when there is nothing to apply
// (no variation, or a font without variation axes), else a new owned font that
// keeps the size and the cascade list, and releases the old one.
static CTFontRef fontWithVariationOfAttributes(CTFontRef font, CTFontDescriptorRef attributes) {
    if (font == NULL || attributes == NULL)
        return font;
    NSDictionary *variation =
            [(id) CTFontDescriptorCopyAttribute(attributes, kCTFontVariationAttribute) autorelease];
    if (![variation isKindOfClass: [NSDictionary class]] || [variation count] == 0)
        return font;
    O2Font_freetype *freeType = copyFreeTypeFont(font);
    O2Font_freetype *varied = [freeType copyWithVariation: variation];
    [freeType release];
    if (varied == nil)
        return font;
    CTFontRef result = createFont((CGFontRef) varied, CTFontGetSize(font));
    [varied release];
    if (result == NULL)
        return font;
    fontWithCascade(result, fontCascade(font));
    CGAffineTransform matrix = fontMatrix(font);
    fontWithMatrix(result, &matrix);
    CFRelease(font);
    return result;
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
    // The documentation gives the identity matrix for NULL and CTFontGetMatrix returns what was given. It
    // does not say that the matrix changes the font's metrics or glyph outlines, so only the matrix is kept.
    return fontWithMatrix(result, matrix);
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
        CGFontRef graphicsFont = (CGFontRef) O2FontCreateWithDataProviderAndFaceIndex(
                (O2DataProviderRef) provider, KTFontDescriptorGetFaceIndex(descriptor));
        CGDataProviderRelease(provider);
        if (graphicsFont != NULL) {
            CTFontRef result = fontWithMatrix(createFont(graphicsFont, size), matrix);
            CGFontRelease(graphicsFont);
            result = fontWithVariationOfAttributes(result, descriptor);
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
    result = fontWithVariationOfAttributes(result, descriptor);
    return fontWithCascade(result, cascadeOfAttributes(descriptor));
}

CTFontRef CTFontCreateWithFontDescriptorAndOptions(CTFontDescriptorRef descriptor, CGFloat size,
                                                   const CGAffineTransform *matrix,
                                                   CTFontOptions options)
{
    return CTFontCreateWithFontDescriptor(descriptor, size, matrix);
}

// Set on the fonts made for the system UI font types; see CTFontDescriptorIsSystemUIFont().
static char systemUIFontKey;

CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType uiFontType,
                                        CGFloat size, CFStringRef language)
{
    KTFont *font = [[KTFont alloc] initWithUIFontType: uiFontType
                                         size: size
                                     language: (NSString*)language];
    // The user and the user fixed-pitch fonts are not system UI fonts.
    if (font != nil && uiFontType != kCTFontUIFontUser && uiFontType != kCTFontUIFontUserFixedPitch)
        objc_setAssociatedObject(font, &systemUIFontKey, (id) kCFBooleanTrue,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return (CTFontRef) font;
}

static CTFontRef copyWithAttributes(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                    CTFontDescriptorRef attributes)
{
    KTFont *object = ktFont(font);
    if (object == nil)
        return NULL;
    if (size == 0)
        size = [object pointSize];
    // A NULL matrix keeps the original font's matrix.
    CGAffineTransform originalMatrix = fontMatrix(font);
    if (matrix == NULL)
        matrix = &originalMatrix;

    // The copy keeps the cascade list unless the attributes supply another.
    id cascade = cascadeOfAttributes(attributes) ?: fontCascade(font);

    if (attributes != NULL) {
        CFStringRef name = CTFontDescriptorCopyAttribute(attributes, kCTFontNameAttribute);
        if (name != NULL) {
            CTFontRef result = CTFontCreateWithName(name, size, matrix);
            CFRelease(name);
            if (result != NULL) {
                result = fontWithVariationOfAttributes(result, attributes);
                return fontWithCascade(result, cascade);
            }
        }
    }

    CGFontRef graphicsFont = [object copyGraphicsFont];
    CTFontRef result = fontWithMatrix(createFont(graphicsFont, size), matrix);
    CGFontRelease(graphicsFont);
    result = fontWithVariationOfAttributes(result, attributes);
    return fontWithCascade(result, cascade);
}

CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size,
                                         const CGAffineTransform *matrix,
                                         CTFontDescriptorRef attributes)
{
    CTFontRef result = copyWithAttributes(font, size, matrix, attributes);
    // QUIRK: the copy keeps the vertical trait of the original; see CTFontCreateCopyWithSymbolicTraits.
    if (result != NULL && ktFont(font) != nil)
        fontWithVertical(result, (CTFontGetSymbolicTraits(font) & kCTFontTraitVertical) != 0);
    return result;
}

// Observed on macOS 26.7.3 and Mac OS X 10.14.4 (black-box, through the public API, identical): within one
// family a copy with the italic, bold, expanded, condensed or color-glyph trait set differently from the
// original's is looked up among the faces and gives NULL when there is none (Helvetica has no expanded,
// condensed or color-glyph face); setting the monospace, UI-optimized, composite or class-mask bits leaves the
// font as it is, so they are not compared. The vertical trait is not compared either, but is carried
// into the copy (see CTFontCreateCopyWithSymbolicTraits). Test: coretext-font-copy-with-traits-and-family.
static const CTFontSymbolicTraits sameFamilyStyleTraits =
        kCTFontTraitItalic | kCTFontTraitBold | kCTFontTraitExpanded | kCTFontTraitCondensed |
        kCTFontTraitColorGlyphs;
// GUESS: moving to another family keeps only what a face of any family can differ in, the slant
// and the boldness (observed: Helvetica to Courier keeps the slant and bold bits, and the target family's
// monospace trait is its own). Monospace, condensed and expanded describe a whole family, so requiring them to
// equal the original's would find nothing across families.
static const CTFontSymbolicTraits crossFamilyStyleTraits = kCTFontTraitItalic | kCTFontTraitBold;

static CGFloat weightOfFont(CTFontRef font) {
    CGFloat weight = 0;
    CFDictionaryRef traits = CTFontCopyTraits(font);
    CFNumberRef number = traits != NULL ? CFDictionaryGetValue(traits, kCTFontWeightTrait) : NULL;
    if (number != NULL)
        CFNumberGetValue(number, kCFNumberCGFloatType, &weight);
    if (traits != NULL)
        CFRelease(traits);
    return weight;
}

static BOOL fontHasPostScriptName(CTFontRef font, CFStringRef name) {
    CFStringRef own = CTFontCopyPostScriptName(font);
    BOOL same = own != NULL && name != NULL && CFEqual(own, name);
    if (own != NULL)
        CFRelease(own);
    return same;
}

// A new font of `family` whose style traits, over the bits in `compared`, are those of `wanted`,
// or NULL when the family has no such face. A size of 0 keeps the size of the original and (with keepMatrix) a NULL
// matrix keeps the original's matrix. The cascade list of the original is carried over to
// the copy (observed on macOS 26.7.3 and Mac OS X 10.14.4, together with the feature settings, which fonts here do
// not have); the variation is not.
// GUESS: when several faces have the wanted traits (a family with Light, Regular and Medium
// has three non-bold faces) the one whose weight trait is nearest to `targetWeight` is taken,
// the first listed among equals. The documentation names no rule.
// QUIRK: a request that changes no trait (an empty mask) returns the original face itself, whichever other
// faces are as near in weight. Otherwise the first listed of equally near faces wins.
// Not documented. Evidence: black-box observation of CTFontCreateCopyWithSymbolicTraits with value 0 and
// mask 0 on macOS 26.7.3 and Mac OS X 10.14.4 (x86_64, i386; tier 2): all 66 faces of the probe return
// themselves, among them Avenir-Roman beside the equally weighted Avenir-Book (probe 639.E.nochange). With a
// mask the two versions differ (Avenir-Roman with bold cleared gives Avenir-Roman on 26.7.3 and Avenir-Book on
// 10.14.4), and CTFontCreateCopyWithFamily into the face's own family gives Avenir-Book on both, so neither is
// reproduced. Test: coretext-font-copy-with-traits-and-family (checkEmptyMaskKeepsTheFace).
static CTFontRef copyFontInFamily(CTFontRef font, CGFloat size, const CGAffineTransform *matrix, BOOL keepMatrix,
                                  CFStringRef family, CTFontSymbolicTraits wanted,
                                  CTFontSymbolicTraits compared, CGFloat targetWeight, BOOL originalWinsTies)
{
    if (ktFont(font) == nil || family == NULL)
        return NULL;
    if (size == 0)
        size = CTFontGetSize(font);
    CGAffineTransform originalMatrix = fontMatrix(font);
    if (matrix == NULL && keepMatrix)
        matrix = &originalMatrix;

    const void *keys[] = { kCTFontFamilyNameAttribute };
    const void *values[] = { family };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef query = CTFontDescriptorCreateWithAttributes(attributes);
    CFRelease(attributes);
    CFArrayRef faces = CTFontDescriptorCreateMatchingFontDescriptors(query, NULL);
    CFRelease(query);
    if (faces == NULL)
        return NULL;

    CTFontRef best = NULL;
    CGFloat bestDistance = 0;
    CFStringRef originalName = CTFontCopyPostScriptName(font);
    for (CFIndex i = 0; i < CFArrayGetCount(faces); i++) {
        CTFontRef candidate = CTFontCreateWithFontDescriptor(
                (CTFontDescriptorRef) CFArrayGetValueAtIndex(faces, i), size, matrix);
        if (candidate == NULL)
            continue;
        if ((CTFontGetSymbolicTraits(candidate) & compared) != (wanted & compared)) {
            CFRelease(candidate);
            continue;
        }
        CGFloat distance = fabs(weightOfFont(candidate) - targetWeight);
        BOOL wins = best == NULL || distance < bestDistance - 1e-9;
        if (!wins && originalWinsTies && distance <= bestDistance + 1e-9)
            wins = fontHasPostScriptName(candidate, originalName);
        if (!wins) {
            CFRelease(candidate);
            continue;
        }
        if (best != NULL)
            CFRelease(best);
        best = candidate;
        bestDistance = distance;
    }
    CFRelease(faces);
    if (originalName != NULL)
        CFRelease(originalName);
    return fontWithCascade(best, fontCascade(font));
}

CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size,
                                             const CGAffineTransform *matrix,
                                             CTFontSymbolicTraits symTraitValue, 
                                             CTFontSymbolicTraits symTraitMask)
{
    if (ktFont(font) == nil)
        return NULL;
    // QUIRK: a negative size keeps the original's size, like the documented 0.0. Evidence:
    // black-box observation of CTFontCreateCopyWithSymbolicTraits on macOS 26.7.3 and Mac OS X 10.14.4
    // (identical, tier 2) and on 26.1 (arm64): Helvetica at 17 with size -5 gives a copy of size 17 (probe
    // 639.B.size). Not probed for CTFontCreateCopyWithFamily, which is left as it is. Test: coretext-font-copy-with-traits-and-family.
    if (size < 0)
        size = 0;
    // GUESS: the documentation gives "the value of the symbolic traits" and "the mask bits"
    // without saying how they combine. The mask is taken to select the bits of the value that
    // replace the original's traits; the original's other bits stay.
    CTFontSymbolicTraits original = CTFontGetSymbolicTraits(font);
    CTFontSymbolicTraits wanted = (original & ~symTraitMask) | (symTraitValue & symTraitMask);
    // GUESS: a request that clears the bold trait aims at the regular weight (0.0 on the scale
    // of kCTFontWeightTrait). Aiming at the original's weight would turn a Black face into the
    // heaviest face that is not bold, a Semibold one. Otherwise the original's weight is kept.
    CGFloat targetWeight = ((original & kCTFontTraitBold) && !(wanted & kCTFontTraitBold))
            ? 0 : weightOfFont(font);
    CFStringRef family = CTFontCopyFamilyName(font);
    CTFontRef result = copyFontInFamily(font, size, matrix, YES, family, wanted,
                                        sameFamilyStyleTraits, targetWeight, symTraitMask == 0);
    // QUIRK: the vertical-orientation bit is not compared when looking for a face, but a request
    // that sets it under the mask is carried into the copy's symbolic traits, and once a font has it no
    // copy loses it: a request that clears it, an empty mask, a new size, a changed bold trait and
    // CTFontCreateCopyWithAttributes all keep it (CTFontCreateCopyWithFamily does not). Not documented.
    // Evidence: black-box observation on macOS 26.7.3 and Mac OS X 10.14.4 (x86_64, i386; tier 2):
    // Helvetica with value=mask=0x800 gives traits 0x80000800, and every later copy of that font reads
    // 0x80000800 (probe ctvert.c). Test: coretext-font-copy-with-traits-and-family.
    fontWithVertical(result, ((original | (symTraitValue & symTraitMask)) & kCTFontTraitVertical) != 0);
    if (family != NULL)
        CFRelease(family);
    return result;
}

CTFontRef CTFontCreateCopyWithFamily(CTFontRef font, CGFloat size,
                                     const CGAffineTransform *matrix, CFStringRef family)
{
    if (ktFont(font) == nil)
        return NULL;
    // QUIRK: a NULL matrix gives the identity matrix here, not the original's (unlike
    // CTFontCreateCopyWithSymbolicTraits and CTFontCreateCopyWithAttributes, which keep it).
    // Evidence: black-box observation on macOS 10.14.4 (x86_64, i386) and 26.7.3 (tier 2); the
    // documentation says NULL keeps the original's matrix. Test: coretext-font-matrix.
    CTFontSymbolicTraits original = CTFontGetSymbolicTraits(font);
    CTFontRef result = copyFontInFamily(font, size, matrix, NO, family, original,
                                        crossFamilyStyleTraits, weightOfFont(font), NO);
    // QUIRK, against the documented return value (a font with the original's traits in the family,
    // or NULL when none is found; flagged for the maintainer): when the family has no face with the
    // original's italic and bold traits (a bold original and a family of one regular face) the
    // family's closest face is returned, not NULL. Evidence: black-box observation of
    // CTFontCreateCopyWithFamily on macOS 26.7.3 and Mac OS X 10.14.4 (identical, tier 2) and on 26.1
    // (arm64): Helvetica-Bold into Zapfino and into Apple
    // Color Emoji gives those families' only face (probe 639.F.family). Only single-face families
    // were probed; for a family of several the order below is what the test's bold-italic case pins (it passes
    // on 26.7.3 and 10.14.4). The fewest mismatches are taken,
    // bold dropped first, then italic, then the nearest weight; the rejected alternative is to
    // ignore both at once. CTFontCreateCopyWithSymbolicTraits does return NULL for a missing trait
    // inside one family (probe 639.D.noface). Test: coretext-font-copy-with-traits-and-family.
    static const CTFontSymbolicTraits relaxed[] = { kCTFontTraitItalic, 0 };
    for (size_t i = 0; result == NULL && i < sizeof(relaxed) / sizeof(relaxed[0]); i++)
        result = copyFontInFamily(font, size, matrix, NO, family, original, relaxed[i], weightOfFont(font), NO);
    return result;
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
    if (objc_getAssociatedObject(object, &systemUIFontKey) != nil)
        [attributes setObject: (id) kCFBooleanTrue forKey: (NSString *) KTFontSystemUIAttribute];
    NSDictionary *variation = (NSDictionary *) CTFontCopyVariation(font);
    if (variation != nil)
        [attributes setObject: variation forKey: (NSString *) kCTFontVariationAttribute];
    [variation release];
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
    if (ktFont(font) == nil)
        return CGAffineTransformIdentity;
    return fontMatrix(font);
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
    if (objc_getAssociatedObject(ktFont(font), &fontVerticalKey) != nil)
        traits |= kCTFontTraitVertical;

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

CGFloat KTFontGetPairKerning(CTFontRef font, CGGlyph first, CGGlyph second)
{
    KTFont *object = ktFont(font);
    return object != nil ? [object kerningBetweenGlyph: first andGlyph: second] : 0;
}

double CTFontGetAdvancesForGlyphs(CTFontRef font, CTFontOrientation orientation,
                                const CGGlyph *glyphs, CGSize *advances,
                                CFIndex count)
{
    KTFont *object = ktFont(font);
    if (object == nil || glyphs == NULL || count <= 0)
        return 0;

    // The advances array is optional; the total is returned either way.
    // Vertical text gets the font's vertical advance as the width, and a height of 0.
    double sum = 0;
    for (CFIndex i = 0; i < count; i++) {
        CGSize advance;
        if (orientation == kCTFontOrientationVertical)
            [object getVerticalAdvancements: &advance forGlyphs: &glyphs[i] count: 1];
        else
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
    O2Font_freetype *freeType = copyFreeTypeFont(font);
    NSArray *axes = [freeType copyVariationAxes];
    [freeType release];
    if (axes == nil)
        return NULL;

    NSMutableArray *result = [[NSMutableArray alloc] init];
    for (NSDictionary *axis in axes) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        [info setObject: [axis objectForKey: @"tag"]
                 forKey: (NSString *) kCTFontVariationAxisIdentifierKey];
        [info setObject: [axis objectForKey: @"minimum"]
                 forKey: (NSString *) kCTFontVariationAxisMinimumValueKey];
        [info setObject: [axis objectForKey: @"maximum"]
                 forKey: (NSString *) kCTFontVariationAxisMaximumValueKey];
        [info setObject: [axis objectForKey: @"default"]
                 forKey: (NSString *) kCTFontVariationAxisDefaultValueKey];
        NSString *name = [axis objectForKey: @"name"];
        if (name != nil)
            [info setObject: name forKey: (NSString *) kCTFontVariationAxisNameKey];
        // Only the hidden axes carry the key.
        if ([[axis objectForKey: @"hidden"] boolValue])
            [info setObject: (id) kCFBooleanTrue
                     forKey: (NSString *) kCTFontVariationAxisHiddenKey];
        [result addObject: info];
    }
    [axes release];
    return (CFArrayRef) result;
}

CFDictionaryRef CTFontCopyVariation(CTFontRef font)
{
    O2Font_freetype *freeType = copyFreeTypeFont(font);
    NSDictionary *settings = [freeType copyVariationSettings];
    [freeType release];
    return (CFDictionaryRef) settings;
}

CFArrayRef CTFontCopyFeatures(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

// The documented result is the non-default feature settings applied to the font, or NULL when the default
// settings apply. No font made here has settings applied: creating one from a descriptor does not read the
// descriptor's feature-settings attribute, so the default settings always apply.
CFArrayRef CTFontCopyFeatureSettings(CTFontRef font)
{
    return NULL;
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

void CTFontDrawGlyphsWithAdvances(CTFontRef font, const CGGlyph *glyphs,
                                  const CGSize *advances, size_t count,
                                  CGContextRef context)
{
    if (font == NULL || glyphs == NULL || advances == NULL || count == 0 || context == NULL)
        return;
    CGFontRef graphicsFont = CTFontCopyGraphicsFont(font, NULL);
    if (graphicsFont == NULL)
        return;
    CGContextSetFont(context, graphicsFont);
    CGContextSetFontSize(context, CTFontGetSize(font));
    CGContextShowGlyphsWithAdvances(context, glyphs, advances, count);
    CGFontRelease(graphicsFont);
}

bool CTFontShouldAntiAlias(CTFontRef font)
{
    // macOS answers per font (observed on macOS 26.7.3: true for Menlo up to
    // 200 pt, false for Helvetica); Onyx2D antialiases every outline, so this
    // reports true for any font.
    return true;
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
    CTFontRef result = fontWithMatrix(createFont(cgFont, size), xform);
    return fontWithCascade(result, cascadeOfAttributes(attributes));
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

bool CTFontHasTable(CTFontRef font, CTFontTableTag table)
{
    CFDataRef data = CTFontCopyTable(font, table, kCTFontTableOptionNoOptions);
    if (data == NULL)
        return false;
    CFRelease(data);
    return true;
}

CFTypeID CTFontGetTypeID(void)
{
    return (CFTypeID) [KTFont self];
}
