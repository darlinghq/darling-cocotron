/* Copyright (C) 2026 Lubos Dolezel */
/* CTFontCreateUIFontForLanguage returns a font for every UI font type, with the
 * default point size of the type when the requested size is 0 (sizes as
 * observed through the public API on macOS 10.14.4), the requested size when
 * it is not 0, and the bold face for the emphasized types. Types outside the
 * enumeration give NULL. */
#include <CoreText/CoreText.h>
#include <stdio.h>

static int failures;

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); failures++; } } while (0)

static const struct { int type; double size; int bold; } expected[] = {
    { 0, 12, 0 }, { 1, 10, 0 }, { 2, 13, 0 }, { 3, 13, 1 }, { 4, 11, 0 },
    { 5, 11, 1 }, { 6, 9, 0 }, { 7, 9, 1 }, { 8, 12, 0 }, { 9, 13, 0 },
    { 10, 10, 0 }, { 11, 14, 0 }, { 12, 14, 0 }, { 13, 14, 0 }, { 14, 14, 0 },
    { 15, 13, 0 }, { 16, 13, 0 }, { 17, 11, 0 }, { 18, 13, 1 }, { 19, 9, 0 },
    { 20, 9, 1 }, { 21, 11, 0 }, { 22, 10, 0 }, { 23, 13, 0 }, { 24, 11, 0 },
};

int main(void) {
    for (unsigned i = 0; i < sizeof(expected) / sizeof(expected[0]); i++) {
        CTFontRef font = CTFontCreateUIFontForLanguage((CTFontUIFontType) expected[i].type, 0, NULL);
        if (font == NULL) {
            fprintf(stderr, "FAIL type %d: NULL\n", expected[i].type);
            failures++;
            continue;
        }
        if (CTFontGetSize(font) != expected[i].size) {
            fprintf(stderr, "FAIL type %d: size %g, expected %g\n", expected[i].type, CTFontGetSize(font), expected[i].size);
            failures++;
        }
        int bold = (CTFontGetSymbolicTraits(font) & kCTFontBoldTrait) != 0;
        if (bold != expected[i].bold) {
            fprintf(stderr, "FAIL type %d: bold %d, expected %d\n", expected[i].type, bold, expected[i].bold);
            failures++;
        }
        CHECK(CTFontGetAscent(font) > 0);
        CFRelease(font);

        CTFontRef sized = CTFontCreateUIFontForLanguage((CTFontUIFontType) expected[i].type, 20, NULL);
        CHECK(sized != NULL && CTFontGetSize(sized) == 20);
        if (sized != NULL)
            CFRelease(sized);
    }
    CHECK(CTFontCreateUIFontForLanguage(kCTFontUIFontNone, 0, NULL) == NULL);
    CHECK(CTFontCreateUIFontForLanguage((CTFontUIFontType) 1000, 0, NULL) == NULL);
    if (failures)
        return 1;
    printf("PASS coretext-ui-fonts\n");
    return 0;
}
