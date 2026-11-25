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
#include <strings.h>
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

// Set on the fonts made for the system UI font types; see CTFontDescriptorIsSystemUIFont().
static char systemUIFontKey;
// The UI font type (an NSNumber) a font was made for; see CTFontGetUIFontType().
static char uiFontTypeKey;

// Marks a font as made for a UI font type, and as a system UI font when it is one.
static CTFontRef fontWithUIFontType(CTFontRef font, id uiFontType, bool systemUIFont)
{
    if (font == NULL)
        return font;
    if (systemUIFont)
        objc_setAssociatedObject(ktFont(font), &systemUIFontKey, (id) kCFBooleanTrue,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([uiFontType isKindOfClass: [NSNumber class]])
        objc_setAssociatedObject(ktFont(font), &uiFontTypeKey, uiFontType,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return font;
}

// A font made from a descriptor of a UI font is that UI font.
static CTFontRef fontWithUIFontTypeOfDescriptor(CTFontRef font, CTFontDescriptorRef descriptor)
{
    id type = [(id) CTFontDescriptorCopyAttribute(descriptor, KTFontUIFontTypeAttribute) autorelease];
    return fontWithUIFontType(font, type, CTFontDescriptorIsSystemUIFont(descriptor));
}

// A copy of a font in the same face keeps what it was made for.
static CTFontRef fontWithUIFontTypeOfFont(CTFontRef font, CTFontRef original)
{
    KTFont *object = ktFont(original);
    return fontWithUIFontType(font, objc_getAssociatedObject(object, &uiFontTypeKey),
                              objc_getAssociatedObject(object, &systemUIFontKey) != nil);
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
            result = fontWithUIFontTypeOfDescriptor(result, descriptor);
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
    result = fontWithUIFontTypeOfDescriptor(result, descriptor);
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
    KTFont *font = [[KTFont alloc] initWithUIFontType: uiFontType
                                         size: size
                                     language: (NSString*)language];
    // The user and the user fixed-pitch fonts are not system UI fonts.
    bool systemUIFont = uiFontType != kCTFontUIFontUser && uiFontType != kCTFontUIFontUserFixedPitch;
    return fontWithUIFontType((CTFontRef) font, [NSNumber numberWithUnsignedInt: uiFontType],
                              systemUIFont);
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
    result = fontWithUIFontTypeOfFont(result, font);
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

// The NSFontWeight values of the nine OS/2 weight classes, 100 to 900.
static const CGFloat weightClassWeights[] = { -0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62 };
static const unsigned int boldWeightClassIndex = 6;

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
    // The documentation does not say which of several faces with the wanted traits is returned.
    // QUIRK: a request that sets the bold trait on a face without it aims at the weight of the Bold
    // weight class (700, 0.4 in the table above), not at the original's weight, so a regular face
    // goes to Bold even when a Semibold or Demibold face is nearer to 0.0. A request that clears
    // the bold trait aims at the regular weight (0.0), so a Black or Heavy face does not become the
    // heaviest face that is not bold. Otherwise the original's weight is kept. Evidence: black-box
    // observation of CTFontCreateCopyWithSymbolicTraits on macOS 26.1 (arm64): AvenirNext-Regular and
    // GillSans give AvenirNext-Bold and GillSans-Bold (weight 0.4) though a face of weight 0.3 exists
    // (probe 639.E.bold-on), and AvenirNext-Heavy gives AvenirNext-Regular when bold is cleared. The
    // probe does not pin 0.4 itself: any target from about 0.35 to 0.48 gives the same faces there.
    // It needs the faces of weight 0.3 to have the bold trait (see fontTraits). Test:
    // coretext-font-copy-with-traits-and-family.
    CGFloat targetWeight = weightOfFont(font);
    if ((wanted & kCTFontTraitBold) && !(original & kCTFontTraitBold))
        targetWeight = weightClassWeights[boldWeightClassIndex];
    else if ((original & kCTFontTraitBold) && !(wanted & kCTFontTraitBold))
        targetWeight = 0;
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

static bool isKana(uint32_t c) {
    return (c >= 0x3040 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF) ||
           (c >= 0xFF66 && c <= 0xFF9F) || (c >= 0x1B000 && c <= 0x1B16F);
}

static bool isHangul(uint32_t c) {
    return (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F) ||
           (c >= 0xA960 && c <= 0xA97F) || (c >= 0xAC00 && c <= 0xD7FF) ||
           (c >= 0xFFA0 && c <= 0xFFDC);
}

static bool isHan(uint32_t c) {
    return (c >= 0x2E80 && c <= 0x2FDF) || (c >= 0x3005 && c <= 0x3007) ||
           (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) ||
           (c >= 0xF900 && c <= 0xFAFF) || (c >= 0x20000 && c <= 0x3134F);
}

static bool isCJKLanguage(const char *language) {
    if (language == NULL)
        return false;
    for (size_t i = 0; i < 3; i++) {
        static const char *prefixes[] = { "zh", "ja", "ko" };
        size_t length = strlen(prefixes[i]);
        if (strncasecmp(language, prefixes[i], length) == 0 &&
            (language[length] == '\0' || language[length] == '-' || language[length] == '_'))
            return true;
    }
    return false;
}

// The language whose faces a substitute for the text is chosen from.
// QUIRK: text with kana is set as Japanese and text with Hangul as Korean, whatever the
// language; Han text is set in the given language if it is Chinese, Japanese or Korean, and as
// Simplified Chinese otherwise (and without one). Not documented. Evidence: black-box
// observation of CTFontCreateForStringWithLanguage on macOS 26.7.3 (tier 2): Han text gets
// PingFang SC with no language and with "en" or "fr", PingFang TC with "zh-Hant", Hiragino Sans
// with "ja" and Apple SD Gothic Neo with "ko"; kana gets Hiragino Sans with "zh-Hans"; Hangul
// gets Apple SD Gothic Neo with "ja". Test: tests/coretext-cjk-fallback-language.c.
static const char *substituteLanguage(const uint32_t *codePoints, size_t count, const char *language) {
    bool han = false;
    for (size_t i = 0; i < count; i++) {
        if (isKana(codePoints[i]))
            return "ja";
        if (isHangul(codePoints[i]))
            return "ko";
        han = han || isHan(codePoints[i]);
    }
    if (han && !isCJKLanguage(language))
        return "zh-Hans";
    return language;
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
                                                              substituteLanguage(codePoints, count, languageName));
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
    id uiFontType = objc_getAssociatedObject(object, &uiFontTypeKey);
    if (uiFontType != nil)
        [attributes setObject: uiFontType forKey: (NSString *) KTFontUIFontTypeAttribute];
    NSNumber *weight = [traits objectForKey: (NSString *) kCTFontWeightTrait];
    NSNumber *width = [traits objectForKey: (NSString *) kCTFontWidthTrait];
    if (weight != nil)
        [attributes setObject: [NSNumber numberWithDouble: KTFontCSSWeightForWeightTrait([weight doubleValue])]
                       forKey: (NSString *) kCTFontCSSWeightAttribute];
    if (width != nil)
        [attributes setObject: [NSNumber numberWithDouble: KTFontCSSWidthForWidthTrait([width doubleValue])]
                       forKey: (NSString *) kCTFontCSSWidthAttribute];
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

// The NSFontWeight values of the nine OS/2 weight classes.
static const CGFloat weights[] = { -0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4,
                                   0.56, 0.62 };

CGFloat KTFontCSSWeightForWeightTrait(CGFloat weight)
{
    // The inverse of the mapping fontTraits() makes from usWeightClass.
    if (!(weight > weights[0]))
        return 100;
    for (unsigned i = 0; i < 8; i++) {
        if (weight <= weights[i + 1])
            return 100 * (i + 1) + 100 * (weight - weights[i]) / (weights[i + 1] - weights[i]);
    }
    return 900;
}

CGFloat KTFontCSSWidthForWidthTrait(CGFloat width)
{
    // The widths of the nine OpenType usWidthClass classes, in percent of the
    // normal width (OpenType specification, OS/2 table); fontTraits() maps
    // the class to (class - 5) / 4.
    static const CGFloat percentages[] = { 50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200 };
    CGFloat position = width * 4 + 4;
    if (!(position > 0))
        return percentages[0];
    if (position >= 8)
        return percentages[8];
    unsigned index = (unsigned) position;
    return percentages[index] + (percentages[index + 1] - percentages[index]) * (position - index);
}

// Traits from the OS/2 table (weight and width class, fsSelection) and the
// post table (italic angle, fixed pitch) of the face, as in the OpenType
// specification.
static CTFontSymbolicTraits fontTraits(CTFontRef font, CGFloat *weight,
                                       CGFloat *width, CGFloat *slant)
{
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
    *weight = weightClassWeights[index];
    if (index < 8)
        *weight += (weightClassWeights[index + 1] - weightClassWeights[index]) * (weightClass % 100) / 100.0;
    // QUIRK: a face of weight class 600 (Semibold, Demibold: weight trait 0.3) and above has the
    // bold trait, not only from class 700. The documentation says only that the trait has more
    // detail in kCTFontWeightTrait. Evidence: black-box observation of the symbolic and weight traits
    // on macOS 26.1 (arm64), 98 faces printed by probe 639: every face reporting weight 0.3,
    // 0.4, 0.56 or 0.62 has the bold bit (AvenirNext-DemiBold and GillSans-SemiBold, both 0.3, report
    // 80000002) and every face at 0.23 or less lacks it. Which fonts those are is machine specific.
    // Evidence for the boundary: the OS/2 usWeightClass and the bold bit of every installed font of macOS
    // 26.7.3 (529 faces) and 10.14.4 (488 faces), mac-probes p796: every face of class 600 and above has the
    // bold bit (26 and 24 faces of class 600), the faces of class 500 do not except 5 (1 on Mojave) whose
    // own bold flag is set. A face's own bold flag in the OS/2 table still counts.
    // Test: coretext-font-copy-with-traits-and-family.
    if (weightClass >= 600)
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

bool CTFontIsSystemUIFont(CTFontRef font)
{
    KTFont *object = ktFont(font);
    return object != nil && objc_getAssociatedObject(object, &systemUIFontKey) != nil;
}

CTFontUIFontType CTFontGetUIFontType(CTFontRef font)
{
    KTFont *object = ktFont(font);
    NSNumber *type = object != nil ? objc_getAssociatedObject(object, &uiFontTypeKey) : nil;
    return type != nil ? (CTFontUIFontType) [type unsignedIntValue] : kCTFontUIFontNone;
}

bool CTFontIsAppleColorEmoji(CTFontRef font)
{
    CFStringRef name = CTFontCopyPostScriptName(font);
    if (name == NULL)
        return false;
    bool result = CFEqual(name, CFSTR("AppleColorEmoji"));
    CFRelease(name);
    return result;
}

CTFontSymbolicTraits CTFontGetPhysicalSymbolicTraits(CTFontRef font)
{
    // A Darling font is always one face (there are no cascade-only "logical"
    // fonts), so its traits are those of the face.
    return CTFontGetSymbolicTraits(font);
}

CTFontRef CTFontCreateForCharactersWithLanguageAndOption(CTFontRef currentFont,
                                                         const UTF16Char *characters,
                                                         CFIndex length, CFStringRef language,
                                                         CTFontFallbackOption option,
                                                         CFIndex *coveredLength)
{
    if (coveredLength != NULL)
        *coveredLength = 0;
    if (ktFont(currentFont) == nil || characters == NULL || length <= 0)
        return NULL;
    CFStringRef string = CFStringCreateWithCharactersNoCopy(kCFAllocatorDefault, characters, length,
                                                            kCFAllocatorNull);
    if (string == NULL)
        return NULL;

    // The font is the one CTFontCreateForStringWithLanguage() finds for the
    // first composed character sequence; it covers as many of the following
    // sequences as it has glyphs for. Darling cannot tell user-installed fonts
    // from system fonts, so the fallback option does not narrow the search.
    CFRange cluster = CFStringGetRangeOfComposedCharactersAtIndex(string, 0);
    CTFontRef result = CTFontCreateForStringWithLanguage(currentFont, string, cluster, language);
    if (result == NULL) {
        // No installed face has the characters: the current font draws them
        // (with its missing-glyph glyph) and covers nothing.
        CFRelease(string);
        return (CTFontRef) CFRetain(currentFont);
    }
    CFIndex covered = 0;
    while (covered < length) {
        cluster = CFStringGetRangeOfComposedCharactersAtIndex(string, covered);
        if (!fontCoversText(result, characters + cluster.location, cluster.length))
            break;
        covered = cluster.location + cluster.length;
    }
    CFRelease(string);
    if (coveredLength != NULL)
        *coveredLength = covered;
    return result;
}

bool CTFontGetGlyphsForCharacterRange(CTFontRef font, CGGlyph glyphs[], CFRange range)
{
    KTFont *object = ktFont(font);
    if (object == nil || glyphs == NULL || range.location < 0 || range.length < 0 ||
        range.location > 0x10000 || range.length > 0x10000 - range.location)
        return false;
    bool all = true;
    for (CFIndex i = 0; i < range.length; i++) {
        UniChar character = (UniChar) (range.location + i);
        // A surrogate code unit on its own is no character.
        if (character >= 0xD800 && character <= 0xDFFF)
            glyphs[i] = 0;
        else
            [object getGlyphs: &glyphs[i] forCharacters: &character length: 1];
        if (glyphs[i] == 0)
            all = false;
    }
    return all;
}

bool CTFontGetVerticalGlyphsForCharacters(CTFontRef font, const UniChar characters[],
                                          CGGlyph glyphs[], CFIndex count)
{
    // Darling applies no vertical substitutions (the OpenType 'vert' and
    // 'vrt2' features), so vertical text uses the nominal glyphs.
    return CTFontGetGlyphsForCharacters(font, characters, glyphs, count);
}

CFBitVectorRef CTFontCopyColorGlyphCoverage(CTFontRef font)
{
    // Darling draws no colour glyphs (sbix, COLR, SVG or bitmap colour
    // tables) and never reports kCTFontTraitColorGlyphs, so no glyph has a
    // colour form.
    return NULL;
}

CFBitVectorRef CTFontCopyGlyphCoverageForFeature(CTFontRef font, CFDictionaryRef feature)
{
    if (ktFont(font) == nil || feature == NULL)
        return NULL;
    // Darling's layout applies no feature substitutions (GSUB, morx), so a
    // feature changes no glyph: the coverage is empty. It is a bit vector
    // over all glyphs of the font, as callers read it without a NULL check.
    CFIndex count = CTFontGetGlyphCount(font);
    CFMutableBitVectorRef coverage = CFBitVectorCreateMutable(kCFAllocatorDefault, count);
    if (coverage == NULL)
        return NULL;
    CFBitVectorSetCount(coverage, count);
    CFBitVectorRef result = CFBitVectorCreateCopy(kCFAllocatorDefault, coverage);
    CFRelease(coverage);
    return result;
}

CGFloat CTFontGetSbixImageSizeForGlyphAndContentsScale(CTFontRef font, const CGGlyph glyph,
                                                       CGFloat contentsScale)
{
    // Darling does not draw sbix images, so for its layout no glyph has one.
    return 0;
}

CGFloat CTFontGetAccessibilityBoldWeightOfWeight(CGFloat weight)
{
    // The weight each named weight becomes, read from this function on macOS
    // 26.7.3 (black-box observation): one step up to Regular, two steps up
    // from Regular to Bold, and Heavy and Black become Black.
    // Test: tests/coretext-spi-fonts.c
    // A weight between two named ones maps as the named weight below it
    // (inferred; only the named weights were observed), and weights outside
    // the named range are kept.
    static const struct { const CGFloat *from, *to; } map[] = {
        { &kCTFontWeightUltraLight, &kCTFontWeightThin },
        { &kCTFontWeightThin, &kCTFontWeightLight },
        { &kCTFontWeightLight, &kCTFontWeightRegular },
        { &kCTFontWeightRegular, &kCTFontWeightSemibold },
        { &kCTFontWeightMedium, &kCTFontWeightBold },
        { &kCTFontWeightSemibold, &kCTFontWeightHeavy },
        { &kCTFontWeightBold, &kCTFontWeightBlack },
        { &kCTFontWeightHeavy, &kCTFontWeightBlack },
        { &kCTFontWeightBlack, &kCTFontWeightBlack },
    };
    const size_t count = sizeof(map) / sizeof(map[0]);
    if (weight != weight || weight < *map[0].from || weight > *map[count - 1].from)
        return weight;
    for (size_t i = count; i-- > 0;) {
        if (weight >= *map[i].from)
            return *map[i].to;
    }
    return weight;
}

CGSize CTFontShapeGlyphs(CTFontRef font, CGGlyph glyphs[], CGSize advances[],
                         CGPoint origins[], CFIndex indexes[], const UniChar chars[],
                         CFIndex count, CTFontShapeOptions options, CFStringRef language,
                         void (^handler)(CFRange, CGGlyph **, CGSize **, CGPoint **, CFIndex **))
{
    if (ktFont(font) == nil || count <= 0 || glyphs == NULL || advances == NULL ||
        origins == NULL || indexes == NULL)
        return CGSizeZero;

    // Darling's shaping is the one its line layout does: glyphs stay one per
    // input glyph (no substitution, so the number of glyphs never changes and
    // the handler is not called), each takes its advance from the font, and
    // kerning adds the font's pair kerning. No glyph is offset from its pen
    // position, so the origins and the initial advance are zero.
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, glyphs, advances, count);
    for (CFIndex i = 0; i < count; i++)
        origins[i] = CGPointZero;

    bool rightToLeft = (options & kCTFontShapeRightToLeft) != 0;
    if (rightToLeft) {
        // Inferred from how callers use the result: right-to-left text comes
        // back in visual order, the reverse of the logical order it came in.
        for (CFIndex i = 0, j = count - 1; i < j; i++, j--) {
            CGGlyph glyph = glyphs[i]; glyphs[i] = glyphs[j]; glyphs[j] = glyph;
            CGSize advance = advances[i]; advances[i] = advances[j]; advances[j] = advance;
            CFIndex index = indexes[i]; indexes[i] = indexes[j]; indexes[j] = index;
        }
    }
    if (options & kCTFontShapeWithKerning) {
        for (CFIndex i = 0; i + 1 < count; i++)
            advances[i].width += KTFontGetPairKerning(font, glyphs[i], glyphs[i + 1]);
    }
    return CGSizeZero;
}
