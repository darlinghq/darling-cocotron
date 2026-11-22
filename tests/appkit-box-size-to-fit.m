// https://developer.apple.com/documentation/appkit/nsbox/sizetofit()
// sizeToFit makes the content view just enclose its subviews (by the content view's own sizeToFit when it
// has one), then moves and resizes the box around the content view, wide enough to show its title.
// The space between the box's edges and its content view is read from the box before the call, so the
// checks do not depend on the exact insets.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

@interface FittingView : NSView
@end
@implementation FittingView
- (void) sizeToFit {
    [self setFrameSize: NSMakeSize(70, 40)];
}
@end

static NSBox *makeBox(NSString *title) {
    NSBox *box = [[[NSBox alloc] initWithFrame: NSMakeRect(30, 40, 300, 200)] autorelease];
    [box setTitle: title];
    return box;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Subviews of the content view: the content view ends up as large as their union.
        NSBox *box = makeBox(@"T");
        NSView *content = [box contentView];
        NSRect before = [content frame];
        CGFloat left = NSMinX(before), bottom = NSMinY(before);
        CGFloat right = NSWidth([box bounds]) - NSMaxX(before), top = NSHeight([box bounds]) - NSMaxY(before);
        NSView *a = [[[NSView alloc] initWithFrame: NSMakeRect(10, 10, 50, 20)] autorelease];
        NSView *b = [[[NSView alloc] initWithFrame: NSMakeRect(70, 40, 30, 30)] autorelease];
        [content addSubview: a];
        [content addSubview: b];
        [box sizeToFit];

        CHECK(NSEqualSizes([content frame].size, NSMakeSize(90, 60)));           // the union of a and b
        CHECK(NSEqualPoints([a frame].origin, NSMakePoint(0, 0)));               // the subviews keep their layout
        CHECK(NSEqualPoints([b frame].origin, NSMakePoint(60, 30)));             // relative to each other
        CHECK(NSEqualPoints([content frame].origin, NSMakePoint(left, bottom))); // and the content view its place
        CHECK([box frame].size.width == left + 90 + right);                      // the box wraps it, with the
        CHECK([box frame].size.height == bottom + 60 + top);                     // space it had around it
        CHECK(NSEqualPoints([box frame].origin, NSMakePoint(30, 40)));           // GUESS: its origin stays

        // A content view that answers sizeToFit sizes itself.
        NSBox *fitting = makeBox(@"T");
        FittingView *own = [[[FittingView alloc] initWithFrame: [[fitting contentView] frame]] autorelease];
        [fitting setContentView: own];
        before = [own frame];
        NSView *child = [[[NSView alloc] initWithFrame: NSMakeRect(5, 5, 500, 500)] autorelease];
        [own addSubview: child];
        [fitting sizeToFit];
        CHECK(NSEqualSizes([own frame].size, NSMakeSize(70, 40)));               // by its own method, not the union
        CHECK([fitting frame].size.width >= 70);

        // The width is enough for a long title.
        NSBox *titled = makeBox(@"A rather long box title that needs much more room than the content");
        NSView *small = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 20, 20)] autorelease];
        [[titled contentView] addSubview: small];
        CGFloat titleWidth = [[titled title] sizeWithAttributes: @{NSFontAttributeName: [titled titleFont]}].width;
        [titled sizeToFit];
        CHECK([titled frame].size.width >= titleWidth);
        CHECK(NSWidth([[titled contentView] frame]) > 20);                       // the content view fills the box

        // Without a title the title adds nothing.
        NSBox *plain = makeBox(@"");
        [[plain contentView] addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 20, 20)] autorelease]];
        [plain sizeToFit];
        CHECK([plain frame].size.width < 60);
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
