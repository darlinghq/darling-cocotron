#import <CoreText/CTFontDescriptor.h>

#include <stdio.h>

const CFStringRef kCTFontURLAttribute = @"CTFontURLAttribute";
const CFStringRef kCTFontNameAttribute = @"NSFontNameAttribute";
const CFStringRef kCTFontDisplayNameAttribute = @"NSFontVisibleNameAttribute";
const CFStringRef kCTFontFamilyNameAttribute = @"NSFontFamilyAttribute";
const CFStringRef kCTFontStyleNameAttribute = @"NSFontFaceAttribute";
const CFStringRef kCTFontTraitsAttribute = @"NSCTFontTraitsAttribute";
const CFStringRef kCTFontVariationAttribute = @"NSFontVariationAttribute";
const CFStringRef kCTFontSizeAttribute = @"NSFontSizeAttribute";
const CFStringRef kCTFontMatrixAttribute = @"NSFontMatrixAttribute";
const CFStringRef kCTFontCascadeListAttribute = @"CTFontCascadeListAttribute";
const CFStringRef kCTFontCharacterSetAttribute = @"NSFontCharacterSetAttribute";
const CFStringRef kCTFontLanguagesAttribute = @"NSFontLanguagesAttribute";
const CFStringRef kCTFontBaselineAdjustAttribute = @"NSFontBaselineAdjustAttribute";
const CFStringRef kCTFontMacintoshEncodingsAttribute = @"NSFontMacintoshEncodingsAttribute";
const CFStringRef kCTFontFeaturesAttribute = @"CTFontFeaturesAttribute";
const CFStringRef kCTFontFeatureSettingsAttribute = @"CTFontFeatureSettingsAttribute";
const CFStringRef kCTFontFixedAdvanceAttribute = @"NSFontFixedAdvanceAttribute";
const CFStringRef kCTFontOrientationAttribute = @"NSFontOrientationAttribute";
const CFStringRef kCTFontEnabledAttribute = @"NSFontEnabledAttribute";
const CFStringRef kCTFontFormatAttribute = @"NSFontFormatAttribute";
const CFStringRef kCTFontRegistrationScopeAttribute = @"NSFontRegistrationScopeAttribute";
const CFStringRef kCTFontPriorityAttribute = @"NSFontPriorityAttribute";

CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}
