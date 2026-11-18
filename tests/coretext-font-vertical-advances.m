// Copyright (C) 2026 Lubos Dolezel
//
// CTFontGetAdvancesForGlyphs with kCTFontOrientationVertical.
// Usage: coretext-font-vertical-advances FIXTURE_DIRECTORY (DarlingVerticalTest.ttf, made by
// generate-vertical-font.py: vhea/vmtx advances that differ from the horizontal ones).
// On macOS 26.7.3 the vertical advance comes back positive in .width with .height 0.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

static int failures;
#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); failures++; } } while (0)

static void verifyAdvances(CGFontRef graphics, CGFloat size) {
    CTFontRef font = CTFontCreateWithGraphicsFont(graphics, size, NULL, NULL);
    const UniChar characters[] = {'A', 'B', 'C', 'B'};
    const int vmtxUnits[] = {1000, 600, 1200, 600};
    CGGlyph glyphs[4];
    CHECK(CTFontGetGlyphsForCharacters(font, characters, glyphs, 4));
    CGFloat unit = size / CGFontGetUnitsPerEm(graphics);

    CGSize horizontal[4], vertical[4], standard[4];
    double horizontalSum = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, glyphs, horizontal, 4);
    double standardSum = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationDefault, glyphs, standard, 4);
    double verticalSum = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationVertical, glyphs, vertical, 4);
    double verticalSumOnly = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationVertical, glyphs, NULL, 4);

    double expectedSum = 0;
    for (int i = 0; i < 4; ++i) {
        double expected = vmtxUnits[i] * unit;
        expectedSum += expected;
        CHECK(fabs(vertical[i].width - expected) < 1e-6);
        CHECK(vertical[i].height == 0);
        CHECK(fabs(vertical[i].width - horizontal[i].width) > 1);
        CHECK(fabs(standard[i].width - horizontal[i].width) < 1e-6);
    }
    CHECK(fabs(standardSum - horizontalSum) < 1e-6);
    CHECK(fabs(verticalSum - expectedSum) < 1e-6);
    CHECK(fabs(verticalSumOnly - verticalSum) < 1e-6);
    CFRelease(font);
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    @autoreleasepool {
        NSString *path = [[NSString stringWithUTF8String: argv[1]] stringByAppendingPathComponent: @"DarlingVerticalTest.ttf"];
        NSData *data = [NSData dataWithContentsOfFile: path];
        if (data == nil) return 2;
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef) data);
        CGFontRef graphics = CGFontCreateWithDataProvider(provider);
        CGDataProviderRelease(provider);
        CHECK(graphics != NULL);
        verifyAdvances(graphics, 20);
        verifyAdvances(graphics, 40);
        CGFontRelease(graphics);
    }
    if (failures == 0) puts("PASS");
    return failures ? 1 : 0;
}
