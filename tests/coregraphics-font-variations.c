// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// CGFontCopyVariationAxes, CGFontCopyVariations and CGFontCreateCopyWithVariations. Behaviour observed on macOS 26.7.3
// and Mac OS X 10.14.4 (probe: mac-probes/gog-blockers/cgfont-variations.c; the program builds and runs there too):
// a font without variation axes gives NULL axes and NULL variations, and a copy with variations is the font itself;
// a variable font lists its axes as dictionaries (name, minimum, default, maximum), CGFontCopyVariations gives every
// axis (the default until set), a copy keeps the value that was asked for even outside the axis range, and a name that
// is not an axis is ignored. A variable font is read from a font file by a sequential data provider; the part with
// the variable font prints SKIP when no variable font file is installed.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static double number(CFTypeRef value)
{
    double result = -1e300;
    if (value != NULL && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue(value, kCFNumberDoubleType, &result);
    return result;
}

struct fileState {
    FILE *file;
};

static size_t fileGet(void *info, void *buffer, size_t count)
{
    return fread(buffer, 1, count, ((struct fileState *)info)->file);
}

static off_t fileSkip(void *info, off_t count)
{
    FILE *f = ((struct fileState *)info)->file;
    long before = ftell(f);
    if (fseek(f, count, SEEK_CUR) != 0)
        return 0;
    return ftell(f) - before;
}

static void fileRewind(void *info)
{
    rewind(((struct fileState *)info)->file);
}

static void fileRelease(void *info)
{
    fclose(((struct fileState *)info)->file);
    free(info);
}

static CGFontRef variableFont(void)
{
    static const char *paths[] = {
        "/System/Library/Fonts/Supplemental/Skia.ttf",
        "/Library/Fonts/Skia.ttf",
        "/Volumes/SystemRoot/usr/share/fonts/TTF/CascadiaCode.ttf",
        "/Volumes/SystemRoot/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf",
        "/Volumes/SystemRoot/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    };
    for (unsigned i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        FILE *f = fopen(paths[i], "rb");
        if (f == NULL)
            continue;
        struct fileState *state = malloc(sizeof(*state));
        state->file = f;
        CGDataProviderSequentialCallbacks callbacks = {0, fileGet, fileSkip, fileRewind, fileRelease};
        CGDataProviderRef provider = CGDataProviderCreateSequential(state, &callbacks);
        CGFontRef font = provider != NULL ? CGFontCreateWithDataProvider(provider) : NULL;
        if (provider != NULL)
            CGDataProviderRelease(provider);
        if (font != NULL) {
            CFArrayRef axes = CGFontCopyVariationAxes(font);
            if (axes != NULL) {
                CFRelease(axes);
                return font;
            }
            CGFontRelease(font);
        }
    }
    return NULL;
}

int main(void)
{
    CGFontRef plain = CGFontCreateWithFontName(CFSTR("Helvetica"));
    expect(plain != NULL, "a font to ask");
    if (plain != NULL) {
        expect(CGFontCopyVariationAxes(plain) == NULL, "a font without variations has no axes");
        expect(CGFontCopyVariations(plain) == NULL, "a font without variations has no variation settings");
        CGFontRef same = CGFontCreateCopyWithVariations(plain, NULL);
        expect(same == plain, "a copy with NULL variations is the font itself");
        CGFontRelease(same);
        CFStringRef name = CFSTR("Weight");
        double one = 1;
        CFNumberRef value = CFNumberCreate(NULL, kCFNumberDoubleType, &one);
        CFDictionaryRef set = CFDictionaryCreate(NULL, (const void **)&name, (const void **)&value, 1,
                                                 &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        same = CGFontCreateCopyWithVariations(plain, set);
        expect(same == plain, "a copy of a font without axes is the font itself");
        CGFontRelease(same);
        CFRelease(set);
        CFRelease(value);
        CGFontRelease(plain);
    }
    expect(CGFontCopyVariationAxes(NULL) == NULL && CGFontCopyVariations(NULL) == NULL &&
           CGFontCreateCopyWithVariations(NULL, NULL) == NULL, "NULL fonts give NULL");

    CGFontRef font = variableFont();
    if (font == NULL) {
        printf("SKIP no variable font file is installed\n");
    } else {
        CFArrayRef axes = CGFontCopyVariationAxes(font);
        expect(axes != NULL && CFArrayGetCount(axes) >= 1, "a variable font lists its axes");
        CFDictionaryRef axis = CFArrayGetValueAtIndex(axes, 0);
        CFStringRef name = CFDictionaryGetValue(axis, kCGFontVariationAxisName);
        double minimum = number(CFDictionaryGetValue(axis, kCGFontVariationAxisMinValue));
        double maximum = number(CFDictionaryGetValue(axis, kCGFontVariationAxisMaxValue));
        double base = number(CFDictionaryGetValue(axis, kCGFontVariationAxisDefaultValue));
        expect(name != NULL && CFGetTypeID(name) == CFStringGetTypeID(), "an axis has a name");
        expect(minimum <= base && base <= maximum && minimum < maximum, "the default is between the minimum and the maximum");

        CFDictionaryRef variations = CGFontCopyVariations(font);
        expect(variations != NULL && CFDictionaryGetCount(variations) == CFArrayGetCount(axes),
               "the variations list every axis");
        expect(variations != NULL && number(CFDictionaryGetValue(variations, name)) == base, "an axis not set is at its default");
        if (variations != NULL)
            CFRelease(variations);

        double target = maximum;
        CFNumberRef value = CFNumberCreate(NULL, kCFNumberDoubleType, &target);
        CFDictionaryRef set = CFDictionaryCreate(NULL, (const void **)&name, (const void **)&value, 1,
                                                 &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CGFontRef varied = CGFontCreateCopyWithVariations(font, set);
        expect(varied != NULL && varied != font, "a copy with a variation is another font");
        variations = varied != NULL ? CGFontCopyVariations(varied) : NULL;
        expect(variations != NULL && number(CFDictionaryGetValue(variations, name)) == target, "the copy has the value that was set");
        if (variations != NULL)
            CFRelease(variations);
        variations = CGFontCopyVariations(font);
        expect(variations != NULL && number(CFDictionaryGetValue(variations, name)) == base, "the original keeps its settings");
        if (variations != NULL)
            CFRelease(variations);
        CFRelease(set);
        CFRelease(value);

        // the value asked for is kept even outside the axis range
        double outside = maximum * 100;
        value = CFNumberCreate(NULL, kCFNumberDoubleType, &outside);
        set = CFDictionaryCreate(NULL, (const void **)&name, (const void **)&value, 1,
                                 &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CGFontRef wild = CGFontCreateCopyWithVariations(font, set);
        variations = wild != NULL ? CGFontCopyVariations(wild) : NULL;
        expect(variations != NULL && number(CFDictionaryGetValue(variations, name)) == outside,
               "a value outside the axis range is kept as given");
        if (variations != NULL)
            CFRelease(variations);
        CFRelease(set);
        CFRelease(value);
        CGFontRelease(wild);

        // a name that is not an axis changes nothing
        CFStringRef bogus = CFSTR("NoSuchAxis");
        double one = 1;
        value = CFNumberCreate(NULL, kCFNumberDoubleType, &one);
        set = CFDictionaryCreate(NULL, (const void **)&bogus, (const void **)&value, 1,
                                 &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CGFontRef ignored = CGFontCreateCopyWithVariations(font, set);
        expect(ignored != NULL, "an unknown axis name still gives a font");
        variations = ignored != NULL ? CGFontCopyVariations(ignored) : NULL;
        expect(variations != NULL && number(CFDictionaryGetValue(variations, name)) == base, "an unknown axis name is ignored");
        if (variations != NULL)
            CFRelease(variations);
        CFRelease(set);
        CFRelease(value);
        CGFontRelease(ignored);
        CGFontRelease(varied);
        CFRelease(axes);
        CGFontRelease(font);
    }

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
