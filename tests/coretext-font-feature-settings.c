// Copyright (C) 2026 Lubos Dolezel
//
// CTFontCopyFeatureSettings on a font that has no feature settings applied. Documented contract
// (https://developer.apple.com/documentation/coretext/ctfontcopyfeaturesettings(_:)): the result holds the
// non-default feature settings applied to the font, or is NULL when the default settings should be used.
// A font made by name has no settings applied, so the result is NULL, and a copy of the font at another
// size has none either. What the result is for a font made with feature settings is not tested. Needs no window
// server.
#include <CoreText/CoreText.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
    CHECK(font != NULL);

    CFArrayRef settings = CTFontCopyFeatureSettings(font);
    CHECK(settings == NULL);
    if (settings)
        CFRelease(settings);

    CTFontRef copy = CTFontCreateCopyWithAttributes(font, 24, NULL, NULL);
    CHECK(copy != NULL);
    settings = CTFontCopyFeatureSettings(copy);
    CHECK(settings == NULL);
    if (settings)
        CFRelease(settings);
    if (copy)
        CFRelease(copy);

    CFRelease(font);
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
