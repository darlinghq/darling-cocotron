#import <CoreText/CTFontDescriptor.h>
#import <CoreText/CTFont.h>
#import "KTFontDescriptor.h"
#import "CTFontSPI.h"
#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font_freetype.h>

const CFStringRef kCTFontURLAttribute = CFSTR("NSCTFontFileURLAttribute");
const CFStringRef kCTFontNameAttribute = CFSTR("NSFontNameAttribute");
const CFStringRef kCTFontDisplayNameAttribute = CFSTR("NSFontVisibleNameAttribute");
const CFStringRef kCTFontFamilyNameAttribute = CFSTR("NSFontFamilyAttribute");
const CFStringRef kCTFontStyleNameAttribute = CFSTR("NSFontFaceAttribute");
const CFStringRef kCTFontTraitsAttribute = CFSTR("NSCTFontTraitsAttribute");
const CFStringRef kCTFontVariationAttribute = CFSTR("NSCTFontVariationAttribute");
const CFStringRef kCTFontVariationAxesAttribute = CFSTR("NSCTFontVariationAxesAttribute");
const CFStringRef kCTFontSizeAttribute = CFSTR("NSFontSizeAttribute");
const CFStringRef kCTFontMatrixAttribute = CFSTR("NSCTFontMatrixAttribute");
const CFStringRef kCTFontCascadeListAttribute = CFSTR("NSCTFontCascadeListAttribute");
const CFStringRef kCTFontCharacterSetAttribute = CFSTR("NSCTFontCharacterSetAttribute");
const CFStringRef kCTFontLanguagesAttribute = CFSTR("NSCTFontLanguagesAttribute");
const CFStringRef kCTFontBaselineAdjustAttribute = CFSTR("NSCTFontBaselineAdjustAttribute");
const CFStringRef kCTFontMacintoshEncodingsAttribute = CFSTR("NSCTFontMacintoshEncodingsAttribute");
const CFStringRef kCTFontFeaturesAttribute = CFSTR("NSCTFontFeaturesAttribute");
const CFStringRef kCTFontFeatureSettingsAttribute = CFSTR("NSCTFontFeatureSettingsAttribute");
const CFStringRef kCTFontFixedAdvanceAttribute = CFSTR("NSCTFontFixedAdvanceAttribute");
const CFStringRef kCTFontOrientationAttribute = CFSTR("NSCTFontOrientationAttribute");
const CFStringRef kCTFontEnabledAttribute = CFSTR("NSCTFontEnabledAttribute");
const CFStringRef kCTFontFormatAttribute = CFSTR("NSCTFontFormatAttribute");
const CFStringRef kCTFontRegistrationScopeAttribute = CFSTR("NSCTFontRegistrationScopeAttribute");
const CFStringRef kCTFontPriorityAttribute = CFSTR("NSCTFontPriorityAttribute");
const CFStringRef kCTFontDownloadableAttribute = CFSTR("NSCTFontDownloadableAttribute");
const CFStringRef kCTFontDownloadedAttribute = CFSTR("NSCTFontDownloadedAttribute");
const CFStringRef kCTFontDescriptorLanguageAttribute = CFSTR("CTFontDescriptorLanguageAttribute");
__attribute__((visibility("hidden")))
const CFStringRef KTFontSystemUIAttribute = CFSTR("KTFontSystemUIAttribute");
__attribute__((visibility("hidden")))
const CFStringRef KTFontUIFontTypeAttribute = CFSTR("KTFontUIFontTypeAttribute");

@implementation KTFontDescriptor

- initWithAttributes: (NSDictionary *) attributes fontData: (NSData *) data {
    return [self initWithAttributes: attributes fontData: data faceIndex: 0];
}

- initWithAttributes: (NSDictionary *) attributes
            fontData: (NSData *) data
           faceIndex: (int) faceIndex {
    return [self initWithAttributes: attributes fontData: data faceIndex: faceIndex options: 0];
}

- initWithAttributes: (NSDictionary *) attributes
            fontData: (NSData *) data
           faceIndex: (int) faceIndex
             options: (uint32_t) options {
    self = [super init];
    if (self == nil)
        return nil;
    _attributes = attributes ? [attributes copy] : [[NSDictionary alloc] init];
    _fontData = [data copy];
    _faceIndex = faceIndex;
    _options = options;
    return self;
}

- (void) dealloc {
    [_attributes release];
    [_fontData release];
    [super dealloc];
}

- (CFTypeID) _cfTypeID {
    return CTFontDescriptorGetTypeID();
}

- copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (NSDictionary *) attributes {
    return _attributes;
}

- (NSData *) fontData {
    return _fontData;
}

- (int) faceIndex {
    return _faceIndex;
}

- (uint32_t) options {
    return _options;
}

- (BOOL) isEqual: (id) other {
    if (other == self)
        return YES;
    if (![other isKindOfClass: [KTFontDescriptor class]])
        return NO;
    KTFontDescriptor *descriptor = other;
    if (![_attributes isEqual: descriptor->_attributes] ||
        _faceIndex != descriptor->_faceIndex || _options != descriptor->_options)
        return NO;
    if (_fontData == nil || descriptor->_fontData == nil)
        return _fontData == descriptor->_fontData;
    return [_fontData isEqual: descriptor->_fontData];
}

- (NSUInteger) hash {
    return [_attributes hash];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ %p> %@", [self class], self,
                                       _attributes];
}

@end

static NSString *stringAttribute(NSDictionary *attributes, CFStringRef key);

// NSFontDescriptor and CTFontDescriptorRef are toll-free bridged, so the
// functions may be given an NSFontDescriptor: AppKit gives the CoreText
// descriptor with its attributes (as an NSFont gives its CTFont, see ktFont()).
static KTFontDescriptor *descriptorObject(CTFontDescriptorRef descriptor) {
    id object = (id) descriptor;
    if (object != nil && ![object isKindOfClass: [KTFontDescriptor class]] &&
        [object respondsToSelector: @selector(_coreTextFontDescriptor)])
        return (KTFontDescriptor *) [object performSelector: @selector(_coreTextFontDescriptor)];
    return (KTFontDescriptor *) object;
}

CTFontDescriptorRef KTFontDescriptorCreateWithFontData(CFDictionaryRef attributes,
                                                       CFDataRef data)
{
    return (CTFontDescriptorRef) [[KTFontDescriptor alloc]
            initWithAttributes: (NSDictionary *) attributes
                      fontData: (NSData *) data];
}

CTFontDescriptorRef KTFontDescriptorCreateWithFontDataAndFaceIndex(CFDictionaryRef attributes,
                                                                   CFDataRef data,
                                                                   int faceIndex)
{
    return (CTFontDescriptorRef) [[KTFontDescriptor alloc]
            initWithAttributes: (NSDictionary *) attributes
                      fontData: (NSData *) data
                     faceIndex: faceIndex];
}

int KTFontDescriptorGetFaceIndex(CTFontDescriptorRef descriptor) {
    if (descriptor == NULL)
        return 0;
    return [descriptorObject(descriptor) faceIndex];
}

CFDataRef KTFontDescriptorGetFontData(CTFontDescriptorRef descriptor) {
    if (descriptor == NULL)
        return NULL;
    return (CFDataRef) [descriptorObject(descriptor) fontData];
}

CFTypeID CTFontDescriptorGetTypeID(void) {
    return (CFTypeID) [KTFontDescriptor self];
}

CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(CFDictionaryRef attributes) {
    if (attributes == NULL)
        return NULL;
    return KTFontDescriptorCreateWithFontData(attributes, NULL);
}

CTFontDescriptorRef CTFontDescriptorCreateWithNameAndSize(CFStringRef name, CGFloat size) {
    if (name == NULL)
        return NULL;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    [attributes setObject: (NSString *) name forKey: (NSString *) kCTFontNameAttribute];
    if (size != 0)
        [attributes setObject: [NSNumber numberWithDouble: size]
                       forKey: (NSString *) kCTFontSizeAttribute];
    return CTFontDescriptorCreateWithAttributes((CFDictionaryRef) attributes);
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithAttributes(CTFontDescriptorRef original,
                                                            CFDictionaryRef attributes)
{
    if (original == NULL)
        return NULL;
    KTFontDescriptor *descriptor = descriptorObject(original);
    NSMutableDictionary *merged = [[descriptor attributes] mutableCopy];
    if (attributes != NULL)
        [merged addEntriesFromDictionary: (NSDictionary *) attributes];
    CTFontDescriptorRef result = (CTFontDescriptorRef) [[KTFontDescriptor alloc]
            initWithAttributes: merged
                      fontData: [descriptor fontData]
                     faceIndex: [descriptor faceIndex]
                       options: [descriptor options]];
    [merged release];
    return result;
}

CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor) {
    if (descriptor == NULL)
        return NULL;
    return (CFDictionaryRef) [[descriptorObject(descriptor) attributes] copy];
}

// A descriptor is often made with the PostScript name alone, or from a font
// object, and its other naming attributes are those of the installed face of
// that name. The attribute is read from that face when the descriptor does not
// carry it. A descriptor that holds font data is not looked up: the face it
// describes is not necessarily an installed one.
static id installedFaceAttribute(KTFontDescriptor *descriptor, CFStringRef attribute)
{
    const char *faceKey = NULL;
    if (CFEqual(attribute, kCTFontFamilyNameAttribute))
        faceKey = "family";
    else if (CFEqual(attribute, kCTFontDisplayNameAttribute))
        faceKey = "fullName";
    else if (CFEqual(attribute, kCTFontStyleNameAttribute))
        faceKey = "style";
    else if (CFEqual(attribute, kCTFontURLAttribute))
        faceKey = "path";
    if (faceKey == NULL || [descriptor fontData] != nil)
        return nil;

    NSString *name = stringAttribute([descriptor attributes], kCTFontNameAttribute);
    if (name == nil)
        name = stringAttribute([descriptor attributes], kCTFontPostScriptNameAttribute);
    if (name == nil)
        return nil;
    NSArray *faces = O2FontCopyInstalledFaces(nil, name, nil, nil);
    id value = nil;
    if ([faces count] > 0)
        value = [[faces objectAtIndex: 0] objectForKey: [NSString stringWithUTF8String: faceKey]];
    [faces release];
    if (value != nil && strcmp(faceKey, "path") == 0)
        value = [NSURL fileURLWithPath: value];
    return value;
}

// Attributes that name the same property as another attribute: kCTFontNameAttribute is
// documented as the PostScript name, which is what kCTFontPostScriptNameAttribute names too, and
// the reference URL of a face is taken to be the URL of its font file (inferred: no public
// source describes kCTFontReferenceURLAttribute). A descriptor may carry either key.
static CFStringRef aliasOfAttribute(CFStringRef attribute)
{
    if (CFEqual(attribute, kCTFontNameAttribute))
        return kCTFontPostScriptNameAttribute;
    if (CFEqual(attribute, kCTFontPostScriptNameAttribute))
        return kCTFontNameAttribute;
    if (CFEqual(attribute, kCTFontReferenceURLAttribute))
        return kCTFontURLAttribute;
    return NULL;
}

// The value of an attribute in an attribute dictionary, or of its alias.
static id attributeOrAlias(NSDictionary *attributes, CFStringRef attribute)
{
    id value = [attributes objectForKey: (NSString *) attribute];
    CFStringRef alias = aliasOfAttribute(attribute);
    if (value == nil && alias != NULL)
        value = [attributes objectForKey: (NSString *) alias];
    return value;
}

CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute)
{
    if (descriptor == NULL || attribute == NULL)
        return NULL;
    KTFontDescriptor *object = descriptorObject(descriptor);
    id value = attributeOrAlias([object attributes], attribute);
    if (value == nil)
        value = installedFaceAttribute(object, attribute);
    CFStringRef alias = aliasOfAttribute(attribute);
    if (value == nil && alias != NULL)
        value = installedFaceAttribute(object, alias);
    // Darling's fonts are files it has: none can be or was downloaded on demand.
    // QUIRK: the value is the CFNumber 0 (kCFNumberSInt32Type), not
    // kCFBooleanFalse as the attributes' documentation suggests, so a comparison
    // with kCFBooleanFalse is false. Evidence: black-box observation on macOS
    // 26.7.3 (tier 2) of both attributes of an installed font.
    // Test: tests/coretext-manager-register-font-urls.m (the quirk checks).
    if (value == nil && (CFEqual(attribute, kCTFontDownloadableAttribute) || CFEqual(attribute, kCTFontDownloadedAttribute)))
        value = [NSNumber numberWithInt: 0];
    return (CFTypeRef) [value retain];
}

bool CTFontDescriptorIsSystemUIFont(CTFontDescriptorRef descriptor)
{
    if (descriptor == NULL)
        return false;
    // The option is taken to mark the descriptor as one of a system UI font,
    // as its name says (inferred). CTFontDescriptorGetOptions() reports it for
    // the descriptors of system UI fonts, so the two round-trip.
    if ([descriptorObject(descriptor) options] & kCTFontDescriptorOptionSystemUIFont)
        return true;
    id value = [[descriptorObject(descriptor) attributes] objectForKey: (NSString *) KTFontSystemUIAttribute];
    return [value isKindOfClass: [NSNumber class]] && [value boolValue];
}

CFTypeRef CTFontDescriptorCopyLocalizedAttribute(CTFontDescriptorRef descriptor,
                                                CFStringRef attribute,
                                                CFStringRef *language)
{
    // Only the canonical names are known, and their language is not.
    if (language != NULL)
        *language = NULL;
    return CTFontDescriptorCopyAttribute(descriptor, attribute);
}

static NSString *stringAttribute(NSDictionary *attributes, CFStringRef key) {
    id value = [attributes objectForKey: (NSString *) key];
    return [value isKindOfClass: [NSString class]] ? value : nil;
}

CFArrayRef CTFontDescriptorCreateMatchingFontDescriptors(CTFontDescriptorRef descriptor,
                                                        CFSetRef mandatoryAttributes)
{
    if (descriptor == NULL)
        return NULL;
    NSDictionary *query = [descriptorObject(descriptor) attributes];

    // Match installed faces on the name attributes of the query. Faces are
    // listed, not substituted: a family that is not installed matches
    // nothing, except for the families every macOS provides (Times,
    // Helvetica, ...). Those are answered by the installed family that stands
    // in for them, which is also the family its faces and fonts report.
    NSString *family = stringAttribute(query, kCTFontFamilyNameAttribute);
    NSString *postScriptName = stringAttribute(query, kCTFontNameAttribute);
    if (postScriptName == nil)
        postScriptName = stringAttribute(query, kCTFontPostScriptNameAttribute);
    NSArray *faces = O2FontCopyInstalledFaces(
            family,
            postScriptName,
            stringAttribute(query, kCTFontStyleNameAttribute),
            stringAttribute(query, kCTFontDisplayNameAttribute));
    if (family != nil && [faces count] == 0) {
        NSString *installedFamily = O2FontCopyInstalledFamilyForStandardFamily(family);
        if (installedFamily != nil) {
            [faces release];
            faces = O2FontCopyInstalledFaces(
                    installedFamily,
                    postScriptName,
                    stringAttribute(query, kCTFontStyleNameAttribute),
                    stringAttribute(query, kCTFontDisplayNameAttribute));
            [installedFamily release];
        }
    }

    NSMutableArray *matches = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *face in faces) {
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        NSString *value;
        if ((value = [face objectForKey: @"family"]) != nil)
            [attributes setObject: value forKey: (NSString *) kCTFontFamilyNameAttribute];
        if ((value = [face objectForKey: @"postScriptName"]) != nil)
            [attributes setObject: value forKey: (NSString *) kCTFontNameAttribute];
        if ((value = [face objectForKey: @"style"]) != nil)
            [attributes setObject: value forKey: (NSString *) kCTFontStyleNameAttribute];
        if ((value = [face objectForKey: @"fullName"]) != nil)
            [attributes setObject: value forKey: (NSString *) kCTFontDisplayNameAttribute];
        NSNumber *symbolic = [face objectForKey: @"symbolicTraits"];
        NSNumber *weight = [face objectForKey: @"weight"];
        if (symbolic != nil && weight != nil) {
            // All four traits are reported, as CTFontCopyTraits does: callers read the width and
            // slant values without a check for their presence.
            NSMutableDictionary *traits = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    symbolic, (NSString *) kCTFontSymbolicTrait,
                    weight, (NSString *) kCTFontWeightTrait, nil];
            NSNumber *width = [face objectForKey: @"width"];
            NSNumber *slant = [face objectForKey: @"slant"];
            if (width != nil)
                [traits setObject: width forKey: (NSString *) kCTFontWidthTrait];
            if (slant != nil)
                [traits setObject: slant forKey: (NSString *) kCTFontSlantTrait];
            [attributes setObject: traits forKey: (NSString *) kCTFontTraitsAttribute];
            [attributes setObject: [NSNumber numberWithDouble: KTFontCSSWeightForWeightTrait([weight doubleValue])]
                           forKey: (NSString *) kCTFontCSSWeightAttribute];
            if (width != nil)
                [attributes setObject: [NSNumber numberWithDouble: KTFontCSSWidthForWidthTrait([width doubleValue])]
                               forKey: (NSString *) kCTFontCSSWidthAttribute];
        }
        if ((value = [face objectForKey: @"path"]) != nil)
            [attributes setObject: [NSURL fileURLWithPath: value]
                           forKey: (NSString *) kCTFontURLAttribute];

        // The point size is part of the request, not of the face.
        id size = [query objectForKey: (NSString *) kCTFontSizeAttribute];
        if (size != nil)
            [attributes setObject: size forKey: (NSString *) kCTFontSizeAttribute];

        BOOL accepted = YES;
        for (id key in (NSSet *) mandatoryAttributes) {
            id expected = attributeOrAlias(query, (CFStringRef) key);
            if (expected == nil || ![expected isEqual: attributeOrAlias(attributes, (CFStringRef) key)]) {
                accepted = NO;
                break;
            }
        }
        if (!accepted)
            continue;

        // Faces that differ only in properties not reported here produce
        // equal descriptors; keep one of them.
        if ([seen containsObject: attributes])
            continue;
        [seen addObject: attributes];

        CTFontDescriptorRef match =
                CTFontDescriptorCreateWithAttributes((CFDictionaryRef) attributes);
        [matches addObject: (id) match];
        CFRelease(match);
    }
    [faces release];

    // No match is reported as NULL, as CTFontCollection does.
    if ([matches count] == 0)
        return NULL;
    return (CFArrayRef) [matches copy];
}

CTFontDescriptorRef CTFontDescriptorCreateMatchingFontDescriptor(CTFontDescriptorRef descriptor,
                                                                CFSetRef mandatoryAttributes)
{
    CFArrayRef matches =
            CTFontDescriptorCreateMatchingFontDescriptors(descriptor, mandatoryAttributes);
    if (matches == NULL)
        return NULL;
    CTFontDescriptorRef result =
            (CTFontDescriptorRef) CFRetain(CFArrayGetValueAtIndex(matches, 0));
    CFRelease(matches);
    return result;
}

CTFontSymbolicTraits CTFontDescriptorGetSymbolicTraits(CTFontDescriptorRef descriptor)
{
    if (descriptor == NULL)
        return 0;
    NSDictionary *traits = [[descriptorObject(descriptor) attributes]
            objectForKey: (NSString *) kCTFontTraitsAttribute];
    NSNumber *symbolic = [traits objectForKey: (NSString *) kCTFontSymbolicTrait];
    return [symbolic isKindOfClass: [NSNumber class]]
            ? (CTFontSymbolicTraits) [symbolic unsignedIntValue]
            : 0;
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithSymbolicTraits(CTFontDescriptorRef descriptor,
                                                                 CTFontSymbolicTraits symTraitValue,
                                                                 CTFontSymbolicTraits symTraitMask)
{
    if (descriptor == NULL)
        return NULL;
    NSDictionary *oldTraits = [[descriptorObject(descriptor) attributes]
            objectForKey: (NSString *) kCTFontTraitsAttribute];
    NSMutableDictionary *traits = oldTraits != nil ? [oldTraits mutableCopy]
                                                   : [[NSMutableDictionary alloc] init];
    CTFontSymbolicTraits oldValue = CTFontDescriptorGetSymbolicTraits(descriptor);
    CTFontSymbolicTraits newValue = (oldValue & ~symTraitMask) | (symTraitValue & symTraitMask);
    [traits setObject: [NSNumber numberWithUnsignedInt: newValue]
               forKey: (NSString *) kCTFontSymbolicTrait];

    NSDictionary *changes = [NSDictionary dictionaryWithObject: traits
                                                        forKey: (NSString *) kCTFontTraitsAttribute];
    CTFontDescriptorRef result =
            CTFontDescriptorCreateCopyWithAttributes(descriptor, (CFDictionaryRef) changes);
    [traits release];
    return result;
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithFeature(CTFontDescriptorRef descriptor,
                                                          CFNumberRef featureTypeIdentifier,
                                                          CFNumberRef featureSelectorIdentifier)
{
    if (descriptor == NULL || featureTypeIdentifier == NULL || featureSelectorIdentifier == NULL)
        return NULL;
    NSArray *oldSettings = [[descriptorObject(descriptor) attributes]
            objectForKey: (NSString *) kCTFontFeatureSettingsAttribute];
    // A feature type has one selector: a new setting replaces the old one.
    NSMutableArray *settings = [[NSMutableArray alloc] init];
    for (NSDictionary *setting in oldSettings) {
        id type = [setting objectForKey: (NSString *) kCTFontFeatureTypeIdentifierKey];
        if (![type isEqual: (id) featureTypeIdentifier])
            [settings addObject: setting];
    }
    NSDictionary *newSetting = [NSDictionary dictionaryWithObjectsAndKeys:
            (id) featureTypeIdentifier, (NSString *) kCTFontFeatureTypeIdentifierKey,
            (id) featureSelectorIdentifier, (NSString *) kCTFontFeatureSelectorIdentifierKey,
            nil];
    [settings addObject: newSetting];

    NSDictionary *changes = [NSDictionary dictionaryWithObject: settings
                                                        forKey: (NSString *) kCTFontFeatureSettingsAttribute];
    CTFontDescriptorRef result =
            CTFontDescriptorCreateCopyWithAttributes(descriptor, (CFDictionaryRef) changes);
    [settings release];
    return result;
}

CTFontDescriptorRef CTFontDescriptorCreateCopyWithVariation(CTFontDescriptorRef original,
                                                            CFNumberRef variationIdentifier,
                                                            CGFloat variationValue)
{
    if (original == NULL || variationIdentifier == NULL)
        return NULL;
    NSDictionary *oldVariations = [[descriptorObject(original) attributes]
            objectForKey: (NSString *) kCTFontVariationAttribute];
    NSMutableDictionary *variations = oldVariations != nil ? [oldVariations mutableCopy]
                                                           : [[NSMutableDictionary alloc] init];
    [variations setObject: [NSNumber numberWithDouble: variationValue]
                   forKey: (id) variationIdentifier];

    NSDictionary *changes = [NSDictionary dictionaryWithObject: variations
                                                        forKey: (NSString *) kCTFontVariationAttribute];
    CTFontDescriptorRef result =
            CTFontDescriptorCreateCopyWithAttributes(original, (CFDictionaryRef) changes);
    [variations release];
    return result;
}

CTFontDescriptorRef CTFontDescriptorCreateWithAttributesAndOptions(CFDictionaryRef attributes,
                                                                   CTFontDescriptorOptions options)
{
    if (attributes == NULL)
        return NULL;
    return (CTFontDescriptorRef) [[KTFontDescriptor alloc] initWithAttributes: (NSDictionary *) attributes
                                                                     fontData: nil
                                                                    faceIndex: 0
                                                                      options: options];
}

CTFontDescriptorOptions CTFontDescriptorGetOptions(CTFontDescriptorRef descriptor)
{
    if (descriptor == NULL)
        return 0;
    CTFontDescriptorOptions options = [descriptorObject(descriptor) options];
    if (CTFontDescriptorIsSystemUIFont(descriptor))
        options |= kCTFontDescriptorOptionSystemUIFont;
    return options;
}

// A copy of a descriptor with one more attribute. Consumes the descriptor.
static CTFontDescriptorRef descriptorAddingAttribute(CTFontDescriptorRef descriptor,
                                                     CFStringRef attribute, CFTypeRef value)
{
    if (descriptor == NULL || value == NULL)
        return descriptor;
    NSDictionary *change = [NSDictionary dictionaryWithObject: (id) value forKey: (NSString *) attribute];
    CTFontDescriptorRef result = CTFontDescriptorCreateCopyWithAttributes(descriptor, (CFDictionaryRef) change);
    CFRelease(descriptor);
    return result;
}

CTFontDescriptorRef CTFontDescriptorCreateForUIType(CTFontUIFontType uiType, CGFloat size,
                                                    CFStringRef language)
{
    // The descriptor describes the font CTFontCreateUIFontForLanguage() makes,
    // so a font made from it is that font again (a system UI font of the type).
    CTFontRef font = CTFontCreateUIFontForLanguage(uiType, size, language);
    if (font == NULL)
        return NULL;
    CTFontDescriptorRef descriptor = CTFontCopyFontDescriptor(font);
    CFRelease(font);
    if (language != NULL && CFGetTypeID(language) == CFStringGetTypeID())
        descriptor = descriptorAddingAttribute(descriptor, kCTFontDescriptorLanguageAttribute, language);
    return descriptor;
}

// The metrics of the text styles: point size, weight and line height. Both
// tables were read from CTFontDescriptorGetTextStyleSize() on macOS 26.7.3
// (black-box observation): the first for kCTFontTextStylePlatformDefault and
// kCTFontTextStylePlatformMac, which give the same values for every size
// category; the second for the phone platform at the default category ("L").
// On that system the watch, TV and vision platforms give the phone values, and
// those platforms scale them by size category; Darling does not scale them.
// Test: tests/coretext-spi-descriptors.c
typedef struct {
    const CFStringRef *style;
    CGFloat macSize;
    const CGFloat *macWeight;
    CGFloat macLineHeight;
    CGFloat phoneSize;
    const CGFloat *phoneWeight;
    CGFloat phoneLineHeight;
} KTTextStyleMetrics;

static const KTTextStyleMetrics *textStyleMetrics(CFStringRef style)
{
    static const KTTextStyleMetrics table[] = {
        { &kCTUIFontTextStyleTitle0, 26, &kCTFontWeightRegular, 32, 34, &kCTFontWeightRegular, 41 },
        { &kCTUIFontTextStyleTitle1, 22, &kCTFontWeightRegular, 26, 28, &kCTFontWeightRegular, 34 },
        { &kCTUIFontTextStyleTitle2, 17, &kCTFontWeightRegular, 22, 22, &kCTFontWeightRegular, 28 },
        { &kCTUIFontTextStyleTitle3, 15, &kCTFontWeightRegular, 20, 20, &kCTFontWeightRegular, 25 },
        { &kCTUIFontTextStyleTitle4, 38, &kCTFontWeightHeavy, 48, 38, &kCTFontWeightHeavy, 48 },
        { &kCTUIFontTextStyleHeadline, 13, &kCTFontWeightBold, 16, 17, &kCTFontWeightSemibold, 22 },
        { &kCTUIFontTextStyleShortHeadline, 13, &kCTFontWeightBold, 14, 17, &kCTFontWeightSemibold, 20 },
        { &kCTUIFontTextStyleBody, 13, &kCTFontWeightRegular, 16, 17, &kCTFontWeightRegular, 22 },
        { &kCTUIFontTextStyleShortBody, 13, &kCTFontWeightRegular, 14, 17, &kCTFontWeightRegular, 20 },
        { &kCTUIFontTextStyleTallBody, 13, &kCTFontWeightRegular, 18, 17, &kCTFontWeightRegular, 24 },
        { &kCTUIFontTextStyleSubhead, 11, &kCTFontWeightRegular, 14, 15, &kCTFontWeightRegular, 20 },
        { &kCTUIFontTextStyleShortSubhead, 11, &kCTFontWeightRegular, 12, 15, &kCTFontWeightRegular, 18 },
        { &kCTUIFontTextStyleFootnote, 10, &kCTFontWeightRegular, 13, 13, &kCTFontWeightRegular, 18 },
        { &kCTUIFontTextStyleShortFootnote, 10, &kCTFontWeightRegular, 11, 13, &kCTFontWeightRegular, 16 },
        { &kCTUIFontTextStyleCaption1, 10, &kCTFontWeightRegular, 13, 12, &kCTFontWeightRegular, 16 },
        { &kCTUIFontTextStyleShortCaption1, 10, &kCTFontWeightRegular, 11, 12, &kCTFontWeightRegular, 14 },
        { &kCTUIFontTextStyleCaption2, 10, &kCTFontWeightMedium, 13, 11, &kCTFontWeightRegular, 13 },
    };
    if (style == NULL || CFGetTypeID(style) != CFStringGetTypeID())
        return NULL;
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        if (CFEqual(style, *table[i].style))
            return &table[i];
    }
    return NULL;
}

// Whether a platform gets the phone metrics (see above). The Touch Bar
// platform was observed to give neither table; giving it the macOS one is
// Darling's choice.
static bool usesPhoneMetrics(CTFontTextStylePlatform platform)
{
    switch (platform) {
    case kCTFontTextStylePlatformPhone:
    case kCTFontTextStylePlatformWatch:
    case kCTFontTextStylePlatformTV:
    case kCTFontTextStylePlatformVision:
    case kCTFontTextStylePlatformVisionLegacy:
        return true;
    default:
        return false;
    }
}

CGFloat CTFontDescriptorGetTextStyleSize(CFStringRef style, CFTypeRef sizeCategory,
                                         CTFontTextStylePlatform platform,
                                         CGFloat *weight, CGFloat *lineSpacing)
{
    const KTTextStyleMetrics *metrics = textStyleMetrics(style);
    if (metrics == NULL)
        return 0;
    bool phone = usesPhoneMetrics(platform);
    if (weight != NULL)
        *weight = phone ? *metrics->phoneWeight : *metrics->macWeight;
    if (lineSpacing != NULL)
        *lineSpacing = phone ? metrics->phoneLineHeight : metrics->macLineHeight;
    return phone ? metrics->phoneSize : metrics->macSize;
}

CTFontDescriptorRef CTFontDescriptorCreateWithTextStyle(CFStringRef style, CFStringRef sizeCategory,
                                                        CFStringRef language)
{
    const KTTextStyleMetrics *metrics = textStyleMetrics(style);
    if (metrics == NULL)
        return NULL;
    // Darling's system UI font has a regular and a bold face.
    CTFontUIFontType type = *metrics->macWeight >= kCTFontWeightBold ? kCTFontUIFontEmphasizedSystem
                                                                     : kCTFontUIFontSystem;
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateForUIType(type, metrics->macSize, language);
    return descriptorAddingAttribute(descriptor, kCTFontDescriptorTextStyleAttribute, style);
}

// The descriptor of the face fontconfig resolves a name to, by family and
// PostScript name. NULL when nothing is installed.
static CTFontDescriptorRef createDescriptorForResolvedName(CFStringRef name, CGFloat size)
{
    CTFontRef font = CTFontCreateWithName(name, size, NULL);
    if (font == NULL)
        return NULL;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSString *postScriptName = [(NSString *) CTFontCopyPostScriptName(font) autorelease];
    NSString *family = [(NSString *) CTFontCopyFamilyName(font) autorelease];
    CFRelease(font);
    if (postScriptName != nil)
        [attributes setObject: postScriptName forKey: (NSString *) kCTFontNameAttribute];
    if (family != nil)
        [attributes setObject: family forKey: (NSString *) kCTFontFamilyNameAttribute];
    if ([attributes count] == 0)
        return NULL;
    return CTFontDescriptorCreateWithAttributes((CFDictionaryRef) attributes);
}

CTFontDescriptorRef CTFontDescriptorCreateForCSSFamily(CFStringRef cssFamily, CFStringRef language)
{
    static const CFStringRef *families[] = {
        &kCTFontCSSFamilySerif, &kCTFontCSSFamilySansSerif, &kCTFontCSSFamilyCursive,
        &kCTFontCSSFamilyFantasy, &kCTFontCSSFamilyMonospace,
    };
    if (cssFamily == NULL || CFGetTypeID(cssFamily) != CFStringGetTypeID())
        return NULL;
    for (size_t i = 0; i < sizeof(families) / sizeof(families[0]); i++) {
        // The generic families are fontconfig's generic family names too, so
        // fontconfig's configuration picks the face. The language does not
        // take part: Darling's font lookup by name has no language.
        if (CFStringCompare(cssFamily, *families[i], kCFCompareCaseInsensitive) == kCFCompareEqualTo)
            return createDescriptorForResolvedName(*families[i], 0);
    }
    return NULL;
}

CTFontDescriptorRef CTFontDescriptorCreateLastResort(void)
{
    // Darling has no LastResort font. The face fontconfig falls back to for
    // sans-serif text is the last resort here: some face always answers it
    // where any font is installed.
    return createDescriptorForResolvedName(kCTFontCSSFamilySansSerif, 0);
}

CGFloat CTFontDescriptorGetWeight(CTFontDescriptorRef descriptor)
{
    if (descriptor == NULL)
        return 0.0;
    NSDictionary *attributes = [descriptorObject(descriptor) attributes];
    NSDictionary *traits = [attributes objectForKey: (NSString *) kCTFontTraitsAttribute];
    if ([traits isKindOfClass: [NSDictionary class]]) {
        NSNumber *weight = [traits objectForKey: (NSString *) kCTFontWeightTrait];
        if ([weight isKindOfClass: [NSNumber class]])
            return (CGFloat) [weight doubleValue];
    }
    if (CTFontDescriptorGetSymbolicTraits(descriptor) & kCTFontTraitBold)
        return kCTFontWeightBold;
    return kCTFontWeightRegular;
}
