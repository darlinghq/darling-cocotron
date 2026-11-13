// CTLineCreateTruncatedLine. Expected values are computed from the font's own glyphs and advances (CTFont), not from CTLine code.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); ++failures; } printf(__VA_ARGS__); printf("\n"); } while (0)

static CTFontRef font;
static CFStringRef text;

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

static CTLineRef ellipsisLine(void) {
    const UniChar ellipsis = 0x2026;
    CFStringRef string = CFStringCreateWithCharacters(NULL, &ellipsis, 1);
    CTLineRef line = lineFor(string);
    CFRelease(string);
    return line;
}

static CFIndex glyphsOf(CTLineRef line, CGGlyph *out, CFIndex *indices) {
    CFIndex n = 0;
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    for (CFIndex r = 0; r < CFArrayGetCount(runs); ++r) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
        CFIndex count = CTRunGetGlyphCount(run);
        CTRunGetGlyphs(run, CFRangeMake(0, 0), out + n);
        if (indices) CTRunGetStringIndices(run, CFRangeMake(0, 0), indices + n);
        n += count;
    }
    return n;
}

// font-level glyph and advance of one UTF-16 unit
static void metric(UniChar c, CGGlyph *glyph, double *advance) {
    CGSize size;
    CTFontGetGlyphsForCharacters(font, &c, glyph, 1);
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, glyph, &size, 1);
    *advance = size.width;
}

int main(void) { @autoreleasepool {
    font = CTFontCreateWithName(CFSTR("DejaVu Sans"), 16, NULL);
    text = CFSTR("The quick brown fox jumps over the lazy dog");
    CFIndex length = CFStringGetLength(text);
    CGGlyph glyph[64], ellipsisGlyph; double adv[64], ellipsisAdv, maxAdv = 0, total = 0;
    for (CFIndex i = 0; i < length; ++i) {
        metric(CFStringGetCharacterAtIndex(text, i), &glyph[i], &adv[i]);
        total += adv[i];
        if (adv[i] > maxAdv) maxAdv = adv[i];
    }
    metric(0x2026, &ellipsisGlyph, &ellipsisAdv);
    CTLineRef full = lineFor(text);
    CHECK(fabs(CTLineGetTypographicBounds(full, NULL, NULL, NULL) - total) < 0.001, "reference width %.3f matches the untruncated line", total);

    double W = 180;
    CGGlyph g[128]; CFIndex idx[128]; CFIndex n;
    // A NULL token means no token: the text is cut off. End keeps the largest prefix p with prefix(p) <= W.
    CFIndex p = 0; double used = 0;
    while (p < length && used + adv[p] <= W) used += adv[p++];
    CTLineRef end = CTLineCreateTruncatedLine(full, W, kCTLineTruncationEnd, NULL);
    CHECK(end != NULL, "end truncation without a token returns a line");
    if (end) {
        n = glyphsOf(end, g, idx);
        CHECK(n == p && memcmp(g, glyph, p * sizeof(CGGlyph)) == 0, "end: %ld glyphs, the first %ld characters and nothing else", (long)n, (long)p);
        double w = CTLineGetTypographicBounds(end, NULL, NULL, NULL);
        CHECK(fabs(w - used) < 0.001 && w <= W && w > W - maxAdv, "end: width %.3f equals %.3f, fits %.0f within one character", w, used, W);
        CFRange r = CTLineGetStringRange(end);
        CHECK(r.location == 0 && r.length == length, "end: string range still covers the original line (%ld,%ld)", (long)r.location, (long)r.length);
        CHECK(n == p && idx[0] == 0 && idx[p - 1] == p - 1, "end: kept glyphs keep their original string indices");
        CFRelease(end);
    }
    // Start keeps the smallest suffix start s with suffix(s) <= W
    CFIndex s = length; used = 0;
    while (s > 0 && used + adv[s - 1] <= W) used += adv[--s];
    CTLineRef start = CTLineCreateTruncatedLine(full, W, kCTLineTruncationStart, NULL);
    CHECK(start != NULL, "start truncation without a token returns a line");
    if (start) {
        n = glyphsOf(start, g, idx);
        CHECK(n == length - s && memcmp(g, glyph + s, (length - s) * sizeof(CGGlyph)) == 0, "start: the last %ld characters and nothing else", (long)(length - s));
        double w = CTLineGetTypographicBounds(start, NULL, NULL, NULL);
        CHECK(fabs(w - used) < 0.001 && w <= W, "start: width %.3f equals %.3f and fits", w, used);
        CFRelease(start);
    }
    // Middle: first and last glyph survive, nothing between them is a token, it fits, and no character could still be added
    CTLineRef middle = CTLineCreateTruncatedLine(full, W, kCTLineTruncationMiddle, NULL);
    CHECK(middle != NULL, "middle truncation without a token returns a line");
    if (middle) {
        n = glyphsOf(middle, g, idx);
        double w = CTLineGetTypographicBounds(middle, NULL, NULL, NULL);
        CFIndex cut = 0;
        while (cut < n && idx[cut] == cut) ++cut;
        CHECK(n > 3 && n < length && g[0] == glyph[0] && g[n - 1] == glyph[length - 1] && cut > 0 && cut < n, "middle: starts with T, ends with g, a gap between (prefix %ld of %ld glyphs)", (long)cut, (long)n);
        CHECK(w <= W && w > W - maxAdv, "middle: width %.3f fits %.0f and is within one character of it", w, W);
        CHECK(cut > 0 && memcmp(g, glyph, cut * sizeof(CGGlyph)) == 0 && memcmp(g + cut, glyph + length - (n - cut), (n - cut) * sizeof(CGGlyph)) == 0, "middle: both ends are untouched pieces of the text");
        CFRelease(middle);
    }
    // an explicit ellipsis token: ellipsis glyph last, takes part in the width
    CTLineRef ellipsisToken = ellipsisLine();
    p = 0; used = ellipsisAdv;
    while (p < length && used + adv[p] <= W) used += adv[p++];
    CTLineRef withEllipsis = CTLineCreateTruncatedLine(full, W, kCTLineTruncationEnd, ellipsisToken);
    CHECK(withEllipsis != NULL, "an explicit ellipsis token returns a line");
    if (withEllipsis) {
        n = glyphsOf(withEllipsis, g, idx);
        CHECK(n == p + 1 && memcmp(g, glyph, p * sizeof(CGGlyph)) == 0 && g[p] == ellipsisGlyph, "ellipsis: first %ld characters, then the ellipsis glyph", (long)p);
        double w = CTLineGetTypographicBounds(withEllipsis, NULL, NULL, NULL);
        CHECK(fabs(w - used) < 0.001 && w <= W, "ellipsis: width %.3f equals %.3f", w, used);
        CHECK(n == p + 1 && idx[p] == p, "ellipsis: its glyph maps to the first removed character");
        CFRelease(withEllipsis);
    }
    CFRelease(ellipsisToken);
    // custom token
    CTLineRef token = lineFor(CFSTR("[..]"));
    double tokenWidth = CTLineGetTypographicBounds(token, NULL, NULL, NULL);
    CTLineRef custom = CTLineCreateTruncatedLine(full, W, kCTLineTruncationEnd, token);
    CHECK(custom != NULL, "custom token returns a line");
    if (custom) {
        n = glyphsOf(custom, g, idx);
        CGGlyph tg[8]; glyphsOf(token, tg, NULL);
        CHECK(n > 4 && memcmp(g + n - 4, tg, 4 * sizeof(CGGlyph)) == 0, "custom token glyphs close the line");
        CHECK(CTLineGetTypographicBounds(custom, NULL, NULL, NULL) <= W && tokenWidth > 0, "custom token line fits");
        CFRelease(custom);
    }
    CFRelease(token);
    // fits: unchanged content
    CTLineRef same = CTLineCreateTruncatedLine(full, 2000, kCTLineTruncationEnd, NULL);
    CHECK(same != NULL && CTLineGetGlyphCount(same) == CTLineGetGlyphCount(full) && fabs(CTLineGetTypographicBounds(same, NULL, NULL, NULL) - total) < 0.001, "a line that fits comes back unchanged");
    if (same) CFRelease(same);
    CTLineRef wide = ellipsisLine();
    CTLineRef tiny = CTLineCreateTruncatedLine(full, 2, kCTLineTruncationEnd, wide);
    CHECK(tiny == NULL, "a width smaller than the token returns NULL");
    if (tiny) CFRelease(tiny);
    CFRelease(wide);
    CFRelease(full); CFRelease(font);
    printf("RESULT failures=%d\n", failures);
    return failures ? 1 : 0;
} }
