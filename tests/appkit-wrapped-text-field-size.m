// Copyright (C) 2026 Lubos Dolezel
// A word-wrapping text field reports the height of its wrapped lines, for the width it is given:
// through -[NSCell cellSizeForBounds:] and through -intrinsicContentSize with a
// preferredMaxLayoutWidth. Reference values were observed on macOS 10.14.4 and 26.7.3 (text of
// three lines of 17 points offered 311 points: cell size 299.8 x 51, intrinsic height 51); the
// checks here are relative, so a different font is fine.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *text = @"MacPaw updated its Privacy Policy and Terms of Service to give you more "
                          "transparency into how we collect, use, and disclose information.";
        NSTextField *f = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 311, 48)] autorelease];
        f.bezeled = NO; f.drawsBackground = NO; f.editable = NO; f.selectable = NO;
        f.font = [NSFont systemFontOfSize: 13];
        f.stringValue = text;
        f.lineBreakMode = NSLineBreakByWordWrapping;

        NSSize one = [[f cell] cellSize];
        NSSize wide = [[f cell] cellSizeForBounds: NSMakeRect(0, 0, one.width + 100, CGFLOAT_MAX)];
        NSSize narrow = [[f cell] cellSizeForBounds: NSMakeRect(0, 0, 311, CGFLOAT_MAX)];
        NSSize capped = [[f cell] cellSizeForBounds: NSMakeRect(0, 0, 311, 20)];

        CHECK(wide.height < one.height + 4);                  // fits on one line
        CHECK(narrow.width > 200 && narrow.width <= 311);     // the widest line, within the width
        CHECK(narrow.height > one.height * 2);                // several lines
        CHECK(capped.width == narrow.width && capped.height == 20);  // never more than the bounds offer

        // Without wrapping the height stays that of one line.
        NSTextField *clip = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 311, 48)] autorelease];
        clip.bezeled = NO; clip.font = f.font; clip.stringValue = text;
        clip.lineBreakMode = NSLineBreakByClipping;
        CHECK([[clip cell] cellSizeForBounds: NSMakeRect(0, 0, 311, CGFLOAT_MAX)].height <= one.height);

        // Intrinsic size: no preferred width keeps the single line; with one, the wrapped lines.
        CHECK(f.intrinsicContentSize.height <= one.height);
        f.preferredMaxLayoutWidth = 311;
        NSSize intrinsic = f.intrinsicContentSize;
        CHECK(intrinsic.height == narrow.height);
        CHECK(intrinsic.width <= 311);

        f.preferredMaxLayoutWidth = 150;
        CHECK(f.intrinsicContentSize.height > intrinsic.height);
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
