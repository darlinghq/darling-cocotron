// CFLAGS: -framework Foundation -framework AppKit
//
// The key view loop that -[NSWindow recalculateKeyViewLoop] builds is based on
// the geometric order of the views in the window: from the top of the window to
// the bottom, and from left to right within a row; views whose vertical extents overlap are in the same row
// (a left view a little lower than a right one is still first, views that only touch are in different
// rows), and the subviews of a container are visited right after the container. Observed on macOS 26.7.3 and
// 10.14.4 (black-box, tier 2, mac-probes p794c). The loop is closed, so the
// last view is followed by the first. The loop is recalculated at once, when
// -recalculateKeyViewLoop is called. A view flush with the top left corner of
// the content view is first in the loop, not skipped.
//
// The row and container cases below were observed on both Macs.
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void expect(BOOL ok, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    printf("%s ", ok ? "PASS" : "FAIL");
    vprintf(format, ap);
    printf("\n");
    va_end(ap);
    if (!ok)
        failures++;
}

static NSTextField *addField(NSWindow *window, CGFloat x, CGFloat y)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(x, y, 80, 22)] autorelease];
    [[window contentView] addSubview: field];
    return field;
}

static NSWindow *makeWindow(void)
{
    return [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 300)
                                       styleMask: NSWindowStyleMaskTitled
                                         backing: NSBackingStoreBuffered
                                           defer: YES];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    // One column: the content view is not flipped, a larger y is higher.
    NSWindow *window = makeWindow();
    NSTextField *top = addField(window, 10, 200), *middle = addField(window, 10, 150), *bottom = addField(window, 10, 100);
    [window recalculateKeyViewLoop];
    expect([top nextValidKeyView] == middle, "column: top is followed by middle");
    expect([middle nextValidKeyView] == bottom, "column: middle is followed by bottom");
    expect([bottom nextValidKeyView] == top, "column: bottom is followed by top");
    expect([top previousValidKeyView] == bottom, "column: top is preceded by bottom");

    // A row of two above a field at the left, a field at the right below that.
    window = makeWindow();
    NSTextField *rightUpper = addField(window, 150, 200), *leftUpper = addField(window, 10, 200);
    NSTextField *rightLower = addField(window, 150, 100), *leftLower = addField(window, 10, 100);
    [window recalculateKeyViewLoop];
    expect([leftUpper nextValidKeyView] == rightUpper, "grid: upper left is followed by upper right");
    expect([rightUpper nextValidKeyView] == leftLower, "grid: upper right is followed by lower left");
    expect([leftLower nextValidKeyView] == rightLower, "grid: lower left is followed by lower right");
    expect([rightLower nextValidKeyView] == leftUpper, "grid: lower right is followed by upper left");

    // A field at the top left corner of the content view, above a lower one.
    window = makeWindow();
    NSTextField *lower = addField(window, 10, 100);
    NSRect contentBounds = [[window contentView] bounds];
    NSTextField *corner = addField(window, 0, NSMaxY(contentBounds) - 22);
    [window recalculateKeyViewLoop];
    expect([[window contentView] nextValidKeyView] == corner, "corner: the loop starts with the field at the content view's top left");
    expect([corner nextValidKeyView] == lower, "corner: the corner field is followed by the lower one");
    expect([lower nextValidKeyView] == corner, "corner: the lower field is followed by the corner field");

    // Overlapping extents make a row: the left field, 20 points lower than the right one (22 points tall), is
    // first; with extents that only touch it is second.
    window = makeWindow();
    NSTextField *rightHigh = addField(window, 150, 200), *leftOverlap = addField(window, 10, 180), *below = addField(window, 10, 100);
    [window recalculateKeyViewLoop];
    expect([leftOverlap nextValidKeyView] == rightHigh && [rightHigh nextValidKeyView] == below,
           "row: a left field overlapping the right one's extent comes first");
    window = makeWindow();
    rightHigh = addField(window, 150, 200);
    NSTextField *leftTouching = addField(window, 10, 178);
    below = addField(window, 10, 100);
    [window recalculateKeyViewLoop];
    expect([rightHigh nextValidKeyView] == leftTouching && [leftTouching nextValidKeyView] == below,
           "row: a left field whose extent only touches the right one's comes after it");

    // A row is made of the views overlapping the highest one: C overlaps only B, so it is a row of its own.
    window = makeWindow();
    NSTextField *chainA = addField(window, 210, 200), *chainB = addField(window, 110, 180), *chainC = addField(window, 10, 160);
    [window recalculateKeyViewLoop];
    expect([chainB nextValidKeyView] == chainA && [chainA nextValidKeyView] == chainC,
           "chain: the row of A and B (B first), then C");

    // A container is followed by its own subviews before the views after it in reading order.
    window = makeWindow();
    NSView *container = [[[NSView alloc] initWithFrame: NSMakeRect(10, 100, 120, 180)] autorelease];
    [[window contentView] addSubview: container];
    NSTextField *innerHigh = [[[NSTextField alloc] initWithFrame: NSMakeRect(5, 120, 80, 22)] autorelease];
    NSTextField *innerLow = [[[NSTextField alloc] initWithFrame: NSMakeRect(5, 20, 80, 22)] autorelease];
    [container addSubview: innerHigh];
    [container addSubview: innerLow];
    NSTextField *outer = addField(window, 200, 170);
    [window recalculateKeyViewLoop];
    expect([innerHigh nextValidKeyView] == innerLow && [innerLow nextValidKeyView] == outer && [outer nextValidKeyView] == innerHigh,
           "container: its subviews come before the field to its right, whatever their height");

    if (failures == 0)
        puts("ALL PASSED");
    else
        printf("FAILED %d\n", failures);
    [pool drain];
    return failures != 0;
}
