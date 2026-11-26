#import <CoreText/CTFontManager.h>
#import "KTFontDescriptor.h"
#import "KTFontSuitcase.h"
#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font_freetype.h>
#include <errno.h>

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

// The handler is called once, before the function returns, with every error and done set, as on
// macOS 26.7.3 (tests/coretext-manager-register-font-urls.m). Without a URL to register, its one
// error is EINVAL, as there. The fonts are enabled whatever enabled says: the setting is for
// persistent registrations, and registrations last for the process here.
void CTFontManagerRegisterFontURLs(CFArrayRef fontURLs, CTFontManagerScope scope, bool enabled,
                                   bool (^registrationHandler)(CFArrayRef errors, bool done))
{
    NSMutableArray *errors = [NSMutableArray array];
    CFIndex count = fontURLs != NULL ? CFArrayGetCount(fontURLs) : 0;
    if (count == 0)
        [errors addObject: [NSError errorWithDomain: NSPOSIXErrorDomain code: EINVAL userInfo: nil]];
    for (CFIndex i = 0; i < count; i++) {
        CFErrorRef error = NULL;
        if (!CTFontManagerRegisterFontsForURL((CFURLRef) CFArrayGetValueAtIndex(fontURLs, i), scope, &error)
                && error != NULL) {
            [errors addObject: (id) error];
            CFRelease(error);
        }
    }
    if (registrationHandler != NULL)
        registrationHandler((CFArrayRef) errors, true);
}

// The descriptor of one face of font data: the naming attributes are those of the face, and the
// descriptor keeps the data and the face index, so CTFontCreateWithFontDescriptor makes its font
// from these bytes rather than looking the name up among the installed fonts.
static CTFontDescriptorRef createDescriptorForFace(CFDataRef data, int faceIndex,
                                                   NSString *postScriptName, NSURL *url)
{
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    if (provider == NULL)
        return NULL;
    CGFontRef font = (CGFontRef) O2FontCreateWithDataProviderAndFaceIndex(
            (O2DataProviderRef) provider, faceIndex);
    CGDataProviderRelease(provider);
    if (font == NULL)
        return NULL;

    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    NSString *name = (NSString *) CGFontCopyPostScriptName(font);
    NSString *family = (NSString *) O2FontCopyFamilyName((O2FontRef) font);
    NSString *fullName = (NSString *) O2FontCopyFullName((O2FontRef) font);
    NSString *style = (NSString *) O2FontCopyStyleName((O2FontRef) font);
    if (postScriptName != nil)
        [attributes setObject: postScriptName forKey: (NSString *) kCTFontNameAttribute];
    else if (name != nil)
        [attributes setObject: name forKey: (NSString *) kCTFontNameAttribute];
    if (family != nil)
        [attributes setObject: family forKey: (NSString *) kCTFontFamilyNameAttribute];
    if (fullName != nil)
        [attributes setObject: fullName forKey: (NSString *) kCTFontDisplayNameAttribute];
    if (style != nil)
        [attributes setObject: style forKey: (NSString *) kCTFontStyleNameAttribute];
    if (url != nil)
        [attributes setObject: url forKey: (NSString *) kCTFontURLAttribute];
    [name release];
    [family release];
    [fullName release];
    [style release];
    CGFontRelease(font);
    return KTFontDescriptorCreateWithFontDataAndFaceIndex((CFDictionaryRef) attributes, data,
                                                          faceIndex);
}

// One descriptor per face of the data: every face of a font collection, every 'sfnt' resource of a
// font suitcase (".dfont"), the one face of a plain font file. Returns an empty array for data
// that holds no font.
static CFArrayRef createDescriptorsFromData(CFDataRef data, NSURL *url)
{
    NSMutableArray *descriptors = [NSMutableArray array];
    NSArray *suitcase = KTFontSuitcaseCopyFaces((NSData *) data);
    long count = suitcase != nil ? (long) [suitcase count]
                                 : O2FontFaceCountOfData(CFDataGetBytePtr(data),
                                                         (size_t) CFDataGetLength(data));
    for (long position = 0; position < count; position++) {
        // A suitcase lists its faces in the order of its family records, which is not the order
        // of the font resources that the face index counts.
        NSDictionary *entry = suitcase != nil ? [suitcase objectAtIndex: (NSUInteger) position] : nil;
        int faceIndex = entry != nil ? [[entry objectForKey: @"faceIndex"] intValue] : (int) position;
        CTFontDescriptorRef descriptor = createDescriptorForFace(
                data, faceIndex, [entry objectForKey: @"postScriptName"], url);
        if (descriptor != NULL) {
            [descriptors addObject: (id) descriptor];
            CFRelease(descriptor);
        }
    }
    [suitcase release];
    return (CFArrayRef) [descriptors copy];
}

CTFontDescriptorRef CTFontManagerCreateFontDescriptorFromData(CFDataRef data)
{
    if (data == NULL)
        return NULL;
    CFArrayRef descriptors = createDescriptorsFromData(data, nil);
    CTFontDescriptorRef first = NULL;
    if (CFArrayGetCount(descriptors) > 0)
        first = (CTFontDescriptorRef) CFRetain(CFArrayGetValueAtIndex(descriptors, 0));
    CFRelease(descriptors);
    return first;
}

CFArrayRef CTFontManagerCreateFontDescriptorsFromData(CFDataRef data)
{
    if (data == NULL)
        return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    return createDescriptorsFromData(data, nil);
}

CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fileURL)
{
    if (fileURL == NULL)
        return NULL;
    NSData *data = [NSData dataWithContentsOfURL: (NSURL *) fileURL];
    if (data == nil)
        return NULL;
    // The descriptors report the file they came from.
    CFArrayRef descriptors = createDescriptorsFromData((CFDataRef) data, (NSURL *) fileURL);
    if (CFArrayGetCount(descriptors) == 0) {
        CFRelease(descriptors);
        return NULL;
    }
    return descriptors;
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
