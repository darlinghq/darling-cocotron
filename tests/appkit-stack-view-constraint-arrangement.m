// Copyright (C) 2026 Lubos Dolezel
//
// NSStackView arranges its arranged subviews with constraints: an arranged subview that has constraints of
// its own (a minimum width, a fixed size) takes part in the layout instead of making the constraint
// engine give up, and spacing, alignment, distribution, hugging priority and gravity areas are honoured.
// Expected frames were observed on macOS 26.7.3 and 10.14.4 (x86_64 and i386); the program passes on both.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

@interface FixedBox : NSView {
    NSSize size;
}
- (instancetype)initWithSize:(NSSize)s;
@end
@implementation FixedBox
- (instancetype)initWithSize:(NSSize)s
{
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 1, 1)]))
        size = s;
    return self;
}
- (NSSize)intrinsicContentSize { return size; }
@end

// A view with no intrinsic width, as a search field has
@interface FlexBox : NSView
@end
@implementation FlexBox
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 20); }
@end

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSView *box(CGFloat w, CGFloat h) { return [[[FixedBox alloc] initWithSize:NSMakeSize(w, h)] autorelease]; }

static NSStackView *makeStack(NSArray *views, NSStackViewDistribution distribution, NSUserInterfaceLayoutOrientation orientation,
                              CGFloat width, CGFloat height, NSWindow **window)
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    [stack setDistribution:distribution];
    [stack setOrientation:orientation];
    NSView *host = [[[NSView alloc] init] autorelease];
    [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [host addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [[stack topAnchor] constraintEqualToAnchor:[host topAnchor]],
        [[stack leadingAnchor] constraintEqualToAnchor:[host leadingAnchor]],
        [[stack trailingAnchor] constraintEqualToAnchor:[host trailingAnchor]],
        [[stack bottomAnchor] constraintEqualToAnchor:[host bottomAnchor]]
    ]];
    *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                          styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [*window setContentView:host];
    [*window layoutIfNeeded];
    return stack;
}

// Views' frames x, y, width, height one after another; tolerance covers the pixel rounding of macOS
static void expectFrames(NSStackView *stack, const CGFloat *values, NSString *what)
{
    NSArray *views = [stack arrangedSubviews];
    for (NSUInteger i = 0; i < [views count]; i++)
    {
        NSRect frame = [[views objectAtIndex:i] frame];
        const CGFloat *want = values + 4 * i;
        BOOL ok = fabs(NSMinX(frame) - want[0]) < 1 && fabs(NSMinY(frame) - want[1]) < 1 &&
                  fabs(NSWidth(frame) - want[2]) < 1 && fabs(NSHeight(frame) - want[3]) < 1;
        expect(ok, [NSString stringWithFormat:@"%@, view %lu: got %@, want {{%g, %g}, {%g, %g}}", what, (unsigned long)i,
                                              NSStringFromRect(frame), want[0], want[1], want[2], want[3]]);
    }
}

#define THREE (@[ box(40, 20), box(30, 25), box(20, 10) ])

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSWindow *window;
        NSStackView *stack;

        // An arranged subview with its own minimum width: the layout is solved, the view gets at least that width
        FlexBox *flex = [[[FlexBox alloc] init] autorelease];
        [[flex widthAnchor] constraintGreaterThanOrEqualToConstant:220].active = YES;
        stack = makeStack(@[ box(51, 18), flex ], NSStackViewDistributionGravityAreas, NSUserInterfaceLayoutOrientationHorizontal, 1000, 38, &window);
        expect(fabs(NSWidth([stack frame]) - 1000) < 0.5, @"the stack view fills the host");
        expect(NSWidth([flex frame]) >= 220 - 0.5, @"a minimum width of an arranged subview is honoured");
        expect(fabs(NSMinX([flex frame]) - 59) < 1 && fabs(NSWidth([flex frame]) - 941) < 1,
               [NSString stringWithFormat:@"the view without an intrinsic width takes the rest: %@", NSStringFromRect([flex frame])]);
        expect(![flex translatesAutoresizingMaskIntoConstraints], @"an arranged subview is laid out by constraints");
        expect([[stack constraints] count] > 0, @"the stack view holds the arranging constraints");

        // A constraint added to an arranged subview after it was added to the stack view
        stack = makeStack(@[ box(40, 20), [[[FlexBox alloc] init] autorelease] ], NSStackViewDistributionFill,
                          NSUserInterfaceLayoutOrientationHorizontal, 300, 50, &window);
        {
            NSView *second = [[stack arrangedSubviews] objectAtIndex:1];
            [[second widthAnchor] constraintEqualToConstant:90].active = YES;
            [window layoutIfNeeded];
            expect(fabs(NSWidth([second frame]) - 90) < 0.5, @"a fixed width of an arranged subview is honoured");
        }

        // Frames observed on the Macs (views with an intrinsic size; origin at the bottom left)
        stack = makeStack(THREE, NSStackViewDistributionGravityAreas, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 40, 20, 48, 13, 30, 25, 86, 20, 20, 10}, @"gravity areas, all leading");
        stack = makeStack(THREE, NSStackViewDistributionFill, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 234, 20, 242, 13, 30, 25, 280, 20, 20, 10}, @"fill");
        stack = makeStack(THREE, NSStackViewDistributionFillEqually, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 95, 20, 103, 13, 94, 25, 205, 20, 95, 10}, @"fill equally");
        stack = makeStack(THREE, NSStackViewDistributionFillProportionally, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 126, 20, 134, 13, 95, 25, 237, 20, 63, 10}, @"fill proportionally");
        stack = makeStack(THREE, NSStackViewDistributionFill, 1, 50, 300, &window);
        expectFrames(stack, (CGFloat[]){5, 51, 40, 249, 10, 18, 30, 25, 15, 0, 20, 10}, @"vertical fill, first view at the top");

        // Content hugging priority decides which view takes the spare room
        NSArray *views = THREE;
        [[views objectAtIndex:0] setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [[views objectAtIndex:1] setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
        stack = makeStack(views, NSStackViewDistributionFill, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 40, 20, 48, 13, 224, 25, 280, 20, 20, 10}, @"fill, middle view hugs least");
        views = THREE;
        [[views objectAtIndex:2] setContentHuggingPriority:100 forOrientation:NSLayoutConstraintOrientationHorizontal];
        stack = makeStack(views, NSStackViewDistributionFill, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 40, 20, 48, 13, 30, 25, 86, 20, 214, 10}, @"fill, last view hugs least");

        // Gravity areas: leading, center and trailing
        stack = [NSStackView stackViewWithViews:@[]];
        [stack addView:box(40, 20) inGravity:NSStackViewGravityLeading];
        [stack addView:box(30, 25) inGravity:NSStackViewGravityCenter];
        [stack addView:box(20, 10) inGravity:NSStackViewGravityTrailing];
        {
            NSView *host = [[[NSView alloc] init] autorelease];
            [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
            [host addSubview:stack];
            [NSLayoutConstraint activateConstraints:@[
                [[stack topAnchor] constraintEqualToAnchor:[host topAnchor]],
                [[stack leadingAnchor] constraintEqualToAnchor:[host leadingAnchor]],
                [[stack trailingAnchor] constraintEqualToAnchor:[host trailingAnchor]],
                [[stack bottomAnchor] constraintEqualToAnchor:[host bottomAnchor]]
            ]];
            window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 50) styleMask:NSWindowStyleMaskTitled
                                                   backing:NSBackingStoreBuffered defer:NO];
            [window setContentView:host];
            [window layoutIfNeeded];
            expectFrames(stack, (CGFloat[]){0, 15, 40, 20, 135, 13, 30, 25, 280, 20, 20, 10}, @"gravity areas, leading center trailing");
        }

        // Spacing, custom spacing, alignment
        views = THREE;
        stack = makeStack(views, NSStackViewDistributionFill, 0, 300, 50, &window);
        [stack setCustomSpacing:30 afterView:[views objectAtIndex:0]];
        [window layoutIfNeeded];
        expectFrames(stack, (CGFloat[]){0, 15, 212, 20, 242, 13, 30, 25, 280, 20, 20, 10}, @"custom spacing after the first view");
        stack = makeStack(THREE, NSStackViewDistributionFill, 0, 300, 50, &window);
        [stack setSpacing:20];
        [window layoutIfNeeded];
        expectFrames(stack, (CGFloat[]){0, 15, 210, 20, 230, 13, 30, 25, 280, 20, 20, 10}, @"spacing 20");
        stack = makeStack(THREE, NSStackViewDistributionFill, 0, 300, 50, &window);
        [stack setAlignment:NSLayoutAttributeTop];
        [window layoutIfNeeded];
        expectFrames(stack, (CGFloat[]){0, 30, 234, 20, 242, 25, 30, 25, 280, 40, 20, 10}, @"horizontal, aligned at the top");
        [stack setAlignment:NSLayoutAttributeBottom];
        [window layoutIfNeeded];
        expectFrames(stack, (CGFloat[]){0, 0, 234, 20, 242, 0, 30, 25, 280, 0, 20, 10}, @"horizontal, aligned at the bottom");
        stack = makeStack(THREE, NSStackViewDistributionFill, 1, 80, 300, &window);
        [stack setAlignment:NSLayoutAttributeLeading];
        [window layoutIfNeeded];
        expectFrames(stack, (CGFloat[]){0, 51, 40, 249, 0, 18, 30, 25, 0, 0, 20, 10}, @"vertical, aligned leading");
        [stack setAlignment:NSLayoutAttributeTrailing];
        [window layoutIfNeeded];
        expectFrames(stack, (CGFloat[]){40, 51, 40, 249, 50, 18, 30, 25, 60, 0, 20, 10}, @"vertical, aligned trailing");

        // An own width constraint of an arranged subview in a stack that distributes by gravity areas
        views = THREE;
        [[[views objectAtIndex:0] widthAnchor] constraintEqualToConstant:90].active = YES;
        [[[views objectAtIndex:2] heightAnchor] constraintEqualToConstant:40].active = YES;
        stack = makeStack(views, NSStackViewDistributionGravityAreas, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 90, 20, 98, 13, 30, 25, 136, 5, 20, 40}, @"own width and height constraints");
        views = THREE;
        [[[views objectAtIndex:1] widthAnchor] constraintGreaterThanOrEqualToConstant:200].active = YES;
        stack = makeStack(views, NSStackViewDistributionGravityAreas, 0, 300, 50, &window);
        expectFrames(stack, (CGFloat[]){0, 15, 40, 20, 48, 13, 200, 25, 256, 20, 20, 10}, @"own minimum width");

        [window close];
    }
    printf("PASS\n");
    return 0;
}
