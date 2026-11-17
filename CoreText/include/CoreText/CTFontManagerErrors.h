/* Copyright (C) 2026 Lubos Dolezel */
#import <CoreText/CoreTextExport.h>
#import <CoreFoundation/CoreFoundation.h>

CF_IMPLICIT_BRIDGING_ENABLED

CORETEXT_EXPORT const CFStringRef kCTFontManagerErrorDomain;
CORETEXT_EXPORT const CFStringRef kCTFontManagerErrorFontURLsKey;

typedef CF_ENUM(CFIndex, CTFontManagerError)
{
    kCTFontManagerErrorFileNotFound = 101,
    kCTFontManagerErrorInsufficientPermissions = 102,
    kCTFontManagerErrorUnrecognizedFormat = 103,
    kCTFontManagerErrorInvalidFontData = 104,
    kCTFontManagerErrorAlreadyRegistered = 105,
    kCTFontManagerErrorNotRegistered = 201,
    kCTFontManagerErrorInUse = 202,
    kCTFontManagerErrorSystemRequired = 203,
};

CF_IMPLICIT_BRIDGING_DISABLED
