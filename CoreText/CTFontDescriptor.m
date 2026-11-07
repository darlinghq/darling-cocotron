#import <CoreText/CTFontDescriptor.h>
#import "KTFontDescriptor.h"
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

@implementation KTFontDescriptor

- initWithAttributes: (NSDictionary *) attributes fontData: (NSData *) data {
    self = [super init];
    if (self == nil)
        return nil;
    _attributes = attributes ? [attributes copy] : [[NSDictionary alloc] init];
    _fontData = [data copy];
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

- (BOOL) isEqual: (id) other {
    if (other == self)
        return YES;
    if (![other isKindOfClass: [KTFontDescriptor class]])
        return NO;
    KTFontDescriptor *descriptor = other;
    if (![_attributes isEqual: descriptor->_attributes])
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

static KTFontDescriptor *descriptorObject(CTFontDescriptorRef descriptor) {
    return (KTFontDescriptor *) descriptor;
}

CTFontDescriptorRef KTFontDescriptorCreateWithFontData(CFDictionaryRef attributes,
                                                       CFDataRef data)
{
    return (CTFontDescriptorRef) [[KTFontDescriptor alloc]
            initWithAttributes: (NSDictionary *) attributes
                      fontData: (NSData *) data];
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
    CTFontDescriptorRef result = KTFontDescriptorCreateWithFontData(
            (CFDictionaryRef) merged, (CFDataRef) [descriptor fontData]);
    [merged release];
    return result;
}

CFDictionaryRef CTFontDescriptorCopyAttributes(CTFontDescriptorRef descriptor) {
    if (descriptor == NULL)
        return NULL;
    return (CFDictionaryRef) [[descriptorObject(descriptor) attributes] copy];
}

CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute)
{
    if (descriptor == NULL || attribute == NULL)
        return NULL;
    id value = [[descriptorObject(descriptor) attributes] objectForKey: (NSString *) attribute];
    return (CFTypeRef) [value retain];
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
    // nothing.
    NSArray *faces = O2FontCopyInstalledFaces(
            stringAttribute(query, kCTFontFamilyNameAttribute),
            stringAttribute(query, kCTFontNameAttribute),
            stringAttribute(query, kCTFontStyleNameAttribute),
            stringAttribute(query, kCTFontDisplayNameAttribute));

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
        if ((value = [face objectForKey: @"path"]) != nil)
            [attributes setObject: [NSURL fileURLWithPath: value]
                           forKey: (NSString *) kCTFontURLAttribute];

        // The point size is part of the request, not of the face.
        id size = [query objectForKey: (NSString *) kCTFontSizeAttribute];
        if (size != nil)
            [attributes setObject: size forKey: (NSString *) kCTFontSizeAttribute];

        BOOL accepted = YES;
        for (id key in (NSSet *) mandatoryAttributes) {
            id expected = [query objectForKey: key];
            if (expected == nil || ![expected isEqual: [attributes objectForKey: key]]) {
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
