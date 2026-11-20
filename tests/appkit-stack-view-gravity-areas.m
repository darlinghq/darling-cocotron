// Copyright (C) 2026 Lubos Dolezel
//
// NSStackView gravity areas and what goes with them: the layout of the leading, center and
// trailing areas (spacing, custom spacing, hugging below the default stretching a view, the
// distributions), the fitting size, hidden views that are not detached by default, views detached
// for lack of room by their visibility priority, and a nib that holds views in gravity areas.
// Expected frames were observed on macOS 10.14.4 (black-box, i386); 26.7.3 agrees on all of them
// but the QUIRK noted at test_quirk_detaches_hidden_views_default.
//
// Usage: appkit-stack-view-gravity-areas [<tests/fixtures/nibarchive directory>]
// The compiled nib is read on Darling and on macOS 26.7.3 only; macOS 10.14.4 does not instantiate
// the nibs ibtool 26.5 compiles.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...)                                           \
    do {                                                           \
        if (!(cond)) {                                             \
            printf("FAIL line %d: ", __LINE__);                    \
            printf(__VA_ARGS__);                                   \
            printf("\n");                                          \
            failures++;                                            \
        }                                                          \
    } while (0)

// A view with an intrinsic size and nothing else
@interface Box : NSView {
    NSSize _size;
}
- (instancetype)initWithName:(NSString *)name width:(CGFloat)w height:(CGFloat)h;
@end

@implementation Box
- (instancetype)initWithName:(NSString *)name width:(CGFloat)w height:(CGFloat)h
{
    if ((self = [super initWithFrame:NSMakeRect(0, 0, w, h)])) {
        _size = NSMakeSize(w, h);
        [self setIdentifier:name];
    }
    return self;
}
- (NSSize)intrinsicContentSize { return _size; }
@end

@interface Watcher : NSObject <NSStackViewDelegate> {
    NSMutableArray *_detached, *_reattached;
}
@property (readonly) NSMutableArray *detached, *reattached;
@end
@implementation Watcher
@synthesize detached = _detached, reattached = _reattached;
- (instancetype)init
{
    if ((self = [super init])) {
        _detached = [[NSMutableArray alloc] init];
        _reattached = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)stackView:(NSStackView *)stackView willDetachViews:(NSArray *)views { [_detached addObjectsFromArray:views]; }
- (void)stackView:(NSStackView *)stackView didReattachViews:(NSArray *)views { [_reattached addObjectsFromArray:views]; }
@end

static NSView *host;
static const NSLayoutConstraintOrientation H = NSLayoutConstraintOrientationHorizontal;

static Box *box(NSString *name, CGFloat w, CGFloat h) { return [[[Box alloc] initWithName:name width:w height:h] autorelease]; }

// A stack view in a window's content view, placed by its frame ...
static NSStackView *framedStack(CGFloat w, CGFloat h, NSUserInterfaceLayoutOrientation orientation)
{
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 900)
                                                    styleMask:NSWindowStyleMaskBorderless
                                                      backing:NSBackingStoreBuffered
                                                        defer:YES] autorelease];
    host = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 900, 900)] autorelease];
    [window setContentView:host];
    NSStackView *stack = [[[NSStackView alloc] initWithFrame:NSMakeRect(10, 10, w, h)] autorelease];
    [stack setOrientation:orientation];
    [host addSubview:stack];
    return stack;
}

// ... or by constraints of its own
static NSStackView *pinnedStack(CGFloat w, CGFloat h)
{
    NSStackView *stack = framedStack(w, h, NSUserInterfaceLayoutOrientationHorizontal);
    [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
    NSLayoutAttribute attributes[4] = { NSLayoutAttributeLeading, NSLayoutAttributeTop, NSLayoutAttributeWidth, NSLayoutAttributeHeight };
    CGFloat constants[4] = { 10, 10, w, h };
    for (int i = 0; i < 4; i++) {
        BOOL edge = i < 2;
        [host addConstraint:[NSLayoutConstraint constraintWithItem:stack
                                                         attribute:attributes[i]
                                                         relatedBy:NSLayoutRelationEqual
                                                            toItem:edge ? host : nil
                                                         attribute:edge ? attributes[i] : NSLayoutAttributeNotAnAttribute
                                                        multiplier:1
                                                          constant:constants[i]]];
    }
    return stack;
}

static void setPinnedWidth(CGFloat w)
{
    for (NSLayoutConstraint *c in [host constraints])
        if ([c firstAttribute] == NSLayoutAttributeWidth)
            [c setConstant:w];
}

static NSArray *fill(NSStackView *stack, NSArray *lead, NSArray *mid, NSArray *trail)
{
    NSMutableArray *all = [NSMutableArray array];
    for (NSView *v in lead) { [stack addView:v inGravity:NSStackViewGravityLeading]; [all addObject:v]; }
    for (NSView *v in mid) { [stack addView:v inGravity:NSStackViewGravityCenter]; [all addObject:v]; }
    for (NSView *v in trail) { [stack addView:v inGravity:NSStackViewGravityTrailing]; [all addObject:v]; }
    return all;
}

// The standard views: A40 B30 | C20 | D50, 20 or 10 high
static NSArray *fourViews(NSStackView *stack)
{
    return fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20) ], @[ box(@"C", 20, 10) ], @[ box(@"D", 50, 20) ]);
}

static void layout(void) { [host layoutSubtreeIfNeeded]; }

static void expectFrame(NSView *view, CGFloat x, CGFloat y, CGFloat w, CGFloat h, const char *what)
{
    NSRect f = [view frame];
    CHECK(fabs(f.origin.x - x) < 0.01 && fabs(f.origin.y - y) < 0.01 && fabs(f.size.width - w) < 0.01 && fabs(f.size.height - h) < 0.01,
          "%s: %s is {%g,%g,%g,%g}, expected {%g,%g,%g,%g}", what, [[view identifier] UTF8String], f.origin.x, f.origin.y, f.size.width, f.size.height, x, y, w, h);
}

// Frames of the views in order as x, y, width, height
static void expectFrames(NSArray *views, const CGFloat *frames, const char *what)
{
    layout();
    for (NSUInteger i = 0; i < [views count]; i++)
        expectFrame([views objectAtIndex:i], frames[4 * i], frames[4 * i + 1], frames[4 * i + 2], frames[4 * i + 3], what);
}

static void expectFitting(NSStackView *stack, CGFloat width, const char *what)
{
    layout();
    CHECK(fabs([stack fittingSize].width - width) < 0.01, "%s: fitting width %g, expected %g", what, [stack fittingSize].width, width);
}

static void test_gravity_layout(void)
{
    CGFloat w300[] = { 0, 5, 40, 20, 48, 5, 30, 20, 140, 10, 20, 10, 250, 5, 50, 20 };
    CGFloat w200[] = { 0, 5, 40, 20, 48, 5, 30, 20, 90, 10, 20, 10, 150, 5, 50, 20 };
    NSStackView *stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    NSArray *views = fourViews(stack);

    CHECK([stack distribution] == NSStackViewDistributionGravityAreas, "default distribution is gravity areas");
    expectFrames(views, w300, "A B | C | D in 300");
    [stack setFrameSize:NSMakeSize(200, 30)];
    expectFrames(views, w200, "A B | C | D in 200");

    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20) ], @[], @[ box(@"D", 50, 20) ]);
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 48, 5, 30, 20, 250, 5, 50, 20 }, "leading and trailing areas");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fill(stack, @[], @[ box(@"C", 20, 10), box(@"C2", 40, 10) ], @[]);
    expectFrames(views, (CGFloat[]){ 116, 10, 20, 10, 144, 10, 40, 10 }, "center area only");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fill(stack, @[], @[], @[ box(@"D", 50, 20), box(@"D2", 30, 20) ]);
    expectFrames(views, (CGFloat[]){ 212, 5, 50, 20, 270, 5, 30, 20 }, "trailing area only");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fill(stack, @[ box(@"A", 40, 20) ], @[ box(@"C", 20, 10) ], @[]);
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 140, 10, 20, 10 }, "leading and center areas");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fill(stack, @[], @[ box(@"C", 20, 10) ], @[ box(@"D", 50, 20) ]);
    expectFrames(views, (CGFloat[]){ 140, 10, 20, 10, 250, 5, 50, 20 }, "center and trailing areas");

    // spacing, and the space after a view
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    [stack setSpacing:0];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 40, 5, 30, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "spacing 0");
    [stack setSpacing:20];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 60, 5, 30, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "spacing 20");
    [stack setSpacing:8];
    [stack setCustomSpacing:2 afterView:[views objectAtIndex:0]];
    CHECK([stack customSpacingAfterView:[views objectAtIndex:0]] == 2, "custom spacing is kept");
    CHECK([stack customSpacingAfterView:[views objectAtIndex:1]] == NSStackViewSpacingUseDefault, "no custom spacing by default");
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 42, 5, 30, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "custom spacing after A");

    // vertical, top first
    stack = framedStack(100, 300, NSUserInterfaceLayoutOrientationVertical);
    views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 30) ], @[ box(@"C", 20, 20) ], @[ box(@"D", 50, 50) ]);
    expectFrames(views, (CGFloat[]){ 30, 280, 40, 20, 35, 242, 30, 30, 40, 140, 20, 20, 25, 0, 50, 50 }, "vertical gravity areas in 300");
}

static void test_fitting_sizes(void)
{
    NSStackView *stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    NSArray *views = fourViews(stack);
    expectFitting(stack, 192, "A B | C | D: the center area is centered in the stack");
    [stack setSpacing:0];
    expectFitting(stack, 160, "spacing 0");
    [stack setSpacing:20];
    expectFitting(stack, 240, "spacing 20");
    [stack setSpacing:8];
    [stack setCustomSpacing:2 afterView:[views objectAtIndex:0]];
    expectFitting(stack, 180, "custom spacing 2 after A");
    [stack setCustomSpacing:NSStackViewSpacingUseDefault afterView:[views objectAtIndex:0]];
    [stack setCustomSpacing:40 afterView:[views objectAtIndex:1]];
    expectFitting(stack, 256, "custom spacing 40 after the last leading view");
    [stack setCustomSpacing:NSStackViewSpacingUseDefault afterView:[views objectAtIndex:1]];
    [stack setCustomSpacing:40 afterView:[views objectAtIndex:2]];
    expectFitting(stack, 200, "custom spacing 40 after the last center view");
    [stack setCustomSpacing:NSStackViewSpacingUseDefault afterView:[views objectAtIndex:2]];
    [stack setCustomSpacing:40 afterView:[views objectAtIndex:3]];
    expectFitting(stack, 192, "custom spacing after the last view counts for nothing");
    [stack setCustomSpacing:NSStackViewSpacingUseDefault afterView:[views objectAtIndex:3]];
    [stack setCustomSpacing:0 afterView:[views objectAtIndex:0]];
    [stack setCustomSpacing:-5 afterView:[views objectAtIndex:1]];
    expectFitting(stack, 150, "custom spacing 0 after A and -5 after B");

    struct { NSArray *lead, *mid, *trail; CGFloat width; const char *what; } cases[] = {
        { @[ box(@"A", 40, 20), box(@"B", 30, 20) ], @[], @[ box(@"D", 50, 20) ], 136, "leading and trailing" },
        { @[], @[ box(@"C", 20, 10), box(@"C2", 40, 10) ], @[], 68, "center only" },
        { @[ box(@"A", 40, 20) ], @[], @[], 40, "leading only" },
        { @[], @[], @[ box(@"D", 50, 20), box(@"D2", 30, 20) ], 88, "trailing only" },
        { @[ box(@"A", 40, 20) ], @[ box(@"C", 20, 10) ], @[], 116, "leading and center" },
        { @[], @[ box(@"C", 20, 10) ], @[ box(@"D", 50, 20) ], 136, "center and trailing" },
        { @[ box(@"A", 120, 20), box(@"B", 60, 20) ], @[ box(@"C", 60, 10) ], @[ box(@"D", 40, 20) ], 452, "a wide leading area" },
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
        fill(stack, cases[i].lead, cases[i].mid, cases[i].trail);
        expectFitting(stack, cases[i].width, cases[i].what);
    }

    stack = framedStack(100, 300, NSUserInterfaceLayoutOrientationVertical);
    fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 30) ], @[ box(@"C", 20, 20) ], @[ box(@"D", 50, 50) ]);
    layout();
    CHECK(fabs([stack fittingSize].height - 152) < 0.01 && fabs([stack fittingSize].width - 50) < 0.01,
          "vertical gravity areas fit {%g,%g}, expected {50,152}", [stack fittingSize].width, [stack fittingSize].height);

    NSStackViewDistribution distributions[] = { NSStackViewDistributionFill, NSStackViewDistributionFillEqually,
                                                NSStackViewDistributionFillProportionally, NSStackViewDistributionEqualSpacing,
                                                NSStackViewDistributionEqualCentering };
    CGFloat widths[] = { 164, 224, 164, 164, 174 };
    for (int i = 0; i < 5; i++) {
        stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
        [stack setDistribution:distributions[i]];
        fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20), box(@"C", 20, 10), box(@"D", 50, 20) ], @[], @[]);
        expectFitting(stack, widths[i], "distribution");
    }
}

// QUIRK: in gravity areas, a view that hugs below 250 is stretched to the next area. See
// -[NSStackView _stretchGravityAreas:...].
static void test_quirk_gravity_area_stretch(void)
{
    struct { int view; CGFloat hugging; CGFloat widths[2]; CGFloat frames[16]; const char *what; } cases[] = {
        { 1, 100, {300, 0}, { 0, 5, 40, 20, 48, 5, 84, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "B hugging 100 stretches to the center area" },
        { 1, 249, {300, 0}, { 0, 5, 40, 20, 48, 5, 84, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "B hugging 249 stretches" },
        { 1, 250, {300, 0}, { 0, 5, 40, 20, 48, 5, 30, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "B hugging 250 does not" },
        { 1, 251, {300, 0}, { 0, 5, 40, 20, 48, 5, 30, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "B hugging 251 does not" },
        { 0, 100, {300, 0}, { 0, 5, 94, 20, 102, 5, 30, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "A hugging 100: the leading area still ends at the center area" },
        { 2, 100, {300, 0}, { 0, 5, 40, 20, 48, 5, 30, 20, 86, 10, 128, 10, 250, 5, 50, 20 }, "C hugging 100: the center area grows both ways" },
        { 3, 100, {300, 0}, { 0, 5, 40, 20, 48, 5, 30, 20, 140, 10, 20, 10, 168, 5, 132, 20 }, "D hugging 100 stretches back to the center area" },
        { 1, 100, {200, 0}, { 0, 5, 40, 20, 48, 5, 34, 20, 90, 10, 20, 10, 150, 5, 50, 20 }, "B hugging 100 in 200" },
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        NSStackView *stack = framedStack(cases[i].widths[0], 30, NSUserInterfaceLayoutOrientationHorizontal);
        NSArray *views = fourViews(stack);
        [[views objectAtIndex:cases[i].view] setContentHuggingPriority:cases[i].hugging forOrientation:H];
        expectFrames(views, cases[i].frames, cases[i].what);
    }

    NSStackView *stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    NSArray *views = fourViews(stack);
    [[views objectAtIndex:0] setContentHuggingPriority:100 forOrientation:H];
    [[views objectAtIndex:1] setContentHuggingPriority:50 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 48, 5, 84, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "the least hugging view stretches");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    for (int i = 1; i < 4; i++)
        [[views objectAtIndex:i] setContentHuggingPriority:100 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 48, 5, 84, 20, 140, 10, 20, 10, 168, 5, 132, 20 }, "the outer areas stretch before the center area");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    [stack setSpacing:20];
    [[views objectAtIndex:1] setContentHuggingPriority:100 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 60, 5, 60, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "stretching keeps the spacing");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    [stack setCustomSpacing:30 afterView:[views objectAtIndex:1]];
    [[views objectAtIndex:1] setContentHuggingPriority:100 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 48, 5, 62, 20, 140, 10, 20, 10, 250, 5, 50, 20 }, "stretching keeps the space after the area's last view");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fill(stack, @[ box(@"A", 40, 20) ], @[], @[ box(@"B", 30, 20) ]);
    [[views objectAtIndex:0] setContentHuggingPriority:100 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 262, 20, 270, 5, 30, 20 }, "leading view stretching to the trailing area");

    stack = framedStack(100, 300, NSUserInterfaceLayoutOrientationVertical);
    views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 30) ], @[ box(@"C", 20, 20) ], @[ box(@"D", 50, 50) ]);
    [[views objectAtIndex:1] setContentHuggingPriority:100 forOrientation:NSLayoutConstraintOrientationVertical];
    expectFrames(views, (CGFloat[]){ 30, 280, 40, 20, 35, 168, 30, 104, 40, 140, 20, 20, 25, 0, 50, 50 }, "vertical hugging");
}

static void test_fill_distributions(void)
{
    NSStackView *stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    NSArray *views = fourViews(stack);
    [stack setDistribution:NSStackViewDistributionFill];
    expectFrames(views, (CGFloat[]){ 0, 5, 176, 20, 184, 5, 30, 20, 222, 10, 20, 10, 250, 5, 50, 20 }, "fill: the first of equally hugging views stretches");
    [[views objectAtIndex:3] setContentHuggingPriority:249 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 48, 5, 30, 20, 86, 10, 20, 10, 114, 5, 186, 20 }, "fill: the view that hugs least stretches");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    [stack setDistribution:NSStackViewDistributionFill];
    [[views objectAtIndex:3] setContentHuggingPriority:251 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 176, 20, 184, 5, 30, 20, 222, 10, 20, 10, 250, 5, 50, 20 }, "fill: D hugging 251");
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    [stack setDistribution:NSStackViewDistributionFill];
    for (NSView *v in views)
        [v setContentHuggingPriority:300 forOrientation:H];
    [[views objectAtIndex:0] setContentHuggingPriority:301 forOrientation:H];
    expectFrames(views, (CGFloat[]){ 0, 5, 40, 20, 48, 5, 166, 20, 222, 10, 20, 10, 250, 5, 50, 20 }, "fill: first of the least hugging");

    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20), box(@"C", 20, 10) ], @[], @[]);
    [stack setDistribution:NSStackViewDistributionFill];
    [stack setCustomSpacing:30 afterView:[views objectAtIndex:0]];
    expectFrames(views, (CGFloat[]){ 0, 5, 212, 20, 242, 5, 30, 20, 280, 10, 20, 10 }, "fill with custom spacing");

    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    [stack setDistribution:NSStackViewDistributionFill];
    [[views objectAtIndex:2] setHidden:YES];
    [stack setDetachesHiddenViews:YES];
    layout();
    CHECK([[stack detachedViews] containsObject:[views objectAtIndex:2]], "a hidden view detaches when asked to");
    expectFrame([views objectAtIndex:0], 0, 5, 204, 20, "fill without the hidden view");
    expectFrame([views objectAtIndex:1], 212, 5, 30, 20, "fill without the hidden view");
    expectFrame([views objectAtIndex:3], 250, 5, 50, 20, "fill without the hidden view");

    NSStackViewDistribution distributions[] = { NSStackViewDistributionFillEqually, NSStackViewDistributionEqualCentering };
    CGFloat frames[2][16] = {
        { 0, 5, 69, 20, 77, 5, 69, 20, 154, 10, 69, 10, 231, 5, 69, 20 },
        { 0, 5, 40, 20, 90, 5, 30, 20, 180, 10, 20, 10, 250, 5, 50, 20 },
    };
    for (int i = 0; i < 2; i++) {
        stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
        [stack setDistribution:distributions[i]];
        views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20), box(@"C", 20, 10), box(@"D", 50, 20) ], @[], @[]);
        expectFrames(views, frames[i], "distribution of four views in 300");
    }
}

// QUIRK: frames fall on whole pixels. See -[NSStackView _frameAlignedToPixels:].
static void test_quirk_pixel_aligned_frames(void)
{
    NSStackViewDistribution distributions[] = { NSStackViewDistributionFillProportionally, NSStackViewDistributionEqualSpacing };
    CGFloat frames[2][16] = {
        { 0, 5, 79, 20, 87, 5, 59, 20, 154, 10, 39, 10, 201, 5, 99, 20 },
        { 0, 5, 40, 20, 93, 5, 30, 20, 177, 10, 20, 10, 250, 5, 50, 20 },
    };
    for (int i = 0; i < 2; i++) {
        NSStackView *stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
        NSArray *views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20), box(@"C", 20, 10), box(@"D", 50, 20) ], @[], @[]);

        [stack setDistribution:distributions[i]];
        expectFrames(views, frames[i], i ? "equal spacing of four views in 300 points" : "proportional fill of four views in 300 points");
    }
}

// QUIRK: a new stack view does not detach hidden views. See -[NSStackView _setUpStackView].
static void test_quirk_detaches_hidden_views_default(void)
{
    NSStackView *stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    NSArray *views = fourViews(stack);
    NSView *b = [views objectAtIndex:1];

    CHECK(![stack detachesHiddenViews], "a new stack view does not detach hidden views");
    [b setHidden:YES];
    layout();
    CHECK([[stack detachedViews] count] == 0, "a hidden view is not detached by default");
    expectFrame([views objectAtIndex:2], 140, 10, 20, 10, "a hidden view still takes its room");
    [stack setDetachesHiddenViews:YES];
    layout();
    CHECK([[stack detachedViews] containsObject:b], "a hidden view is detached once the stack view detaches them");
    expectFrame([views objectAtIndex:0], 0, 5, 40, 20, "A with B detached");
    expectFrame([views objectAtIndex:2], 140, 10, 20, 10, "the center area stays centered with B detached");
    expectFrame([views objectAtIndex:3], 250, 5, 50, 20, "D with B detached");
    expectFitting(stack, 136, "fitting size without B");
    [b setHidden:NO];
    layout();
    CHECK([[stack detachedViews] count] == 0, "a shown view is attached again");
    expectFrame(b, 48, 5, 30, 20, "B shown again");

    // not visible views
    stack = framedStack(300, 30, NSUserInterfaceLayoutOrientationHorizontal);
    views = fourViews(stack);
    [stack setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible forView:[views objectAtIndex:1]];
    layout();
    CHECK([[stack detachedViews] isEqualToArray:@[ [views objectAtIndex:1] ]], "a not visible view is detached");
    expectFrame([views objectAtIndex:0], 0, 5, 40, 20, "A with B not visible");
    expectFrame([views objectAtIndex:3], 250, 5, 50, 20, "D with B not visible");
    [stack setVisibilityPriority:NSStackViewVisibilityPriorityMustHold forView:[views objectAtIndex:1]];
    layout();
    CHECK([[stack detachedViews] count] == 0, "a view that must be held is attached again");
    expectFrame([views objectAtIndex:1], 48, 5, 30, 20, "B again");
}

static NSArray *detachedNames(NSStackView *stack)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSView *v in [stack detachedViews])
        [names addObject:[v identifier]];
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

static void expectDetached(NSStackView *stack, NSArray *names, const char *what)
{
    layout();
    CHECK([detachedNames(stack) isEqualToArray:names], "%s: detached %s, expected %s", what,
          [[detachedNames(stack) description] UTF8String], [[names description] UTF8String]);
}

// QUIRK: a stack view that is too small for its views detaches the views of the lowest visibility
// priority. See -[NSStackView _updateDroppedViews].
static void test_quirk_visibility_priority_drop(void)
{
    // by constraints and by frame
    for (int mode = 0; mode < 2; mode++) {
        CGFloat widths[] = { 200, 150, 120, 100, 60, 40 };
        NSArray *expected[] = { @[], @[ @"D" ], @[ @"D" ], @[ @"C", @"D" ], @[ @"B", @"C", @"D" ], @[ @"B", @"C", @"D" ] };
        Watcher *watcher = [[[Watcher alloc] init] autorelease];
        NSStackView *stack = mode ? framedStack(200, 30, NSUserInterfaceLayoutOrientationHorizontal) : pinnedStack(200, 30);
        char what[96];

        [stack setClippingResistancePriority:250 forOrientation:H];
        [stack setDelegate:watcher];
        CGFloat priorities[] = { 1000, 900, 500, 200 };
        NSArray *views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20), box(@"C", 20, 10), box(@"D", 50, 20) ], @[], @[]);
        for (int i = 0; i < 4; i++)
            [stack setVisibilityPriority:priorities[i] forView:[views objectAtIndex:i]];
        for (int i = 0; i < 6; i++) {
            if (mode)
                [stack setFrameSize:NSMakeSize(widths[i], 30)];
            else
                setPinnedWidth(widths[i]);
            snprintf(what, sizeof what, "%s stack %g wide, clipping resistance 250", mode ? "framed" : "pinned", widths[i]);
            expectDetached(stack, expected[i], what);
            if (i == 3) {
                expectFrame([views objectAtIndex:0], 0, 5, 40, 20, what);
                expectFrame([views objectAtIndex:1], 48, 5, 30, 20, what);
            }
        }
        CHECK([watcher.detached containsObject:[views objectAtIndex:3]] && [watcher.detached containsObject:[views objectAtIndex:2]] &&
                  [watcher.detached containsObject:[views objectAtIndex:1]],
              "the delegate is told about D, C and B");
        if (mode)
            [stack setFrameSize:NSMakeSize(200, 30)];
        else
            setPinnedWidth(200);
        expectDetached(stack, @[], "widened again");
        CHECK([watcher.reattached containsObject:[views objectAtIndex:1]] && [watcher.reattached containsObject:[views objectAtIndex:2]] &&
                  [watcher.reattached containsObject:[views objectAtIndex:3]],
              "the delegate is told about the views attached again");
        expectFrame([views objectAtIndex:3], 114, 5, 50, 20, "D attached again");
        expectFrame([views objectAtIndex:2], 86, 10, 20, 10, "C attached again");
    }

    // views of equal priority go together
    NSStackView *stack = pinnedStack(120, 30);
    [stack setClippingResistancePriority:250 forOrientation:H];
    NSArray *views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 40, 20), box(@"C", 40, 20), box(@"D", 40, 20) ], @[], @[]);
    for (NSView *v in views)
        [stack setVisibilityPriority:500 forView:v];
    expectDetached(stack, (@[ @"A", @"B", @"C", @"D" ]), "four views of equal priority in 120 points");

    // views that must be held are not detached, and others only down to what fits
    stack = pinnedStack(130, 30);
    [stack setClippingResistancePriority:250 forOrientation:H];
    views = fourViews(stack);
    [stack setVisibilityPriority:NSStackViewVisibilityPriorityDetachOnlyIfNecessary forView:[views objectAtIndex:2]];
    expectDetached(stack, @[ @"C" ], "C detachable only if necessary");
    expectFrame([views objectAtIndex:0], 0, 5, 40, 20, "A with C detached");
    expectFrame([views objectAtIndex:1], 48, 5, 30, 20, "B with C detached");
    expectFrame([views objectAtIndex:3], 86, 5, 50, 20, "D with C detached");

    // what the clipping resistance does: below 750 detaches, from 751 compresses
    CGFloat resistances[] = { 1000, 800, 751, 749, 500, 100 };
    for (int i = 0; i < 6; i++) {
        char what[96];

        stack = pinnedStack(120, 30);
        [stack setClippingResistancePriority:resistances[i] forOrientation:H];
        views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20), box(@"C", 20, 10), box(@"D", 50, 20) ], @[], @[]);
        CGFloat priorities[] = { 1000, 900, 500, 200 };
        for (int k = 0; k < 4; k++)
            [stack setVisibilityPriority:priorities[k] forView:[views objectAtIndex:k]];
        snprintf(what, sizeof what, "clipping resistance %g", resistances[i]);
        expectDetached(stack, resistances[i] < 750 ? @[ @"D" ] : @[], what);
    }
    // the stack view's other settings do not change that
    stack = pinnedStack(120, 30);
    views = fill(stack, @[ box(@"A", 40, 20), box(@"B", 30, 20), box(@"C", 20, 10), box(@"D", 50, 20) ], @[], @[]);
    for (NSView *v in views)
        [stack setVisibilityPriority:500 forView:v];
    CHECK([stack clippingResistancePriorityForOrientation:H] == 1000, "the default clipping resistance is 1000");
    expectDetached(stack, @[], "default clipping resistance: nothing is detached");
}

// A nib that ibtool compiled from tests/fixtures/nibarchive/src/StackGravity.xib: a horizontal
// stack view of gravity areas holding the buttons A and B (leading), C (center) and D (trailing).
static void test_nib_gravity_views(const char *directory)
{
    NSString *path = [[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:@"flat/StackGravity.nib"];
    NSNib *nib = [[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil] autorelease];
    NSArray *objects = nil;

    CHECK(nib != nil, "the nib loads");
    CHECK([nib instantiateWithOwner:nil topLevelObjects:&objects], "the nib instantiates");
    NSView *top = nil;
    for (id object in objects)
        if ([object isKindOfClass:[NSView class]])
            top = object;
    NSStackView *stack = nil;
    for (NSView *v in [top subviews])
        if ([v isKindOfClass:[NSStackView class]])
            stack = (NSStackView *)v;
    CHECK(stack != nil, "the nib has a stack view");
    if (stack == nil)
        return;

    CHECK([stack orientation] == NSUserInterfaceLayoutOrientationHorizontal, "orientation");
    CHECK([stack distribution] == NSStackViewDistributionGravityAreas, "distribution is gravity areas");
    CHECK([stack spacing] == 5, "spacing is %g", [stack spacing]);
    NSArray *leading = [stack viewsInGravity:NSStackViewGravityLeading], *center = [stack viewsInGravity:NSStackViewGravityCenter],
            *trailing = [stack viewsInGravity:NSStackViewGravityTrailing];
    CHECK([leading count] == 2 && [center count] == 1 && [trailing count] == 1, "views in gravity areas: %lu %lu %lu",
          (unsigned long)[leading count], (unsigned long)[center count], (unsigned long)[trailing count]);
    if ([leading count] != 2 || [center count] != 1 || [trailing count] != 1)
        return;
    NSButton *a = [leading objectAtIndex:0], *b = [leading objectAtIndex:1], *c = [center objectAtIndex:0], *d = [trailing objectAtIndex:0];
    CHECK([[a title] isEqualToString:@"A"] && [[b title] isEqualToString:@"B"] && [[c title] isEqualToString:@"C"] && [[d title] isEqualToString:@"D"],
          "the views are in their archived order");
    CHECK([[stack views] count] == 4, "four views");
    CHECK([stack huggingPriorityForOrientation:H] > 249.9 && [stack huggingPriorityForOrientation:H] < 250, "stack hugging is archived");
    // the custom spacing and visibility priorities live in NSMapTables with weak, view-keyed entries
    CHECK([stack customSpacingAfterView:a] == 3, "custom spacing after A is %g", [stack customSpacingAfterView:a]);
    CHECK([stack customSpacingAfterView:b] == NSStackViewSpacingUseDefault, "no custom spacing after B: %g", [stack customSpacingAfterView:b]);
    CHECK([stack visibilityPriorityForView:a] == NSStackViewVisibilityPriorityMustHold, "A's visibility priority is %g", [stack visibilityPriorityForView:a]);
    CHECK([stack visibilityPriorityForView:b] == 600, "B's visibility priority is %g", [stack visibilityPriorityForView:b]);
    CHECK([stack visibilityPriorityForView:d] == NSStackViewVisibilityPriorityNotVisible, "D's visibility priority is %g", [stack visibilityPriorityForView:d]);

    // in a window the stack view arranges its views at once, the center area centered
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 100)
                                                    styleMask:NSWindowStyleMaskBorderless
                                                      backing:NSBackingStoreBuffered
                                                        defer:YES] autorelease];
    [window setContentView:top];
    [top layoutSubtreeIfNeeded];
    CHECK(fabs(NSMidX([c frame]) - NSWidth([stack bounds]) / 2) <= 1, "C is centered in the stack: %s in %g", [NSStringFromRect([c frame]) UTF8String], NSWidth([stack bounds]));
    CHECK(NSMaxX([b frame]) < NSMinX([c frame]), "C is right of B");
}

// What macOS archives for a stack view with views in gravity areas (the keys NSKeyedArchiver writes
// for NSStackView and NSStackViewContainer on macOS 10.14.4 and 26.7.3), decoded as an NSStackView.
@interface ArchivedContainer : NSObject <NSCoding> {
@public
    NSArray *views;
    NSMapTable *spacings, *priorities;
    id stack;
}
@end
@implementation ArchivedContainer
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt32:256 forKey:@"NSvFlags"];
    [coder encodeObject:@"{0, 0}" forKey:@"NSFrameSize"];
    [coder encodeObject:stack forKey:@"NSStackViewContainerStackView"];
    [coder encodeObject:views forKey:@"NSStackViewContainerNonDroppedViews"];
    [coder encodeObject:spacings forKey:@"NSStackViewContainerViewToCustomAfterSpaceMap"];
    [coder encodeObject:priorities forKey:@"NSStackViewContainerVisibilityPriorities"];
}
- (instancetype)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

@interface ArchivedStack : NSObject <NSCoding> {
@public
    NSArray *subviews;
    ArchivedContainer *begin, *middle, *end;
}
@end
@implementation ArchivedStack
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInt32:256 forKey:@"NSvFlags"];
    [coder encodeObject:@"{300, 30}" forKey:@"NSFrameSize"];
    [coder encodeObject:subviews forKey:@"NSSubviews"];
    [coder encodeInteger:0 forKey:@"NSStackViewOrientation"];
    [coder encodeInteger:10 forKey:@"NSStackViewAlignment"];
    [coder encodeFloat:5 forKey:@"NSStackViewSpacing"];
    [coder encodeFloat:0 forKey:@"NSStackViewEdgeInsets.top"];
    [coder encodeFloat:0 forKey:@"NSStackViewEdgeInsets.left"];
    [coder encodeFloat:0 forKey:@"NSStackViewEdgeInsets.bottom"];
    [coder encodeFloat:0 forKey:@"NSStackViewEdgeInsets.right"];
    [coder encodeBool:NO forKey:@"NSStackViewDetachesHiddenViews"];
    [coder encodeBool:YES forKey:@"NSStackViewHasFlatViewHierarchy"];
    [coder encodeObject:begin forKey:@"NSStackViewBeginningContainer"];
    [coder encodeObject:middle forKey:@"NSStackViewMiddleContainer"];
    [coder encodeObject:end forKey:@"NSStackViewEndContainer"];
}
- (instancetype)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static NSView *plain(CGFloat width) { return [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, 20)] autorelease]; }

static void test_decode_gravity_archive(void)
{
    NSView *a = plain(20), *b = plain(25), *c = plain(30), *d = plain(35);
    ArchivedStack *archived = [[[ArchivedStack alloc] init] autorelease];
    ArchivedContainer *containers[3];

    for (int i = 0; i < 3; i++) {
        containers[i] = [[[ArchivedContainer alloc] init] autorelease];
        containers[i]->stack = archived;
    }
    containers[0]->views = @[ a, b ];
    containers[1]->views = @[ c ];
    containers[2]->views = @[ d ];
    containers[0]->spacings = [NSMapTable strongToStrongObjectsMapTable];
    [containers[0]->spacings setObject:@3.0 forKey:a];
    containers[0]->priorities = [NSMapTable strongToStrongObjectsMapTable];
    [containers[0]->priorities setObject:@600.0 forKey:b];
    containers[2]->priorities = [NSMapTable strongToStrongObjectsMapTable];
    [containers[2]->priorities setObject:@0.0 forKey:d];
    archived->subviews = @[ a, b, c ];
    archived->begin = containers[0];
    archived->middle = containers[1];
    archived->end = containers[2];

    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:data] autorelease];
    [archiver setClassName:@"NSStackView" forClass:[ArchivedStack class]];
    [archiver setClassName:@"NSStackViewContainer" forClass:[ArchivedContainer class]];
    [archiver encodeObject:archived forKey:@"root"];
    [archiver finishEncoding];

    NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingWithData:data] autorelease];
    NSStackView *stack = [unarchiver decodeObjectForKey:@"root"];
    [unarchiver finishDecoding];

    CHECK([stack isKindOfClass:[NSStackView class]], "an NSStackView is decoded");
    if (![stack isKindOfClass:[NSStackView class]])
        return;
    NSArray *leading = [stack viewsInGravity:NSStackViewGravityLeading], *center = [stack viewsInGravity:NSStackViewGravityCenter],
            *trailing = [stack viewsInGravity:NSStackViewGravityTrailing];
    CHECK([leading count] == 2 && [center count] == 1 && [trailing count] == 1, "views in gravity areas: %lu %lu %lu",
          (unsigned long)[leading count], (unsigned long)[center count], (unsigned long)[trailing count]);
    if ([leading count] != 2 || [center count] != 1 || [trailing count] != 1)
        return;
    CHECK(NSWidth([[leading objectAtIndex:0] frame]) == 20 && NSWidth([[leading objectAtIndex:1] frame]) == 25 &&
              NSWidth([[center objectAtIndex:0] frame]) == 30 && NSWidth([[trailing objectAtIndex:0] frame]) == 35,
          "the views are in their archived order");
    NSView *da = [leading objectAtIndex:0], *db = [leading objectAtIndex:1], *dd = [trailing objectAtIndex:0];
    CHECK([stack spacing] == 5 && ![stack detachesHiddenViews], "settings are decoded");
    CHECK([stack customSpacingAfterView:da] == 3, "custom spacing after A is %g", [stack customSpacingAfterView:da]);
    CHECK([stack customSpacingAfterView:db] == NSStackViewSpacingUseDefault, "no custom spacing after B");
    CHECK([stack visibilityPriorityForView:db] == 600, "B's visibility priority is %g", [stack visibilityPriorityForView:db]);
    CHECK([stack visibilityPriorityForView:da] == NSStackViewVisibilityPriorityMustHold, "A's visibility priority is the default");
    CHECK([stack visibilityPriorityForView:dd] == NSStackViewVisibilityPriorityNotVisible, "D is not visible");
    CHECK([[stack detachedViews] isEqualToArray:@[ dd ]], "D, not visible, is detached");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_gravity_layout();
        test_fitting_sizes();
        test_quirk_gravity_area_stretch();
        test_fill_distributions();
        test_quirk_pixel_aligned_frames();
        test_quirk_detaches_hidden_views_default();
        test_quirk_visibility_priority_drop();
        test_decode_gravity_archive();
        if (argc > 1)
            test_nib_gravity_views(argv[1]);
        else
            printf("SKIP the nib test: no nib path\n");
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
