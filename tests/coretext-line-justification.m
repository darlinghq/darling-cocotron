// CTLineCreateJustifiedLine. Expected advances and positions come from the font's own advances (CTFont), not from CTLine code.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); ++failures; } printf(__VA_ARGS__); printf("\n"); } while (0)

static CTFontRef font;

static CTLineRef lineFor(CFStringRef string) {
    const void *keys[] = {kCTFontAttributeName};
    const void *values[] = {font};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef attributed = CFAttributedStringCreate(NULL, string, attributes);
    CTLineRef line = CTLineCreateWithAttributedString(attributed);
    CFRelease(attributed);
    CFRelease(attributes);
    return line;
}

static CFIndex collect(CTLineRef line, CGPoint *positions, CGSize *advances) {
    CFIndex n = 0;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex r = 0; r < CFArrayGetCount(runs); ++r) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
        CTRunGetPositions(run, CFRangeMake(0, 0), positions + n);
        CTRunGetAdvances(run, CFRangeMake(0, 0), advances + n);
        n += CTRunGetGlyphCount(run);
    }
    return n;
}

// Checks that glyph i of the justified line has the font advance of character i plus extra for each space, and sits at the sum of the advances before it.
static void checkLayout(const char *name, CFStringRef string, CTLineRef justified, double extraPerSpace) {
    CFIndex length = CFStringGetLength(string);
    CGPoint pos[128]; CGSize adv[128];
    CFIndex n = collect(justified, pos, adv);
    CHECK(n == length, "%s: glyph count %ld equals the character count %ld", name, (long)n, (long)length);
    double x = 0; int ok = n == length;
    for (CFIndex i = 0; ok && i < length; ++i) {
        UniChar c = CFStringGetCharacterAtIndex(string, i); CGGlyph glyph; CGSize base;
        CTFontGetGlyphsForCharacters(font, &c, &glyph, 1);
        CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &glyph, &base, 1);
        double want = base.width + (c == ' ' ? extraPerSpace : 0);
        if (fabs(adv[i].width - want) > 0.001 || fabs(pos[i].x - x) > 0.001) { printf("  glyph %ld: advance %.3f want %.3f, x %.3f want %.3f\n", (long)i, adv[i].width, want, pos[i].x, x); ok = 0; }
        x += want;
    }
    CHECK(ok, "%s: every advance and position matches the font advance plus the space extra", name);
}

int main(void) { @autoreleasepool {
    font = CTFontCreateWithName(CFSTR("DejaVu Sans"), 16, NULL);
    CFStringRef text = CFSTR("The quick brown fox");
    CTLineRef line = lineFor(text);
    double natural = CTLineGetTypographicBounds(line, NULL, NULL, NULL);

    CTLineRef wide = CTLineCreateJustifiedLine(line, 1.0, natural + 60);
    CHECK(wide != NULL, "full justification returns a line");
    if (wide) {
        CHECK(fabs(CTLineGetTypographicBounds(wide, NULL, NULL, NULL) - (natural + 60)) < 0.001, "width grows from %.3f to %.3f", natural, natural + 60);
        checkLayout("full", text, wide, 20);
        CFRange r = CTLineGetStringRange(wide);
        CHECK(r.location == 0 && r.length == CFStringGetLength(text), "string range is unchanged");
        CFRelease(wide);
    }
    CTLineRef half = CTLineCreateJustifiedLine(line, 0.5, natural + 60);
    CHECK(half != NULL && fabs(CTLineGetTypographicBounds(half, NULL, NULL, NULL) - (natural + 30)) < 0.001, "factor 0.5 closes half of the gap");
    if (half) { checkLayout("half", text, half, 10); CFRelease(half); }
    CTLineRef tight = CTLineCreateJustifiedLine(line, 1.0, natural - 12);
    CHECK(tight != NULL && fabs(CTLineGetTypographicBounds(tight, NULL, NULL, NULL) - (natural - 12)) < 0.001, "a width below the natural width squeezes the line");
    if (tight) { checkLayout("tight", text, tight, -4); CFRelease(tight); }
    CTLineRef none = CTLineCreateJustifiedLine(line, 0.0, natural + 60);
    CHECK(none != NULL && fabs(CTLineGetTypographicBounds(none, NULL, NULL, NULL) - natural) < 0.001, "factor 0 leaves the width alone");
    if (none) CFRelease(none);
    // 1.0 and above is full justification, 0 and below none
    CTLineRef over = CTLineCreateJustifiedLine(line, 2.0, natural + 60);
    CHECK(over != NULL && fabs(CTLineGetTypographicBounds(over, NULL, NULL, NULL) - (natural + 60)) < 0.001, "factor 2.0 is full justification, not 2x");
    if (over) { checkLayout("over", text, over, 20); CFRelease(over); }
    CTLineRef under = CTLineCreateJustifiedLine(line, -1.0, natural + 60);
    CHECK(under != NULL && fabs(CTLineGetTypographicBounds(under, NULL, NULL, NULL) - natural) < 0.001, "factor -1 is no justification, not a squeeze");
    if (under) { checkLayout("under", text, under, 0); CFRelease(under); }

    // no spaces: the extra goes between the glyphs (4 gaps in "Hello")
    CFStringRef word = CFSTR("Hello");
    CTLineRef hello = lineFor(word);
    double helloWidth = CTLineGetTypographicBounds(hello, NULL, NULL, NULL);
    CTLineRef spread = CTLineCreateJustifiedLine(hello, 1.0, helloWidth + 20);
    CHECK(spread != NULL, "a line without spaces returns a line");
    if (spread) {
        CGPoint pos[8]; CGSize adv[8];
        CFIndex n = collect(spread, pos, adv);
        CHECK(n == 5 && fabs(CTLineGetTypographicBounds(spread, NULL, NULL, NULL) - (helloWidth + 20)) < 0.001, "width reaches %.3f", helloWidth + 20);
        CHECK(n == 5 && fabs(pos[4].x + adv[4].width - (helloWidth + 20)) < 0.001, "the last glyph ends at the justified width");
        CHECK(n == 5 && fabs(pos[1].x - pos[0].x - adv[0].width) < 0.001 && adv[0].width > 0, "gaps open after glyphs 0-3, so glyph 1 sits after glyph 0's stretched advance");
        CFRelease(spread);
    }
    // trailing whitespace does not take part: the visible text ends at the justified width
    CFStringRef padded = CFSTR("Hello world   ");
    CTLineRef paddedLine = lineFor(padded);
    double trailing = CTLineGetTrailingWhitespaceWidth(paddedLine);
    double content = CTLineGetTypographicBounds(paddedLine, NULL, NULL, NULL) - trailing;
    CTLineRef paddedJustified = CTLineCreateJustifiedLine(paddedLine, 1.0, content + 30);
    CHECK(paddedJustified != NULL, "a line with trailing spaces returns a line");
    if (paddedJustified) {
        CGPoint pos[32]; CGSize adv[32];
        CFIndex n = collect(paddedJustified, pos, adv);
        CHECK(n == 14 && fabs(pos[10].x + adv[10].width - (content + 30)) < 0.001, "the d of the last word ends at %.3f", content + 30);
        CHECK(n == 14 && fabs(CTLineGetTrailingWhitespaceWidth(paddedJustified) - trailing) < 0.001, "trailing whitespace keeps its width");
        CFRelease(paddedJustified);
    }
    CTLineRef single = lineFor(CFSTR("W"));
    CTLineRef same = CTLineCreateJustifiedLine(single, 1.0, 500);
    CHECK(same != NULL && fabs(CTLineGetTypographicBounds(same, NULL, NULL, NULL) - CTLineGetTypographicBounds(single, NULL, NULL, NULL)) < 0.001, "a single glyph cannot stretch and comes back unchanged");
    if (same) CFRelease(same);
    CHECK(CTLineCreateJustifiedLine(NULL, 1.0, 100) == NULL, "NULL line returns NULL");
    CFRelease(single); CFRelease(paddedLine); CFRelease(hello); CFRelease(line); CFRelease(font);
    printf("RESULT failures=%d\n", failures);
    return failures ? 1 : 0;
} }
