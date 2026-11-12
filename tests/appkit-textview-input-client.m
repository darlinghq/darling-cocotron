/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextInputClient conformance of NSTextView, layout manager settings,
 * idempotent layout manager registration, scroll view knob style and
 * -sendActionOn:. No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void)
{
    @autoreleasepool {
        NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        [view setString: @"hello world"];

        expect([view conformsToProtocol: @protocol(NSTextInputClient)], "NSTextView is an NSTextInputClient");
        expect(![view hasMarkedText], "no marked text");
        expect([view markedRange].location == NSNotFound, "the marked range is not found");
        expect([view validAttributesForMarkedText] != nil, "valid marked text attributes are an array");

        NSRange actual;
        NSAttributedString *part = [view attributedSubstringForProposedRange: NSMakeRange(6, 100) actualRange: &actual];
        expect([[part string] isEqualToString: @"world"] && NSEqualRanges(actual, NSMakeRange(6, 5)),
               "the proposed range is clipped to the text");
        expect([view attributedSubstringForProposedRange: NSMakeRange(50, 3) actualRange: &actual] == nil,
               "a range past the end gives nil");
        NSRect rect = [view firstRectForCharacterRange: NSMakeRange(0, 1) actualRange: NULL];
        expect(!isnan(rect.origin.x) && !isnan(rect.size.width), "firstRectForCharacterRange: answers a rect");

        NSDictionary *link = @{NSUnderlineStyleAttributeName: @1};
        [view setLinkTextAttributes: link];
        [view setMarkedTextAttributes: link];
        expect([[view linkTextAttributes] isEqualToDictionary: link], "link text attributes are stored");
        expect([[view markedTextAttributes] isEqualToDictionary: link], "marked text attributes are stored");
        [view setAcceptsGlyphInfo: YES];
        expect([view acceptsGlyphInfo], "acceptsGlyphInfo is stored");

        NSLayoutManager *manager = [view layoutManager];
        [manager setShowsControlCharacters: YES];
        [manager setShowsInvisibleCharacters: YES];
        [manager setUsesFontLeading: NO];
        [manager setBackgroundLayoutEnabled: YES];
        expect([manager showsControlCharacters] && [manager showsInvisibleCharacters] &&
                       ![manager usesFontLeading] && [manager backgroundLayoutEnabled],
               "layout manager settings are stored");
        [manager ensureLayoutForCharacterRange: NSMakeRange(0, 5)];
        [manager ensureLayoutForGlyphRange: NSMakeRange(0, 5)];

        NSTextStorage *storage = [view textStorage];
        NSUInteger count = [[storage layoutManagers] count];
        [storage addLayoutManager: manager];
        expect([[storage layoutManagers] count] == count, "adding a layout manager twice is a no-op");

        // Clamping a selection after the text shrank keeps the caret where it is allowed.
        [view setSelectedRange: NSMakeRange(8, 3)];
        [storage replaceCharactersInRange: NSMakeRange(2, 9) withString: @""];
        expect(NSMaxRange([view selectedRange]) <= [storage length], "the selection is clamped to the text");

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        [scroll setHasVerticalScroller: YES];
        [scroll setHasHorizontalScroller: YES];
        [scroll setScrollerKnobStyle: NSScrollerKnobStyleLight];
        expect([scroll scrollerKnobStyle] == NSScrollerKnobStyleLight, "the scroll view stores the knob style");
        expect([[scroll verticalScroller] knobStyle] == NSScrollerKnobStyleLight &&
                       [[scroll horizontalScroller] knobStyle] == NSScrollerKnobStyleLight,
               "the knob style reaches both scrollers");

        NSButtonCell *cell = [[NSButtonCell alloc] init];
        [cell sendActionOn: 5];
        expect([cell sendActionOn: 7] == 5, "sendActionOn: returns the previous mask");
    }
    if (failures)
        return 1;
    puts("textview input client: PASS");
    return 0;
}
