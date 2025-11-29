#import <CoreText/CTFontDescriptor.h>
#import <CoreGraphics/CoreGraphics.h>

CF_IMPLICIT_BRIDGING_ENABLED

typedef NS_ENUM(uint32_t, CTFontManagerScope)
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

CORETEXT_EXPORT bool CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef * error);

CF_IMPLICIT_BRIDGING_DISABLED
