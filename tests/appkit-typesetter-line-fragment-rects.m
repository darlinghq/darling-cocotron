/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The typesetter reports line fragment rects that span the whole width of the
 * text container, and used rects that cover the line fragment padding on both
 * sides of the glyphs, which themselves start after the left padding. No
 * window server needed.
 */
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL near(CGFloat a, CGFloat b)
{
    return fabs(a - b) < 0.01;
}

static void checkSingleLine(CGFloat padding)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
    NSLayoutManager *manager = [view layoutManager];
    NSTextContainer *container = [view textContainer];
    [container setLineFragmentPadding: padding];
    [view setString: @"Hello"];
    [manager ensureLayoutForTextContainer: container];

    NSRect glyphs = [manager boundingRectForGlyphRange: NSMakeRange(0, 5)
                                       inTextContainer: container];
    NSRect fragment = [manager lineFragmentRectForGlyphAtIndex: 0 effectiveRange: NULL];
    NSRect used = [manager lineFragmentUsedRectForGlyphAtIndex: 0 effectiveRange: NULL];
    NSRect all = [manager usedRectForTextContainer: container];

    expect(near(glyphs.origin.x, padding), "the glyphs start after the left padding");
    expect(near([manager locationForGlyphAtIndex: 0].x, padding),
           "the glyph location is after the left padding");
    expect(near(fragment.origin.x, 0), "the fragment rect starts at the container edge");
    expect(near(fragment.size.width, [container containerSize].width),
           "the fragment rect is as wide as the container");
    expect(fragment.size.height > 0, "the fragment rect has a height");
    expect(near(used.origin.x, 0), "the used rect starts at the container edge");
    expect(near(used.size.width, glyphs.size.width + 2 * padding),
           "the used rect covers the padding on both sides");
    expect(near(all.origin.x, 0) && near(all.size.width, used.size.width),
           "the used rect of the container matches that of the line");
}

int main(void)
{
    @autoreleasepool {
        checkSingleLine(5.0);
        checkSingleLine(0.0);

        // Wrapped lines are all full width.
        NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 60, 200)];
        NSLayoutManager *manager = [view layoutManager];
        NSTextContainer *container = [view textContainer];
        [view setString: @"Hello wide world of wrapped text"];
        [manager ensureLayoutForTextContainer: container];
        NSUInteger glyphIndex = 0, lines = 0;
        while (glyphIndex < [manager numberOfGlyphs]) {
            NSRange range;
            NSRect fragment = [manager lineFragmentRectForGlyphAtIndex: glyphIndex
                                                        effectiveRange: &range];
            expect(near(fragment.origin.x, 0) &&
                           near(fragment.size.width, [container containerSize].width),
                   "every wrapped line spans the container");
            glyphIndex = NSMaxRange(range);
            lines++;
        }
        expect(lines > 1, "the text wraps");

        // A click in the left padding is before the first glyph, not at the end.
        NSTextView *hit = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        [hit setString: @"Hello"];
        NSLayoutManager *hitManager = [hit layoutManager];
        [hitManager ensureLayoutForTextContainer: [hit textContainer]];
        expect([hitManager glyphIndexForPoint: NSMakePoint(2, 5)
                              inTextContainer: [hit textContainer]] == 0,
               "a point in the left padding maps to the first glyph");
        expect([hitManager glyphIndexForPoint: NSMakePoint(150, 5)
                              inTextContainer: [hit textContainer]] >= 4,
               "a point after the text maps to the end of the line");
    }
    if (failures)
        return 1;
    puts("typesetter line fragment rects: PASS");
    return 0;
}
