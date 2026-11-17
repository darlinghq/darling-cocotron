/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSLayoutManager: the bounding rect of a single glyph covers that glyph, the
// rects of consecutive glyphs follow each other, and glyphIndexForPoint:
// answers with the glyph under the point, with the fraction of the glyph's
// width the point is at, at every position inside the glyph's rect, also for
// narrow glyphs. Expectations come from observing macOS 26.7.3 and 10.14.4.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSLayoutManager *makeManager(NSString *string, NSFont *font, NSTextContainer **containerOut) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString: string
                                                        attributes: [NSDictionary dictionaryWithObject: font
                                                                                                forKey: NSFontAttributeName]];
    NSLayoutManager *manager = [[NSLayoutManager alloc] init];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize: NSMakeSize(1000, 1000)] autorelease];

    [manager addTextContainer: container];
    [storage addLayoutManager: manager];
    [storage autorelease]; // the layout manager does not retain its text storage
    [manager ensureLayoutForTextContainer: container];
    *containerOut = container;
    return [manager autorelease];
}

static void testSingleGlyphRects(void) {
    NSString *string = @"go link iilli here";
    NSTextContainer *container;
    NSLayoutManager *manager = makeManager(string, [NSFont systemFontOfSize: 12], &container);
    NSUInteger count = [string length];
    NSRect previous = NSZeroRect;

    for (NSUInteger i = 0; i < count; i++) {
        NSRect rect = [manager boundingRectForGlyphRange: NSMakeRange(i, 1) inTextContainer: container];
        char what[160];

        snprintf(what, sizeof what, "glyph %lu has a rect with a width", (unsigned long) i);
        expect(rect.size.width > 0, what);
        if (i > 0) {
            snprintf(what, sizeof what, "the rect of glyph %lu starts where the rect of glyph %lu ends", (unsigned long) i,
                     (unsigned long) i - 1);
            expect(fabs(NSMinX(rect) - NSMaxX(previous)) < 1.0, what);
        }
        previous = rect;
    }

    // the rect of a range is as wide as the rects of its glyphs
    NSRect word = [manager boundingRectForGlyphRange: NSMakeRange(3, 4) inTextContainer: container];
    NSRect first = [manager boundingRectForGlyphRange: NSMakeRange(3, 1) inTextContainer: container];
    NSRect last = [manager boundingRectForGlyphRange: NSMakeRange(6, 1) inTextContainer: container];
    expect(fabs(NSMinX(word) - NSMinX(first)) < 1.0 && fabs(NSMaxX(word) - NSMaxX(last)) < 1.0,
           "the rect of a range spans from its first glyph to its last");
}

static void testHitTestAgreesWithRects(void) {
    NSString *string = @"go link iilli here";
    NSTextContainer *container;
    NSLayoutManager *manager = makeManager(string, [NSFont systemFontOfSize: 12], &container);

    for (NSUInteger i = 0; i < [string length]; i++) {
        NSRect rect = [manager boundingRectForGlyphRange: NSMakeRange(i, 1) inTextContainer: container];
        double fractions[] = {0.1, 0.25, 0.5, 0.75, 0.9};

        for (int f = 0; f < 5; f++) {
            NSPoint point = NSMakePoint(NSMinX(rect) + rect.size.width * fractions[f], NSMidY(rect));
            CGFloat fraction = -1;
            NSUInteger index = [manager glyphIndexForPoint: point inTextContainer: container fractionOfDistanceThroughGlyph: &fraction];
            char what[160];

            snprintf(what, sizeof what, "a point %.0f%% into the rect of glyph %lu is over glyph %lu", fractions[f] * 100,
                     (unsigned long) i, (unsigned long) i);
            expect(index == i, what);
            snprintf(what, sizeof what, "and is %.0f%% through it (glyph %lu)", fractions[f] * 100, (unsigned long) i);
            expect(fabs(fraction - fractions[f]) < 0.1, what);
            expect([manager fractionOfDistanceThroughGlyphForPoint: point inTextContainer: container] == fraction,
                   "fractionOfDistanceThroughGlyphForPoint: answers the same fraction");
        }
    }
}

// glyph and character indexes are the same here (one glyph per character)
static void testTextViewCharacterIndex(void) {
    NSTextView *view = [[[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 400, 100)] autorelease];
    NSLayoutManager *manager = [view layoutManager];

    [view setFont: [NSFont systemFontOfSize: 12]];
    [view setString: @"go link here"];
    [manager ensureLayoutForTextContainer: [view textContainer]];
    for (NSUInteger i = 0; i < 12; i++) {
        NSRect rect = [manager boundingRectForGlyphRange: NSMakeRange(i, 1) inTextContainer: [view textContainer]];
        NSUInteger index = [manager characterIndexForGlyphAtIndex: [manager glyphIndexForPoint: NSMakePoint(NSMidX(rect), NSMidY(rect))
                                                                                  inTextContainer: [view textContainer]]];
        char what[96];

        snprintf(what, sizeof what, "the middle of the rect of character %lu is over that character", (unsigned long) i);
        expect(index == i, what);
    }
}

int main(void) {
    @autoreleasepool {
        testSingleGlyphRects();
        testHitTestAgreesWithRects();
        testTextViewCharacterIndex();
    }
    if (failures != 0)
        return 1;
    puts("layout manager glyph hit test: PASS");
    return 0;
}
