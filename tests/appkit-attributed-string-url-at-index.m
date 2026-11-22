// https://developer.apple.com/documentation/foundation/nsattributedstring/url(at:effectiverange:)
// Returns the URL stored in the link attribute at an index, and the range the link covers. The link
// attribute holds an NSURL or an NSString (https://developer.apple.com/documentation/foundation/nsattributedstring/key/link).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

int main(void)
{
    @autoreleasepool {
        NSURL *first = [NSURL URLWithString: @"https://example.invalid/first"];
        NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString: @"see first and second here"] autorelease];
        [text addAttribute: NSLinkAttributeName value: first range: NSMakeRange(4, 5)];
        [text addAttribute: NSLinkAttributeName value: @"https://example.invalid/second" range: NSMakeRange(14, 6)];
        // A run inside a link that differs in another attribute does not split the link's range.
        [text addAttribute: NSForegroundColorAttributeName value: [NSColor redColor] range: NSMakeRange(6, 2)];

        NSRange range = NSMakeRange(99, 99);
        NSURL *url = [text URLAtIndex: 4 effectiveRange: &range];
        CHECK([url isEqual: first]);
        CHECK(NSEqualRanges(range, NSMakeRange(4, 5)));

        url = [text URLAtIndex: 7 effectiveRange: &range];
        CHECK([url isEqual: first]);
        CHECK(NSEqualRanges(range, NSMakeRange(4, 5)));

        // A link given as a string is returned as a URL.
        url = [text URLAtIndex: 16 effectiveRange: &range];
        CHECK([[url absoluteString] isEqual: @"https://example.invalid/second"]);
        CHECK(NSEqualRanges(range, NSMakeRange(14, 6)));

        // The range pointer is optional.
        CHECK([[text URLAtIndex: 4 effectiveRange: NULL] isEqual: first]);

        // No link: nil, with the range of the text around the index that has no link.
        range = NSMakeRange(99, 99);
        CHECK([text URLAtIndex: 0 effectiveRange: &range] == nil);
        CHECK(NSEqualRanges(range, NSMakeRange(0, 4)));
        CHECK([text URLAtIndex: 10 effectiveRange: &range] == nil);
        CHECK(NSEqualRanges(range, NSMakeRange(9, 5)));
        CHECK([text URLAtIndex: 10 effectiveRange: NULL] == nil);
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
