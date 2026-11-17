/* Copyright (C) 2026 Lubos Dolezel */
/* CTFontHasTable, CTFontManagerIsSupportedFont and the SFNTLayoutTypes feature numbers.
 * Expected values were observed on macOS 26.7.3 (and match the TrueType Font Feature Registry). */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static CFURLRef fileURL(const char *path) {
    return CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *) path, strlen(path), false);
}

static void writeFile(const char *path, size_t size) {
    FILE *f = fopen(path, "wb");
    for (size_t i = 0; i < size; i++) fputc('A' + (int) (i % 26), f);
    fclose(f);
}

static bool supported(const char *path) {
    CFURLRef url = fileURL(path);
    bool result = CTFontManagerIsSupportedFont(url);
    CFRelease(url);
    return result;
}

int main(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
    CHECK(font != NULL);
    CHECK(CTFontHasTable(font, 'head'));
    CHECK(CTFontHasTable(font, 'cmap'));
    CHECK(!CTFontHasTable(font, 'XXXX'));
    CHECK(!CTFontHasTable(font, 0));
    CFArrayRef tags = CTFontCopyAvailableTables(font, kCTFontTableOptionNoOptions);
    CHECK(tags != NULL);
    for (CFIndex i = 0; tags && i < CFArrayGetCount(tags); i++) {
        CTFontTableTag tag = (CTFontTableTag) (uintptr_t) CFArrayGetValueAtIndex(tags, i);
        CHECK(CTFontHasTable(font, tag));
    }
    if (tags) CFRelease(tags);
    CFRelease(font);

    CHECK(kNumberSpacingType == 6 && kMonospacedNumbersSelector == 0 && kProportionalNumbersSelector == 1);
    CHECK(kVerticalPositionType == 10 && kSuperiorsSelector == 1 && kInferiorsSelector == 2 && kOrdinalsSelector == 3);
    CHECK(kFractionsType == 11 && kNoFractionsSelector == 0 && kDiagonalFractionsSelector == 2);
    CHECK(kNumberCaseType == 21 && kLowerCaseNumbersSelector == 0 && kUpperCaseNumbersSelector == 1);
    CHECK(kLowerCaseType == 37 && kLowerCaseSmallCapsSelector == 1);
    CHECK(kUpperCaseType == 38 && kUpperCaseSmallCapsSelector == 1);

    char dir[] = "/tmp/ct-supported.XXXXXX";
    CHECK(mkdtemp(dir) != NULL);
    char path[512];
    const char *accepted[] = {"a.ttf", "a.otf", "a.ttc", "a.otc", "a.dfont", "a.pfb", "a.pfa", "a.suit", "a.TTF", "a.Otf", NULL};
    for (int i = 0; accepted[i]; i++) {
        snprintf(path, sizeof path, "%s/%s", dir, accepted[i]);
        writeFile(path, 64);
        CHECK(supported(path));
        unlink(path);
    }
    const char *refused[] = {"a.woff", "a.woff2", "a.fon", "a.bdf", "a.pcf", "a.txt", "a.ttf.bak", "noext", NULL};
    for (int i = 0; refused[i]; i++) {
        snprintf(path, sizeof path, "%s/%s", dir, refused[i]);
        writeFile(path, 64);
        CHECK(!supported(path));
        unlink(path);
    }
    snprintf(path, sizeof path, "%s/missing.ttf", dir);
    CHECK(!supported(path));
    snprintf(path, sizeof path, "%s/dir.ttf", dir);
    mkdir(path, 0700);
    CHECK(!supported(path));
    rmdir(path);
    snprintf(path, sizeof path, "%s/size.ttf", dir);
    /* test_quirk_four_byte_minimum */
    for (size_t size = 0; size <= 8; size++) {
        writeFile(path, size);
        CHECK(supported(path) == (size >= 4));
    }
    unlink(path);
    rmdir(dir);
    CFURLRef web = CFURLCreateWithString(NULL, CFSTR("http://example.com/a.ttf"), NULL);
    CHECK(!CTFontManagerIsSupportedFont(web));
    CFRelease(web);

    if (failures == 0) printf("PASS\n");
    return failures ? 1 : 0;
}
