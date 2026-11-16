// Copyright (C) 2026 Lubos Dolezel
//
// CGColorSpaceGetBaseColorSpace, CGColorSpaceGetColorTableCount and
// CGColorSpaceGetColorTable on indexed, pattern and plain spaces.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); return 20; } } while (0)

int main(void) {
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    const unsigned char palette[9] = {1, 2, 3, 4, 5, 6, 7, 8, 9};

    CGColorSpaceRef indexed = CGColorSpaceCreateIndexed(rgb, 2, palette);
    CHECK(indexed != NULL);
    CHECK(CGColorSpaceGetModel(indexed) == kCGColorSpaceModelIndexed);
    CHECK(CGColorSpaceGetBaseColorSpace(indexed) == rgb);
    CHECK(CGColorSpaceGetColorTableCount(indexed) == 3);
    uint8_t table[9];
    memset(table, 0, sizeof table);
    CGColorSpaceGetColorTable(indexed, table);
    CHECK(memcmp(table, palette, sizeof palette) == 0);

    // The count is the number of entries, not bytes, for any base space.
    const unsigned char grays[2] = {0, 255};
    CGColorSpaceRef grayIndexed = CGColorSpaceCreateIndexed(gray, 1, grays);
    CHECK(CGColorSpaceGetBaseColorSpace(grayIndexed) == gray);
    CHECK(CGColorSpaceGetColorTableCount(grayIndexed) == 2);
    uint8_t grayTable[2] = {7, 7};
    CGColorSpaceGetColorTable(grayIndexed, grayTable);
    CHECK(grayTable[0] == 0 && grayTable[1] == 255);

    // Spaces that are not indexed have no table and, unless they wrap another space, no base.
    CHECK(CGColorSpaceGetBaseColorSpace(rgb) == NULL);
    CHECK(CGColorSpaceGetColorTableCount(rgb) == 0);
    uint8_t untouched[4] = {99, 99, 99, 99};
    CGColorSpaceGetColorTable(rgb, untouched);
    CHECK(untouched[0] == 99 && untouched[3] == 99);

    CGColorSpaceRef pattern = CGColorSpaceCreatePattern(rgb);
    CHECK(pattern != NULL);
    CHECK(CGColorSpaceGetBaseColorSpace(pattern) == rgb);
    CHECK(CGColorSpaceGetColorTableCount(pattern) == 0);

    CGColorSpaceRef plainPattern = CGColorSpaceCreatePattern(NULL);
    CHECK(plainPattern != NULL);
    CHECK(CGColorSpaceGetBaseColorSpace(plainPattern) == NULL);

    CHECK(CGColorSpaceGetBaseColorSpace(NULL) == NULL);
    CHECK(CGColorSpaceGetColorTableCount(NULL) == 0);
    CGColorSpaceGetColorTable(NULL, untouched);
    puts("PASS");
    return 0;
}
