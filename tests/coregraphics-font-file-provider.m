// Copyright (C) 2026 Lubos Dolezel
// CGFontCreateWithDataProvider with a provider made by CGDataProviderCreateWithFilename
// must give the same font as one made from the file's CFData.
//
// Run with the path of a TrueType or OpenType font file, for example
// /Library/Fonts/Arial.ttf on macOS.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); return 20; \
} } while (0)

int main(int argc, const char **argv)
{
    if (argc != 2) return 2;
    @autoreleasepool {
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        CHECK(data != nil);

        CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)data);
        CGFontRef reference = CGFontCreateWithDataProvider(dataProvider);
        CHECK(reference != NULL);

        CGDataProviderRef fileProvider = CGDataProviderCreateWithFilename(argv[1]);
        CHECK(fileProvider != NULL);
        CGFontRef font = CGFontCreateWithDataProvider(fileProvider);
        CHECK(font != NULL);

        CHECK(CGFontGetNumberOfGlyphs(font) == CGFontGetNumberOfGlyphs(reference));
        CHECK(CGFontGetNumberOfGlyphs(font) > 0);
        CHECK(CGFontGetUnitsPerEm(font) == CGFontGetUnitsPerEm(reference));
        CHECK(CGFontGetAscent(font) == CGFontGetAscent(reference));
        CHECK(CGFontGetDescent(font) == CGFontGetDescent(reference));

        CFStringRef name = CGFontCopyPostScriptName(font);
        CFStringRef referenceName = CGFontCopyPostScriptName(reference);
        CHECK(name != NULL && referenceName != NULL);
        CHECK(CFEqual(name, referenceName));

        CGGlyph glyph = CGFontGetGlyphWithGlyphName(font, CFSTR("A"));
        CHECK(glyph != 0);
        CHECK(glyph == CGFontGetGlyphWithGlyphName(reference, CFSTR("A")));
        int advance = 0, referenceAdvance = 0;
        CHECK(CGFontGetGlyphAdvances(font, &glyph, 1, &advance));
        CHECK(CGFontGetGlyphAdvances(reference, &glyph, 1, &referenceAdvance));
        CHECK(advance == referenceAdvance && advance > 0);

        // The font owns its bytes: it keeps working after the provider is gone.
        CGDataProviderRelease(fileProvider);
        CHECK(CGFontGetGlyphAdvances(font, &glyph, 1, &advance) && advance == referenceAdvance);

        CFRelease(name); CFRelease(referenceName);
        CGFontRelease(font); CGFontRelease(reference);
        CGDataProviderRelease(dataProvider);
        printf("PASS\n");
    }
    return 0;
}
