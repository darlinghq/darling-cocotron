/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTextContainer's default line fragment padding is 5 points, the typesetter
 * applies it on the left of a line (the text starts at x = 5, as the bounding rect of a laid out string shows on macOS), and the text container inset of an
 * NSTextView reduces the container size it tracks. No window server needed.
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
        NSTextContainer *container =
                [[NSTextContainer alloc] initWithContainerSize: NSMakeSize(100, 100)];
        expect([container lineFragmentPadding] == 5.0, "default padding is 5");
        [container setLineFragmentPadding: 0];
        expect([container lineFragmentPadding] == 0, "padding can be changed");

        NSTextView *view = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        [view setString: @"Hello"];
        NSLayoutManager *manager = [view layoutManager];
        NSTextContainer *own = [view textContainer];
        expect([own lineFragmentPadding] == 5.0, "text view container padding is 5");

        [manager ensureLayoutForTextContainer: own];
        NSRect box = [manager boundingRectForGlyphRange: NSMakeRange(0, 5) inTextContainer: own];
        expect(box.origin.x == 5.0, "the text starts after the left padding");
        NSRect fragment = [manager lineFragmentRectForGlyphAtIndex: 0 effectiveRange: NULL];
        expect(fragment.size.width <= [own containerSize].width,
               "the fragment rect stays inside the container");

        [view setTextContainerInset: NSMakeSize(10, 10)];
        expect([own containerSize].width == 180.0,
               "container width tracks the view width minus the inset");
    }
    if (failures)
        return 1;
    puts("text container padding: PASS");
    return 0;
}
