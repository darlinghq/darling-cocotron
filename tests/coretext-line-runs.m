/*
 Copyright (C) 2026 Lubos Dolezel

 Checks the CTLine / CTRun object model: distinct CF type identities, runs
 split per attribute range, string indices that stay inside the run range
 for combining sequences, and range arguments that are clamped.
*/
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <stdio.h>

static unsigned failures;
static void expect(BOOL value, const char *label)
{
    printf("%s %s\n", value ? "PASS" : "FAIL", label);
    if (!value)
        ++failures;
}

int main(void)
{
    @autoreleasepool {
        CTFontRef first = CTFontCreateWithName(CFSTR("DejaVu Sans"), 20, NULL);
        CTFontRef second = CTFontCreateWithName(CFSTR("DejaVu Sans"), 30, NULL);
        // "ab" (size 20), then "e" + U+0301 combining acute + "c" (size 30).
        CFMutableAttributedStringRef text = CFAttributedStringCreateMutable(NULL, 0);
        CFAttributedStringReplaceString(text, CFRangeMake(0, 0), CFSTR("abe\xCC\x81" "c"));
        CFAttributedStringSetAttribute(text, CFRangeMake(0, 2), kCTFontAttributeName, first);
        CFAttributedStringSetAttribute(text, CFRangeMake(2, 3), kCTFontAttributeName, second);
        CTLineRef line = CTLineCreateWithAttributedString(text);
        expect(line != NULL, "line created");

        expect(CFGetTypeID(line) == CTLineGetTypeID(), "CFGetTypeID(line) is CTLineGetTypeID");
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        expect(CFArrayGetCount(runs) >= 2, "one run per font range at least");
        expect(CFGetTypeID(CFArrayGetValueAtIndex(runs, 0)) == CTRunGetTypeID(),
               "CFGetTypeID(run) is CTRunGetTypeID");
        expect(CTLineGetTypeID() != CTRunGetTypeID(), "line and run type ids differ");

        BOOL inside = YES;
        CFIndex glyphs = 0;
        for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i) {
            CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
            CFRange range = CTRunGetStringRange(run);
            CFIndex count = CTRunGetGlyphCount(run);
            const CFIndex *indices = CTRunGetStringIndicesPtr(run);
            glyphs += count;
            if (range.location < 0 || range.location + range.length > 5)
                inside = NO;
            for (CFIndex j = 0; j < count; ++j)
                if (indices[j] < range.location || indices[j] >= range.location + range.length)
                    inside = NO;
        }
        expect(inside, "run string indices stay inside the run string range");
        expect(CTLineGetGlyphCount(line) == glyphs, "line glyph count sums the runs");
        expect(CTLineGetStringRange(line).location == 0 && CTLineGetStringRange(line).length == 5,
               "line string range covers the string");

        // Range arguments: an over-long range is clamped to the glyph count.
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
        CFIndex count = CTRunGetGlyphCount(run);
        CGPoint positions[8];
        for (int i = 0; i < 8; ++i)
            positions[i] = CGPointMake(-1, -1);
        CTRunGetPositions(run, CFRangeMake(0, count + 100), positions);
        expect(positions[count].x == -1, "over-long range does not write past the glyph count");

        // The width equals the sum of the run widths.
        double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
        double sum = 0;
        for (CFIndex i = 0; i < CFArrayGetCount(runs); ++i)
            sum += CTRunGetTypographicBounds((CTRunRef)CFArrayGetValueAtIndex(runs, i),
                                             CFRangeMake(0, 0), NULL, NULL, NULL);
        expect(width > 0 && width - sum < 0.001 && sum - width < 0.001, "line width equals run widths");

        CFRelease(line);
        CFRelease(text);
        CFRelease(first);
        CFRelease(second);
    }
    return failures ? 1 : 0;
}
