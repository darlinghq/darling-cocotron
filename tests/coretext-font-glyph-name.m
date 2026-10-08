#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); return 20; \
} } while (0)

typedef CFStringRef (*CopyName)(CTFontRef, CGGlyph);

static CGFontRef loadFont(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return NULL;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGFontRef font = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    return font;
}

int main(int argc, const char **argv)
{
    if (argc != 3) return 2;
    bool api = strcmp(argv[2], "api") == 0;
    if (!api && strcmp(argv[2], "backend") != 0) return 2;
    CopyName copyName = (CopyName)dlsym(RTLD_DEFAULT, "CTFontCopyNameForGlyph");
    if (api && !copyName) {
        fputs("missing CTFontCopyNameForGlyph export\n", stderr);
        return 10;
    }
    NSAutoreleasePool *outer = [NSAutoreleasePool new];
    NSString *directory = [NSString stringWithUTF8String:argv[1]];
    NSArray *files = @[@"conforming.ttf", @"tolerated-long.ttf", @"nameless.ttf"];
    for (NSUInteger index = 0; index < [files count]; ++index) {
        NSAutoreleasePool *inner = [NSAutoreleasePool new];
        CGFontRef graphics = loadFont([directory stringByAppendingPathComponent:files[index]]);
        CHECK(graphics != NULL);
        CTFontRef font = CTFontCreateWithGraphicsFont(graphics, 18, NULL, NULL);
        CHECK(font != NULL);
        CHECK(CGFontGetNumberOfGlyphs(graphics) == (index == 2 ? 2 : 3));
        if (index == 2) {
            CHECK(CGFontCopyGlyphNameForGlyph(graphics, 1) == NULL);
            if (api) CHECK(copyName(font, 1) == NULL);
        } else {
            char nameBytes[151];
            size_t length = index == 0 ? 63 : 150;
            memset(nameBytes, index == 0 ? 'n' : 'g', length);
            nameBytes[length] = 0;
            NSString *wanted = [NSString stringWithUTF8String:nameBytes];
            CGGlyph glyph = CGFontGetGlyphWithGlyphName(graphics, (CFStringRef)wanted);
            CHECK(glyph == 2);
            CFStringRef result = api ? copyName(font, glyph) : CGFontCopyGlyphNameForGlyph(graphics, glyph);
            CHECK(result != NULL && CFGetTypeID(result) == CFStringGetTypeID());
            if (![(NSString *)result isEqualToString:wanted]) {
                fprintf(stderr, "glyph name length %lu, expected %lu\n",
                        (unsigned long)CFStringGetLength(result), (unsigned long)length);
                return 20;
            }
            CHECK((api ? CTFontGetGlyphWithName(font, result) :
                   CGFontGetGlyphWithGlyphName(graphics, result)) == glyph);
            CFStringRef ordinary = api ? copyName(font, 1) : CGFontCopyGlyphNameForGlyph(graphics, 1);
            CFStringRef notdef = api ? copyName(font, 0) : CGFontCopyGlyphNameForGlyph(graphics, 0);
            CHECK(ordinary && [(NSString *)ordinary isEqualToString:@"A"]);
            CHECK(notdef && [(NSString *)notdef isEqualToString:@".notdef"]);
            if (api) {
                CHECK(copyName(NULL, 0) == NULL);
                CHECK(copyName(font, 3) == NULL && copyName(font, UINT16_MAX) == NULL);
            }
            CFRelease(font);
            CGFontRelease(graphics);
            [inner drain];
            CHECK(CFStringGetLength(result) == (CFIndex)length);
            char preserved[151];
            CHECK(CFStringGetCString(result, preserved, sizeof(preserved), kCFStringEncodingUTF8) &&
                  strcmp(preserved, nameBytes) == 0);
            CHECK([(NSString *)ordinary isEqualToString:@"A"]);
            CHECK([(NSString *)notdef isEqualToString:@".notdef"]);
            CFRelease(result); CFRelease(ordinary); CFRelease(notdef);
            continue;
        }
        CFRelease(font);
        CGFontRelease(graphics);
        [inner drain];
    }
    [outer drain];
    puts(api ? "CT glyph-name adapter, exact names and owned lifetime passed" :
               "CG glyph names preserved, including FreeType-tolerated long input");
    return 0;
}
