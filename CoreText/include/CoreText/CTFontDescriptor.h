#import <CoreFoundation/CFBase.h>
#import <CoreText/CoreTextExport.h>

// CORETEXT_EXPORT const CFStringRef kCTFontURLAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontNameAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontDisplayNameAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontFamilyNameAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontStyleNameAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontTraitsAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontVariationAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontSizeAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontMatrixAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontCascadeListAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontCharacterSetAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontLanguagesAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontBaselineAdjustAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontMacintoshEncodingsAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontFeaturesAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontFeatureSettingsAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontFixedAdvanceAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontOrientationAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontEnabledAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontFormatAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontRegistrationScopeAttribute;
// CORETEXT_EXPORT const CFStringRef kCTFontPriorityAttribute;

CF_IMPLICIT_BRIDGING_ENABLED

typedef struct __CTFontDescriptor *CTFontDescriptorRef;

CORETEXT_EXPORT CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute);

CF_IMPLICIT_BRIDGING_DISABLED
