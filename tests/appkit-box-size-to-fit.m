// https://developer.apple.com/documentation/appkit/nsbox/sizetofit()
// sizeToFit makes the content view just enclose its subviews (by the content view's own sizeToFit when it
// has one), then moves and resizes the box around the content view, wide enough to show its title.
// The space between the box's edges and its content view is read from the box before the call, so the
// checks do not depend on the exact insets. Pinned by black-box observation on macOS 26.7.3 and 10.14.4: the
// box moves by the offset of the subviews' union so the subviews stay in place on screen, a content view
// without subviews becomes empty and the box shrinks to its margins and title, and a long title makes the box
// as wide as the title cell plus 20 points.
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
        CHECK(NSEqualPoints([box frame].origin, NSMakePoint(40, 50)));           // it moves by the union's offset (10, 10)

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

        // A content view without subviews becomes empty and the box wraps the margins and the title.
        NSBox *empty = makeBox(@"T");
        NSView *emptyContent = [empty contentView];
        NSRect emptyBefore = [emptyContent frame];
        CGFloat emptyTop = NSHeight([empty bounds]) - NSMaxY(emptyBefore);
        [empty sizeToFit];
        CHECK(NSHeight([emptyContent frame]) == 0);
        CHECK([empty frame].size.height == NSMinY(emptyBefore) + emptyTop);
        CHECK(NSEqualPoints([empty frame].origin, NSMakePoint(30, 40)));        // no subviews: no offset

        // A subview with a negative origin moves the box and the other subviews by that offset.
        NSBox *negative = makeBox(@"T");
        NSView *p = [[[NSView alloc] initWithFrame: NSMakeRect(10, 10, 50, 20)] autorelease];
        NSView *q = [[[NSView alloc] initWithFrame: NSMakeRect(-20, -10, 10, 10)] autorelease];
        [[negative contentView] addSubview: p];
        [[negative contentView] addSubview: q];
        [negative sizeToFit];
        CHECK(NSEqualPoints([q frame].origin, NSMakePoint(0, 0)));
        CHECK(NSEqualPoints([p frame].origin, NSMakePoint(30, 20)));
        CHECK(NSEqualPoints([negative frame].origin, NSMakePoint(10, 30)));

        // sizeToFit twice changes nothing the second time.
        NSRect once = [box frame], contentOnce = [content frame];
        [box sizeToFit];
        CHECK(NSEqualRects([box frame], once));
        CHECK(NSEqualRects([content frame], contentOnce));
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
