// CTLineGetTrailingWhitespaceWidth: the typographic width of the whitespace at the end of a line.
// Expected values come from the font's own advance of the space glyph, not from CTLine code.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); ++failures; } printf(__VA_ARGS__); printf("\n"); } while (0)

static CTLineRef lineFor(CTFontRef font, CFStringRef string) {
    const void *keys[] = {kCTFontAttributeName};
    const void *values[] = {font};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef text = CFAttributedStringCreate(NULL, string, attributes);
    CTLineRef line = CTLineCreateWithAttributedString(text);
    CFRelease(text);
    CFRelease(attributes);
    return line;
}

int main(void) { @autoreleasepool {
    CTFontRef font = CTFontCreateWithName(CFSTR("DejaVu Sans"), 20, NULL);
    UniChar space = ' ';
    CGGlyph spaceGlyph = 0;
    CGSize spaceAdvance = CGSizeZero;
    CTFontGetGlyphsForCharacters(font, &space, &spaceGlyph, 1);
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &spaceGlyph, &spaceAdvance, 1);
    CHECK(spaceAdvance.width > 1, "font reports a positive space advance %.3f", spaceAdvance.width);

    CTLineRef plain = lineFor(font, CFSTR("Hello"));
    CHECK(CTLineGetTrailingWhitespaceWidth(plain) == 0, "no trailing whitespace reads 0");
    CTLineRef padded = lineFor(font, CFSTR("Hello   "));
    CHECK(fabs(CTLineGetTrailingWhitespaceWidth(padded) - 3 * spaceAdvance.width) < 0.001, "three trailing spaces read %.3f (expected %.3f)", CTLineGetTrailingWhitespaceWidth(padded), 3 * spaceAdvance.width);
    CHECK(fabs(CTLineGetTypographicBounds(padded, NULL, NULL, NULL) - CTLineGetTypographicBounds(plain, NULL, NULL, NULL) - 3 * spaceAdvance.width) < 0.001, "the typographic width includes the trailing spaces");
    CTLineRef inner = lineFor(font, CFSTR("a b"));
    CHECK(CTLineGetTrailingWhitespaceWidth(inner) == 0, "a space inside the line does not count");
    CTLineRef blank = lineFor(font, CFSTR("  "));
    CHECK(fabs(CTLineGetTrailingWhitespaceWidth(blank) - 2 * spaceAdvance.width) < 0.001, "an all-space line is all trailing whitespace");
    CHECK(CTLineGetTrailingWhitespaceWidth(NULL) == 0, "NULL line reads 0");
    CFRelease(plain); CFRelease(padded); CFRelease(inner); CFRelease(blank); CFRelease(font);
    printf("RESULT failures=%d\n", failures);
    return failures ? 1 : 0;
} }
