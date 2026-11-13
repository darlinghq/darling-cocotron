#import <CoreText/CTFontManager.h>
#import "KTFontDescriptor.h"
#import <Foundation/Foundation.h>
#import <Onyx2D/O2Font_freetype.h>

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

bool CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef * error)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
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
