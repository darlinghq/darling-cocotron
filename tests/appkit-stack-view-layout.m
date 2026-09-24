// NSStackView: documented defaults, gravity areas, orientation, alignment, distributions,
// custom spacing, edge insets and detaching hidden or not-visible views.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void expectRect(NSView *view, NSRect rect, NSString *what)
{
    NSRect frame = [view frame];
    expect(fabs(NSMinX(frame) - NSMinX(rect)) < 0.01 && fabs(NSMinY(frame) - NSMinY(rect)) < 0.01 &&
               fabs(NSWidth(frame) - NSWidth(rect)) < 0.01 && fabs(NSHeight(frame) - NSHeight(rect)) < 0.01,
           [NSString stringWithFormat:@"%@: got %@, want %@", what, NSStringFromRect(frame), NSStringFromRect(rect)]);
}

static NSView *box(CGFloat width, CGFloat height)
{
    return [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)] autorelease];
}

@interface Watcher : NSObject <NSStackViewDelegate>
@property (retain) NSArray *detached;
@property (retain) NSArray *reattached;
@end
@implementation Watcher
- (void)stackView:(NSStackView *)stackView willDetachViews:(NSArray *)views { self.detached = views; }
- (void)stackView:(NSStackView *)stackView didReattachViews:(NSArray *)views { self.reattached = views; }
@end

@interface Remover : NSObject <NSStackViewDelegate>
@end
@implementation Remover
- (void)stackView:(NSStackView *)stackView willDetachViews:(NSArray *)views
{
    for (NSView *view in views)
        [stackView removeView:view];
}
@end

@interface FlippedStackView : NSStackView
@end
@implementation FlippedStackView
- (BOOL)isFlipped { return YES; }
@end

int main(void)
{
    @autoreleasepool
    {
        NSStackView *stack = [[[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 300, 50)] autorelease];
        expect(stack.orientation == NSUserInterfaceLayoutOrientationHorizontal, @"default orientation");
        expect(stack.alignment == NSLayoutAttributeCenterY, @"default horizontal alignment");
        expect(stack.spacing == 8, @"default spacing");
        expect(stack.distribution == NSStackViewDistributionGravityAreas, @"default distribution");
        expect(stack.detachesHiddenViews, @"hidden views detach by default");

        // Gravity areas, horizontal.
        NSView *a = box(40, 20), *b = box(30, 20), *c = box(20, 10), *d = box(50, 20);
        [stack addView:a inGravity:NSStackViewGravityLeading];
        [stack addView:d inGravity:NSStackViewGravityTrailing];
        [stack addView:c inGravity:NSStackViewGravityCenter];
        [stack insertView:b atIndex:1 inGravity:NSStackViewGravityLeading];
        expect([stack.views isEqualToArray:(@[a, b, c, d])], @"views ordered by gravity");
        expect([[stack viewsInGravity:NSStackViewGravityLeading] isEqualToArray:(@[a, b])], @"leading views");
        expect([a superview] == stack && [d superview] == stack, @"added views become subviews");
        expectRect(a, NSMakeRect(0, 15, 40, 20), @"leading a");
        expectRect(b, NSMakeRect(48, 15, 30, 20), @"leading b after spacing");
        expectRect(c, NSMakeRect(140, 20, 20, 10), @"center c");
        expectRect(d, NSMakeRect(250, 15, 50, 20), @"trailing d");

        [stack setFrameSize:NSMakeSize(400, 50)];
        expectRect(d, NSMakeRect(350, 15, 50, 20), @"trailing d follows a resize");

        [stack setCustomSpacing:2 afterView:a];
        expect([stack customSpacingAfterView:a] == 2, @"custom spacing kept");
        expect([stack customSpacingAfterView:b] == NSStackViewSpacingUseDefault, @"no custom spacing");
        expectRect(b, NSMakeRect(42, 15, 30, 20), @"custom spacing after a");

        stack.alignment = NSLayoutAttributeTop;
        expectRect(c, NSMakeRect(190, 40, 20, 10), @"top alignment");
        stack.alignment = NSLayoutAttributeHeight;
        expectRect(c, NSMakeRect(190, 0, 20, 50), @"height alignment fills");
        stack.alignment = NSLayoutAttributeCenterY;

        // Detaching.
        Watcher *watcher = [[[Watcher alloc] init] autorelease];
        stack.delegate = watcher;
        [b setHidden:YES];
        expect([b superview] == nil, @"hidden view detached");
        expect([stack.detachedViews isEqualToArray:(@[b])], @"detachedViews");
        expect([stack.arrangedSubviews isEqualToArray:(@[a, c, d])], @"arrangedSubviews excludes detached");
        expect([stack.views isEqualToArray:(@[a, b, c, d])], @"views keeps detached");
        expect([watcher.detached isEqualToArray:(@[b])], @"delegate told about detaching");
        [b setHidden:NO];
        expect([b superview] == stack, @"shown view reattached");
        expect([watcher.reattached isEqualToArray:(@[b])], @"delegate told about reattaching");

        [stack setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible forView:c];
        expect([c superview] == nil, @"NotVisible detaches");
        [stack setVisibilityPriority:NSStackViewVisibilityPriorityMustHold forView:c];
        expect([c superview] == stack, @"MustHold reattaches");

        stack.detachesHiddenViews = NO;
        [b setHidden:YES];
        expect([b superview] == stack, @"hidden view stays when not detaching");
        [b setHidden:NO];

        [stack removeView:c];
        expect([c superview] == nil && ![stack.views containsObject:c], @"removeView");
        [d removeFromSuperview];
        expect(![stack.views containsObject:d], @"removeFromSuperview removes from the stack");
        stack.delegate = nil;

        // Vertical: top first, cross axis centered.
        NSStackView *column = [[[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 100, 200)] autorelease];
        column.orientation = NSUserInterfaceLayoutOrientationVertical;
        expect(column.alignment == NSLayoutAttributeCenterX, @"default vertical alignment");
        NSView *e = box(20, 30), *f = box(40, 10), *g = box(10, 10);
        [column addView:e inGravity:NSStackViewGravityTop];
        [column addView:f inGravity:NSStackViewGravityTop];
        [column addView:g inGravity:NSStackViewGravityBottom];
        expectRect(e, NSMakeRect(40, 170, 20, 30), @"vertical first view at the top");
        expectRect(f, NSMakeRect(30, 152, 40, 10), @"vertical second view below");
        expectRect(g, NSMakeRect(45, 0, 10, 10), @"bottom gravity");
        column.edgeInsets = NSEdgeInsetsMake(5, 6, 7, 8);
        expectRect(e, NSMakeRect(39, 165, 20, 30), @"edge insets");
        column.alignment = NSLayoutAttributeLeading;
        expectRect(f, NSMakeRect(6, 147, 40, 10), @"leading alignment");
        expect(NSEqualSizes([column intrinsicContentSize], NSMakeSize(40 + 14, 30 + 8 + 10 + 8 + 10 + 12)),
               @"intrinsic size of the packed views");

        // Distributions.
        NSView *p = box(50, 10), *q = box(50, 10);
        NSStackView *row = [NSStackView stackViewWithViews:@[p, q]];
        expect([[row viewsInGravity:NSStackViewGravityLeading] isEqualToArray:(@[p, q])],
               @"stackViewWithViews fills the leading area");
        row.spacing = 10;
        [row setFrame:NSMakeRect(0, 0, 200, 10)];
        row.distribution = NSStackViewDistributionFill;
        expectRect(q, NSMakeRect(60, 0, 140, 10), @"fill stretches the least hugging view");
        row.distribution = NSStackViewDistributionFillEqually;
        expectRect(p, NSMakeRect(0, 0, 95, 10), @"fill equally p");
        expectRect(q, NSMakeRect(105, 0, 95, 10), @"fill equally q");
        NSView *w = box(30, 10);
        [row addView:w inGravity:NSStackViewGravityLeading];
        row.distribution = NSStackViewDistributionFill;
        expectRect(q, NSMakeRect(60, 0, 50, 10), @"a formerly stretched view gets its own size back");
        expectRect(w, NSMakeRect(120, 0, 80, 10), @"fill stretches the new last view");
        [p removeFromSuperview];
        expectRect(q, NSMakeRect(0, 0, 50, 10), @"views close up after removeFromSuperview");

        NSView *r = box(20, 10), *s = box(20, 10), *t = box(20, 10);
        NSStackView *spaced = [NSStackView stackViewWithViews:@[r, s, t]];
        [spaced setFrame:NSMakeRect(0, 0, 200, 10)];
        spaced.distribution = NSStackViewDistributionEqualSpacing;
        expectRect(s, NSMakeRect(90, 0, 20, 10), @"equal spacing middle");
        expectRect(t, NSMakeRect(180, 0, 20, 10), @"equal spacing last");
        [s setFrameSize:NSMakeSize(40, 10)];
        spaced.distribution = NSStackViewDistributionEqualCentering;
        expectRect(s, NSMakeRect(80, 0, 40, 10), @"equal centering middle");

        [stack addArrangedSubview:c];
        expect([stack.arrangedSubviews lastObject] == c, @"addArrangedSubview appends");
        [stack insertArrangedSubview:d atIndex:0];
        expect([stack.arrangedSubviews objectAtIndex:0] == d, @"insertArrangedSubview at 0");
        [stack removeArrangedSubview:d];
        expect(![stack.arrangedSubviews containsObject:d] && [d superview] == stack,
               @"removeArrangedSubview keeps the subview");

        NSStackView *turned = [[[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
        turned.alignment = NSLayoutAttributeLeading;
        turned.orientation = NSUserInterfaceLayoutOrientationVertical;
        expect(turned.alignment == NSLayoutAttributeLeading, @"orientation change keeps an explicit alignment");

        FlippedStackView *flipped = [[[FlippedStackView alloc] initWithFrame:NSMakeRect(0, 0, 100, 200)] autorelease];
        flipped.orientation = NSUserInterfaceLayoutOrientationVertical;
        NSView *top = box(20, 30), *bottom = box(10, 10);
        [flipped addView:top inGravity:NSStackViewGravityTop];
        [flipped addView:bottom inGravity:NSStackViewGravityBottom];
        expectRect(top, NSMakeRect(40, 0, 20, 30), @"flipped: top view at y 0");
        expectRect(bottom, NSMakeRect(45, 190, 10, 10), @"flipped: bottom view at the bottom");

        Remover *remover = [[[Remover alloc] init] autorelease];
        flipped.delegate = remover;
        [top setHidden:YES];
        expect(![flipped.views containsObject:top] && [top superview] == nil,
               @"a delegate may remove views it is told are detaching");
        flipped.delegate = nil;

        NSLog(@"PASS: NSStackView layout");
    }
    return 0;
}
