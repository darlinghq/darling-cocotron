// Copyright (C) 2026 Lubos Dolezel
// -[NSView invalidateIntrinsicContentSize]: the layout flags it leaves, that the next layout pass uses
// the new intrinsic size, that AppKit controls call it when their content changes (and not when a
// setter is given the value the control already has), and that a frame-placed stack view arranges its
// views again with the new size. The QUIRK in NSView.m (a view whose autoresizing mask is translated
// into constraints is not queued) is covered by the "tamic" checks.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
static int g_calls;

#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)
// The setter must call it at least once.
#define CALLS(label, ...) do { g_calls = 0; __VA_ARGS__; \
        if (g_calls < 1) { printf("FAIL %d: %s did not invalidate\n", __LINE__, label); g_failures++; } } while (0)
// The setter is given what the control has and must not call it.
#define NO_CALLS(label, ...) do { g_calls = 0; __VA_ARGS__; \
        if (g_calls != 0) { printf("FAIL %d: %s invalidated (%d)\n", __LINE__, label, g_calls); g_failures++; } } while (0)

@interface IntrView : NSView { NSSize _size; }
@property NSSize size;
@end
@implementation IntrView
@synthesize size = _size;
- (NSSize)intrinsicContentSize { return _size; }
- (void)invalidateIntrinsicContentSize { g_calls++; [super invalidateIntrinsicContentSize]; }
@end

@interface CountField : NSTextField @end
@implementation CountField
- (void)invalidateIntrinsicContentSize { g_calls++; [super invalidateIntrinsicContentSize]; }
@end
@interface CountButton : NSButton @end
@implementation CountButton
- (void)invalidateIntrinsicContentSize { g_calls++; [super invalidateIntrinsicContentSize]; }
@end
@interface CountImageView : NSImageView @end
@implementation CountImageView
- (void)invalidateIntrinsicContentSize { g_calls++; [super invalidateIntrinsicContentSize]; }
@end
@interface CountPopUp : NSPopUpButton @end
@implementation CountPopUp
- (void)invalidateIntrinsicContentSize { g_calls++; [super invalidateIntrinsicContentSize]; }
@end

static NSWindow *g_window;
static NSView *g_host;

static void settle(void)
{
    [g_window layoutIfNeeded];
    [g_host layoutSubtreeIfNeeded];
}

static void pinToTopLeft(NSView *view)
{
    [view setTranslatesAutoresizingMaskIntoConstraints:NO];
    [g_host addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [[view leadingAnchor] constraintEqualToAnchor:[g_host leadingAnchor]],
        [[view topAnchor] constraintEqualToAnchor:[g_host topAnchor]]]];
}

static void test_flags_and_relayout(void)
{
    IntrView *view = [[IntrView alloc] init];

    [view setSize:NSMakeSize(40, 20)];
    pinToTopLeft(view);
    settle();
    CHECK(NSEqualSizes([view frame].size, NSMakeSize(40, 20)));
    CHECK(![view needsUpdateConstraints] && ![view needsLayout]);

    [view setSize:NSMakeSize(90, 25)];
    [view invalidateIntrinsicContentSize];
    // The view is queued for a constraint update; the layout flags of it and of its superview are not touched
    CHECK([view needsUpdateConstraints]);
    CHECK(![view needsLayout]);
    CHECK(![g_host needsLayout] && ![g_host needsUpdateConstraints]);
    settle();
    CHECK(![view needsUpdateConstraints]);
    CHECK(NSEqualSizes([view frame].size, NSMakeSize(90, 25)));
    [view removeFromSuperview];

    // A view placed by its frame is not queued (tamic)
    IntrView *frameView = [[IntrView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [frameView setSize:NSMakeSize(40, 20)];
    [g_host addSubview:frameView];
    settle();
    CHECK(![frameView needsUpdateConstraints] && ![frameView needsLayout]);
    [frameView invalidateIntrinsicContentSize];
    CHECK(![frameView needsUpdateConstraints] && ![frameView needsLayout]);
    CHECK(![g_host needsLayout]);
    CHECK(NSEqualRects([frameView frame], NSMakeRect(0, 0, 10, 10)));
    [frameView removeFromSuperview];

    // Not in a window and not in a superview: no failure
    IntrView *loose = [[IntrView alloc] init];
    [loose setTranslatesAutoresizingMaskIntoConstraints:NO];
    [loose invalidateIntrinsicContentSize];
    CHECK([loose needsUpdateConstraints]);
}

static void test_controls(void)
{
    CountField *tf = [[CountField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
    CountField *label = [CountField labelWithString:@"x"];
    CountButton *button = [[CountButton alloc] initWithFrame:NSMakeRect(0, 30, 100, 24)];
    CountImageView *imageView = [[CountImageView alloc] initWithFrame:NSMakeRect(0, 60, 32, 32)];
    CountPopUp *popup = [[CountPopUp alloc] initWithFrame:NSMakeRect(0, 100, 100, 24) pullsDown:NO];
    for (NSView *v in @[tf, label, button, imageView, popup])
        [g_host addSubview:v];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    NSImage *image2 = [[NSImage alloc] initWithSize:NSMakeSize(24, 24)];
    NSFont *font = [NSFont systemFontOfSize:20];

    CALLS("text field setStringValue:", [tf setStringValue:@"hello"]);
    NO_CALLS("text field setStringValue: same value", [tf setStringValue:@"hello"]);
    CALLS("text field setAttributedStringValue:", [tf setAttributedStringValue:[[NSAttributedString alloc] initWithString:@"world"]]);
    CALLS("text field setObjectValue:", [tf setObjectValue:@"obj"]);
    CALLS("text field setIntegerValue:", [tf setIntegerValue:42]);
    CALLS("text field setFont:", [tf setFont:font]);
    NO_CALLS("text field setFont: same font", [tf setFont:font]);
    CALLS("text field setControlSize:", [tf setControlSize:NSControlSizeSmall]);
    CALLS("text field setBezeled:", [tf setBezeled:NO]);
    CALLS("text field setBordered:", [tf setBordered:YES]);
    CALLS("text field setAlignment:", [tf setAlignment:NSTextAlignmentRight]);
    CALLS("label setStringValue:", [label setStringValue:@"a longer label"]);

    CALLS("button setTitle:", [button setTitle:@"Press"]);
    NO_CALLS("button setTitle: same title", [button setTitle:@"Press"]);
    CALLS("button setAttributedTitle:", [button setAttributedTitle:[[NSAttributedString alloc] initWithString:@"Attr"]]);
    CALLS("button setAlternateTitle:", [button setAlternateTitle:@"Alt"]);
    CALLS("button setImage:", [button setImage:image]);
    CALLS("button setAlternateImage:", [button setAlternateImage:image]);
    CALLS("button setImagePosition:", [button setImagePosition:NSImageLeft]);
    [button setBezelStyle:NSBezelStyleRounded];
    CALLS("button setBezelStyle:", [button setBezelStyle:NSBezelStyleRegularSquare]);
    CALLS("button setButtonType:", [button setButtonType:NSButtonTypeSwitch]);
    CALLS("button setFont:", [button setFont:font]);
    CALLS("button setControlSize:", [button setControlSize:NSControlSizeMini]);

    CALLS("image view setImage:", [imageView setImage:image]);
    CALLS("image view setImage: other image", [imageView setImage:image2]);
    CALLS("image view setImage: nil", [imageView setImage:nil]);
    CALLS("image view setImageFrameStyle:", [imageView setImageFrameStyle:NSImageFrameGrayBezel]);

    CALLS("pop-up addItemWithTitle:", [popup addItemWithTitle:@"One"]);
    [popup addItemsWithTitles:@[@"Two", @"A much longer item"]];
    CALLS("pop-up selectItemAtIndex: (selection changes)", [popup selectItemAtIndex:2]);
    NO_CALLS("pop-up selectItemAtIndex: (same selection)", [popup selectItemAtIndex:2]);
    CALLS("pop-up selectItemWithTitle:", [popup selectItemWithTitle:@"One"]);
    CALLS("pop-up setFont:", [popup setFont:font]);
    CALLS("pop-up removeAllItems", [popup removeAllItems]);
}

// Stack views that are placed by their frame measure their views at layout
static void test_stack_remeasures(void)
{
    NSTextField *label = [NSTextField labelWithString:@"x"];
    NSView *second = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 30, 20)];
    NSStackView *stack = [NSStackView stackViewWithViews:@[label, second]];

    [stack setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [stack setDistribution:NSStackViewDistributionGravityAreas];
    [stack setSpacing:8];
    [stack setFrame:NSMakeRect(0, 100, 400, 30)];
    [g_host addSubview:stack];
    settle();
    CGFloat before = NSMinX([second frame]);
    [label setStringValue:@"a considerably longer label text"];
    settle();
    CHECK(NSMinX([second frame]) > before + 40);
    CHECK(NSWidth([label frame]) > 100);
    [stack removeFromSuperview];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        g_host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
        g_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200) styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered defer:NO];
        [g_window setContentView:g_host];

        test_flags_and_relayout();
        test_controls();
        test_stack_remeasures();

        printf("%s\n", g_failures == 0 ? "PASS" : "FAIL");
        return g_failures != 0;
    }
}
