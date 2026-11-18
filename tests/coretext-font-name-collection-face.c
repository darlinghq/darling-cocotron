/* Copyright (C) 2026 Lubos Dolezel */
/* A font created by the PostScript name of an installed face is that face, also when the face
 * is one of several in a font collection file (.ttc) and not the first. Every face the font
 * collection of the available fonts lists is created by its name and must report the name back.
 * Where the host has no collection file the check covers single-face fonts only. */
#include <CoreText/CoreText.h>
#include <stdio.h>

int main(void) {
    int failures = 0, checked = 0;
    CTFontCollectionRef all = CTFontCollectionCreateFromAvailableFonts(NULL);
    CFArrayRef descriptors = all != NULL ? CTFontCollectionCreateMatchingFontDescriptors(all) : NULL;
    if (descriptors == NULL || CFArrayGetCount(descriptors) == 0) {
        puts("SKIP: no installed fonts");
        return 0;
    }
    for (CFIndex i = 0; i < CFArrayGetCount(descriptors); i++) {
        CTFontDescriptorRef descriptor = (CTFontDescriptorRef) CFArrayGetValueAtIndex(descriptors, i);
        CFStringRef name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
        if (name == NULL)
            continue;
        CTFontRef font = CTFontCreateWithName(name, 14, NULL);
        CFStringRef reported = font != NULL ? CTFontCopyPostScriptName(font) : NULL;
        checked++;
        if (reported == NULL || !CFEqual(reported, name)) {
            char wanted[256] = "", got[256] = "";
            CFStringGetCString(name, wanted, sizeof(wanted), kCFStringEncodingUTF8);
            if (reported != NULL)
                CFStringGetCString(reported, got, sizeof(got), kCFStringEncodingUTF8);
            fprintf(stderr, "FAIL: font created for \"%s\" reports \"%s\"\n", wanted, got);
            failures++;
        }
        if (reported != NULL)
            CFRelease(reported);
        if (font != NULL)
            CFRelease(font);
        CFRelease(name);
    }
    printf("%d faces checked\n", checked);
    puts(failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
