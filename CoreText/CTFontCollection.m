#import <CoreText/CTFontCollection.h>

const CFStringRef kCTFontCollectionRemoveDuplicatesOption = CFSTR("CTFontCollectionRemoveDuplicatesOption");

CTFontCollectionRef CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef _Nullable CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef collection)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontCollectionRef CTFontCollectionCreateWithFontDescriptors(CFArrayRef _Nullable queryDescriptors,
                                                              CFDictionaryRef _Nullable options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}
