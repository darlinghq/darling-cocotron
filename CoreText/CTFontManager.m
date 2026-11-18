#import <CoreText/CTFontManager.h>
#import "KTFontDescriptor.h"
#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font_freetype.h>

const CFStringRef kCTFontManagerErrorDomain = CFSTR("com.apple.CoreText.CTFontManagerErrorDomain");
const CFStringRef kCTFontManagerErrorFontURLsKey = CFSTR("CTFontManagerErrorFontURLs");
const CFStringRef kCTFontManagerRegisteredFontsChangedNotification = CFSTR("CTFontManagerFontChangedNotification");

bool CTFontManagerRegisterGraphicsFont(CGFontRef font, CFErrorRef* error)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

bool CTFontManagerUnregisterGraphicsFont(CGFontRef font, CFErrorRef *error)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void)
{
    NSArray *faces = O2FontCopyInstalledFaces(nil, nil, nil, nil);
    NSMutableSet *families = [NSMutableSet set];
    for (NSDictionary *face in faces) {
        NSString *family = [face objectForKey: @"family"];
        if (family != nil)
            [families addObject: family];
    }
    [faces release];
    NSArray *sorted = [[families allObjects]
            sortedArrayUsingSelector: @selector(localizedStandardCompare:)];
    return (CFArrayRef) [sorted copy];
}

// The registration lasts for the process whatever the scope asked for.
bool CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef * error)
{
    NSURL *url = (NSURL *) fontURL;
    O2FontRegistrationResult result = O2FontRegistrationNotFound;

    if (url != nil && [url isFileURL])
        result = O2FontRegisterFontFile([url path]);
    if (result == O2FontRegistrationSucceeded) {
        if (error != NULL)
            *error = NULL;
        return true;
    }
    if (error != NULL) {
        CFIndex code = kCTFontManagerErrorFileNotFound;
        if (result == O2FontRegistrationUnrecognized)
            code = kCTFontManagerErrorUnrecognizedFormat;
        else if (result == O2FontRegistrationAlreadyRegistered)
            code = kCTFontManagerErrorAlreadyRegistered;
        NSDictionary *userInfo = url == nil ? nil
            : [NSDictionary dictionaryWithObject: [NSArray arrayWithObject: url]
                                          forKey: (NSString *) kCTFontManagerErrorFontURLsKey];
        *error = CFErrorCreate(kCFAllocatorDefault, kCTFontManagerErrorDomain, code,
                               (CFDictionaryRef) userInfo);
    }
    return false;
}

CTFontDescriptorRef CTFontManagerCreateFontDescriptorFromData(CFDataRef data)
{
    if (data == NULL)
        return NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    if (provider == NULL)
        return NULL;
    CGFontRef font = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    if (font == NULL)
        return NULL;

    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSString *name = (NSString *) CGFontCopyPostScriptName(font);
    NSString *family = (NSString *) O2FontCopyFamilyName((O2FontRef) font);
    if (name != nil)
        [attributes setObject: name forKey: (NSString *) kCTFontNameAttribute];
    if (family != nil)
        [attributes setObject: family forKey: (NSString *) kCTFontFamilyNameAttribute];
    [name release];
    [family release];
    CGFontRelease(font);

    // The descriptor keeps the data, so CTFontCreateWithFontDescriptor
    // makes its font from these bytes rather than looking the name up
    // among the installed fonts.
    return KTFontDescriptorCreateWithFontData((CFDictionaryRef) attributes, data);
}

CFArrayRef CTFontManagerCreateFontDescriptorsFromData(CFDataRef data)
{
    CTFontDescriptorRef descriptor = CTFontManagerCreateFontDescriptorFromData(data);
    if (descriptor == NULL)
        return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    CFArrayRef result = CFArrayCreate(NULL, (const void **) &descriptor, 1,
                                      &kCFTypeArrayCallBacks);
    CFRelease(descriptor);
    return result;
}

CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fileURL)
{
    if (fileURL == NULL)
        return NULL;
    NSData *data = [NSData dataWithContentsOfURL: (NSURL *) fileURL];
    if (data == nil)
        return NULL;
    CTFontDescriptorRef descriptor = CTFontManagerCreateFontDescriptorFromData((CFDataRef) data);
    if (descriptor == NULL)
        return NULL;

    // Report the file the descriptor came from.
    NSDictionary *url = [NSDictionary dictionaryWithObject: (NSURL *) fileURL
                                                    forKey: (NSString *) kCTFontURLAttribute];
    CTFontDescriptorRef withURL =
            CTFontDescriptorCreateCopyWithAttributes(descriptor, (CFDictionaryRef) url);
    CFRelease(descriptor);
    CFArrayRef result = CFArrayCreate(NULL, (const void **) &withURL, 1, &kCFTypeArrayCallBacks);
    CFRelease(withURL);
    return result;
}

// CTFontManagerIsSupportedFont decides from the file name and the file's size, without looking at the font data: a
// regular file on the local file system whose name ends (in any letter case) in one of the extensions below, and which
// holds at least four bytes. A file URL for a missing file, a directory, an empty file or a name with another extension
// (including woff, woff2, fon, bdf, pcf) is not supported; neither is a URL that is not a file URL.
// QUIRK: the four-byte minimum is not documented. Evidence: black-box observation on macOS 26.7.3 (tier 2): .ttf files
// of 0 to 3 bytes are refused and of 4 to 16 bytes accepted.
// Test: tests/coretext-manager-supported-font.c (test_quirk_four_byte_minimum)
bool CTFontManagerIsSupportedFont(CFURLRef fontURL)
{
    if (fontURL == NULL || ![(NSURL *) fontURL isFileURL])
        return false;
    NSString *path = [(NSURL *) fontURL path];
    static NSSet *extensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = [[NSSet alloc] initWithObjects: @"ttf", @"otf", @"ttc", @"otc", @"dfont", @"pfb", @"pfa", @"suit", nil];
    });
    if (![extensions containsObject: [[path pathExtension] lowercaseString]])
        return false;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath: path error: NULL];
    if (![[attributes fileType] isEqualToString: NSFileTypeRegular])
        return false;
    return [attributes fileSize] >= 4;
}
