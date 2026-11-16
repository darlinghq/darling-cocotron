// CTLineEnumerateCaretOffsets: leading and trailing edge of every character, in visual order.
// Expected offsets are running sums of the font's own advances (CTFont), not CTLine values.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <math.h>
#ifndef FONT_NAME
#define FONT_NAME "DejaVu Sans"
#endif
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); ++failures; } printf(__VA_ARGS__); printf("\n"); } while (0)

int main(void) { @autoreleasepool {
    CTFontRef font = CTFontCreateWithName(CFSTR(FONT_NAME), 18, NULL);
    const void *keys[] = {kCTFontAttributeName}, *values[] = {font};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFStringRef string = CFSTR("Wide i");
    CFAttributedStringRef attributed = CFAttributedStringCreate(NULL, string, attributes);
    CTLineRef line = CTLineCreateWithAttributedString(attributed);

    CFIndex length = CFStringGetLength(string);
    double wantStorage[16]; double *want = wantStorage; double x = 0;
    for (CFIndex i = 0; i < length; ++i) {
        UniChar c = CFStringGetCharacterAtIndex(string, i); CGGlyph g; CGSize a;
        CTFontGetGlyphsForCharacters(font, &c, &g, 1);
        CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &g, &a, 1);
        want[2 * i] = x; x += a.width; want[2 * i + 1] = x;
    }
    __block int calls = 0, bad = 0;
    __block double lastOffset = -1;
    CTLineEnumerateCaretOffsets(line, ^(double offset, CFIndex charIndex, bool leadingEdge, bool *stop) {
        int k = calls++;
        if (k >= 2 * length || fabs(offset - want[k]) > 0.001 || charIndex != k / 2 || leadingEdge != (k % 2 == 0) || offset < lastOffset) { ++bad; printf("  call %d: offset %.3f index %ld leading %d\n", k, offset, (long)charIndex, leadingEdge); }
        lastOffset = offset;
    });
    CHECK(calls == 2 * length, "%d callbacks for %ld characters", calls, (long)length);
    CHECK(bad == 0, "every callback matches the running sum of advances, index and edge");
    CHECK(fabs(lastOffset - CTLineGetTypographicBounds(line, NULL, NULL, NULL)) < 0.001, "the last trailing edge is the line width");
    __block int stopped = 0;
    CTLineEnumerateCaretOffsets(line, ^(double offset, CFIndex charIndex, bool leadingEdge, bool *stop) { if (++stopped == 3) *stop = true; });
    CHECK(stopped == 3, "setting stop ends the enumeration (%d calls)", stopped);
    // QUIRK check (macOS 26.7.3): the trailing edge of a cluster reports the index of its last UTF-16 unit
    {
        UniChar chars[] = {'a', 'e', 0x0301, 'f'};
        CFStringRef accented = CFStringCreateWithCharacters(NULL, chars, 4);
        CFAttributedStringRef accentedText = CFAttributedStringCreate(NULL, accented, attributes);
        CTLineRef accentedLine = CTLineCreateWithAttributedString(accentedText);
        static CFIndex seen[16]; static bool lead[16]; __block int k = 0;
        CTLineEnumerateCaretOffsets(accentedLine, ^(double offset, CFIndex charIndex, bool leadingEdge, bool *stop) { if (k < 16) { seen[k] = charIndex; lead[k] = leadingEdge; } ++k; });
        CHECK(k == 6 && seen[2] == 1 && lead[2] && seen[3] == 2 && !lead[3] && seen[4] == 3 && lead[4], "cluster e + U+0301: leading index 1, trailing index 2; %d callbacks", k);
        CFRelease(accentedLine); CFRelease(accentedText); CFRelease(accented);
    }
    CTLineEnumerateCaretOffsets(NULL, ^(double o, CFIndex i, bool l, bool *s) { ++failures; });
    CFRelease(line); CFRelease(attributed); CFRelease(attributes); CFRelease(font);
    printf("RESULT failures=%d\n", failures);
    return failures ? 1 : 0;
} }
