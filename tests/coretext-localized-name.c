// SPDX-License-Identifier: GPL-3.0-only
// Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
/* Runs the real CTFontCopyLocalizedName of CoreText/CTFont.m against a mock CTFontCopyName.
 *
 * tests/coretext-localized-name.sh extracts the function text from CTFont.m. Apple documents the result as the
 * font's name for the key (NULL when the font has none) and actualLanguage as an output; callers such as
 * Chromium pre-fill it and read it back, so it must be written whenever the pointer is non-NULL. */
#include <stdio.h>
#include <string.h>

typedef const struct OpaqueFont *CTFontRef;
typedef const char *CFStringRef;
#define _Nullable
#define nil 0

static const char kFamilyKey[] = "CTFontFamilyName", kFamily[] = "Helvetica";
static CTFontRef lastFont;
static CFStringRef lastKey;
static int copyNameCalls, nullArgCalls;
static CFStringRef CTFontCopyName(CTFontRef font, CFStringRef nameKey)
{
    copyNameCalls++; lastFont = font; lastKey = nameKey;
    /* The real CTFontCopyName dereferences a NULL font; flag the call instead of hiding it. */
    if (!font || !nameKey) { nullArgCalls++; return NULL; }
    return kFamily;
}

#include FUNCTION_INC

static int fails, checks;
#define CK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void)
{
    CTFontRef font = (CTFontRef)&checks;
    CFStringRef sentinel = "sentinel", language = sentinel;

    CFStringRef name = CTFontCopyLocalizedName(font, kFamilyKey, &language);
    CK(name == kFamily, "returns the name CTFontCopyName gives for the key (got %s)", name ? name : "NULL");
    CK(copyNameCalls == 1 && lastFont == font && lastKey == kFamilyKey, "asks CTFontCopyName for the same font and key");
    CK(language == NULL, "writes NULL to actualLanguage (got %s)", language ? language : "NULL");

    CK(CTFontCopyLocalizedName(font, kFamilyKey, NULL) == kFamily, "accepts a NULL actualLanguage");

    language = sentinel;
    copyNameCalls = 0;
    CK(CTFontCopyLocalizedName(NULL, kFamilyKey, &language) == NULL, "NULL font, NULL result");
    CK(language == NULL, "NULL font still clears actualLanguage");

    language = sentinel;
    CK(CTFontCopyLocalizedName(font, NULL, &language) == NULL, "NULL key, NULL result");
    CK(language == NULL, "NULL key still clears actualLanguage");
    CK(CTFontCopyLocalizedName(NULL, NULL, NULL) == NULL, "NULL font, key and actualLanguage, NULL result");
    CK(copyNameCalls == 0 && nullArgCalls == 0, "never calls CTFontCopyName for a NULL font or key (%d calls)", copyNameCalls);

    printf("%s: %d checks, %d failed\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails != 0;
}
