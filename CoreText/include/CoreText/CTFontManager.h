#import <CoreText/CTFontDescriptor.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CTFontManagerErrors.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef CF_ENUM(uint32_t, CTFontManagerScope)
{
    kCTFontManagerScopeNone = 0,
    kCTFontManagerScopeProcess = 1,
    kCTFontManagerScopePersistent = 2,
    kCTFontManagerScopeSession = 3,
    kCTFontManagerScopeUser = 2,
};

CORETEXT_EXPORT const CFStringRef kCTFontManagerRegisteredFontsChangedNotification;

CORETEXT_EXPORT bool CTFontManagerRegisterGraphicsFont(CGFontRef font, CFErrorRef* error);
CORETEXT_EXPORT bool CTFontManagerUnregisterGraphicsFont(CGFontRef font, CFErrorRef *error);

CORETEXT_EXPORT CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void);

CORETEXT_EXPORT CTFontDescriptorRef CTFontManagerCreateFontDescriptorFromData(CFDataRef data);
CORETEXT_EXPORT CFArrayRef CTFontManagerCreateFontDescriptorsFromData(CFDataRef data);
CORETEXT_EXPORT CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fileURL);
CORETEXT_EXPORT bool CTFontManagerIsSupportedFont(CFURLRef fontURL);

CORETEXT_EXPORT bool CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef * error);
// Registers the fonts of the files, then calls the handler with the errors of
// the files that failed. It returns whether to go on; done is true on the last call.
CORETEXT_EXPORT void CTFontManagerRegisterFontURLs(CFArrayRef fontURLs, CTFontManagerScope scope, bool enabled,
                                                   bool (^registrationHandler)(CFArrayRef errors, bool done));

CF_IMPLICIT_BRIDGING_DISABLED
