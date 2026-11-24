// Build: clang -fobjc-arc -framework AppKit appkit-scrollview-scroll-wheel.m
// Needs a Darling guest with a window system: the scroll view is put in a window, so that the visible
// area of its document view is the one a user sees. Prints PASS and exits 0 on success.
//
// NSScrollView scrollWheel: as the documentation describes the scroll deltas of a scroll wheel event:
//  - scrollingDeltaX/Y are the preferred deltas of a scroll wheel event (deltaY is not meant for them).
//    When hasPreciseScrollingDeltas is NO they count lines, to be multiplied by the height of a line or row;
//    otherwise the view scrolls by the amount itself, in points.
//    https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltay
//    https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas
//  - The line scroll amounts are per axis (horizontalLineScroll, verticalLineScroll).
//    https://developer.apple.com/documentation/appkit/nsscrollview/verticallinescroll
// GUESS: the documentation gives no number of lines for a wheel notch; kLinesPerNotch is the one
// NSScrollView has always used. GUESS: the line scroll amount of an axis is the line height of a
// line-counting event (its page speaks of the scroll arrows), and the amount of a precise event is in
// points of the document view.
// A wheel event (made with mouseEventWithType:...deltaX:deltaY:) is not precise and its scrolling deltas
// are its legacy deltas; a precise event is made through the private method that the window system backends
// use, as tests/appkit-precise-scroll-events.m does.
// On master the precise cases fail (the scroll view uses the legacy deltas, a tenth of the scrolling ones,
// times the line scroll and 3); the wheel cases pass and pin the behaviour that must not change.
// Not tested: the sign of the horizontal axis of a precise event (not documented, and the window system
// backends disagree), and usesPredominantAxisScrolling (the scroll view does not use it).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static const CGFloat kLinesPerNotch = 3; // GUESS, see above.
static const CGFloat kVerticalLine = 7;
static const CGFloat kHorizontalLine = 5;

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define CHECK_ORIGIN(sv, ex, ey) do { NSPoint o_ = [[sv contentView] bounds].origin; \
    if (fabs(o_.x - (ex)) > 1e-6 || fabs(o_.y - (ey)) > 1e-6) { \
        fprintf(stderr, "FAIL line %d: origin %g,%g, expected %g,%g\n", __LINE__, o_.x, o_.y, \
                (double)(ex), (double)(ey)); failures++; } } while (0)

@interface NSEvent_mouse : NSEvent
- (void)_setPreciseScrollingDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY phase:(NSEventPhase)phase;
@end

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSEvent *wheel(CGFloat dx, CGFloat dy) {
    return [NSEvent mouseEventWithType:NSScrollWheel location:NSMakePoint(5, 5) modifierFlags:0 window:nil
                            clickCount:1 deltaX:dx deltaY:dy];
}

static NSEvent *precise(CGFloat dx, CGFloat dy) {
    NSEvent *event = wheel(0, 0);
    [(NSEvent_mouse *)event _setPreciseScrollingDeltaX:dx deltaY:dy phase:NSEventPhaseChanged];
    return event;
}

static NSWindow *window;

// 200x100 scroll view without scrollers (the content view fills it) over a 1000x800 document view, scrolled
// to (100, 200) with different line scroll amounts on the two axes.
static NSScrollView *makeScrollView(BOOL flipped) {
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    [sv setHasVerticalScroller:NO];
    [sv setHasHorizontalScroller:NO];
    [sv setHorizontalLineScroll:kHorizontalLine];
    [sv setVerticalLineScroll:kVerticalLine];
    NSRect frame = NSMakeRect(0, 0, 1000, 800);
    NSView *document = flipped ? [[FlippedView alloc] initWithFrame:frame] : [[NSView alloc] initWithFrame:frame];
    [sv setDocumentView:document];
    [window setContentView:sv];
    [[sv contentView] scrollToPoint:NSMakePoint(100, 200)];
    [sv reflectScrolledClipView:[sv contentView]];
    return sv;
}

static void test_wheel_notches_scroll_lines(void) {
    // A wheel event counts lines of the axis' line scroll amount. Wheel up (deltaY > 0) shows what is above:
    // the smaller y of a flipped document, the larger y of an unflipped one.
    NSScrollView *sv = makeScrollView(YES);
    CHECK_ORIGIN(sv, 100, 200);
    [sv scrollWheel:wheel(0, -1)];
    CHECK_ORIGIN(sv, 100, 200 + kVerticalLine * kLinesPerNotch);
    [sv scrollWheel:wheel(0, 2)];
    CHECK_ORIGIN(sv, 100, 200 - kVerticalLine * kLinesPerNotch);
    [sv scrollWheel:wheel(0, -0.5)];
    CHECK_ORIGIN(sv, 100, 200 - kVerticalLine * kLinesPerNotch * 0.5);

    sv = makeScrollView(NO);
    CHECK_ORIGIN(sv, 100, 200);
    [sv scrollWheel:wheel(0, 1)];
    CHECK_ORIGIN(sv, 100, 200 + kVerticalLine * kLinesPerNotch);
    [sv scrollWheel:wheel(0, -2)];
    CHECK_ORIGIN(sv, 100, 200 - kVerticalLine * kLinesPerNotch);

    // The horizontal amount uses the horizontal line scroll.
    sv = makeScrollView(YES);
    [sv scrollWheel:wheel(2, 0)];
    CHECK_ORIGIN(sv, 100 + 2 * kHorizontalLine * kLinesPerNotch, 200);
    [sv scrollWheel:wheel(-1, 0)];
    CHECK_ORIGIN(sv, 100 + kHorizontalLine * kLinesPerNotch, 200);

    // Both axes in one event scroll both, for a wheel.
    sv = makeScrollView(YES);
    [sv scrollWheel:wheel(1, -1)];
    CHECK_ORIGIN(sv, 100 + kHorizontalLine * kLinesPerNotch, 200 + kVerticalLine * kLinesPerNotch);

    // A wheel event sent to the document view reaches the enclosing scroll view.
    sv = makeScrollView(YES);
    [[sv documentView] scrollWheel:wheel(0, -1)];
    CHECK_ORIGIN(sv, 100, 200 + kVerticalLine * kLinesPerNotch);
}

static void test_wheel_clamps(void) {
    NSScrollView *sv = makeScrollView(YES);
    [sv scrollWheel:wheel(0, 1000)];
    CHECK_ORIGIN(sv, 100, 0);
    [sv scrollWheel:wheel(0, -1000)];
    CHECK_ORIGIN(sv, 100, 700);
    [sv scrollWheel:wheel(1000, 0)];
    CHECK_ORIGIN(sv, 800, 700);
    [sv scrollWheel:wheel(-1000, 0)];
    CHECK_ORIGIN(sv, 0, 700);

    sv = makeScrollView(NO);
    [sv scrollWheel:wheel(0, 1000)];
    CHECK_ORIGIN(sv, 100, 700);
    [sv scrollWheel:wheel(0, -1000)];
    CHECK_ORIGIN(sv, 100, 0);
}

static void test_precise_scrolls_points(void) {
    // The amount is in points whatever the line scroll amounts are, and has the sign of a wheel event's
    // (a positive delta shows what is above).
    for (int pass = 0; pass < 2; pass++) {
        NSScrollView *sv = makeScrollView(YES);
        if (pass == 1)
            [sv setLineScroll:1];
        [sv scrollWheel:precise(0, -30)];
        CHECK_ORIGIN(sv, 100, 230);
        [sv scrollWheel:precise(0, 12.5)];
        CHECK_ORIGIN(sv, 100, 217.5);
    }

    NSScrollView *sv = makeScrollView(NO);
    [sv scrollWheel:precise(0, 30)];
    CHECK_ORIGIN(sv, 100, 230);
    [sv scrollWheel:precise(0, -5)];
    CHECK_ORIGIN(sv, 100, 225);

    // Clamped like a wheel event.
    sv = makeScrollView(YES);
    [sv scrollWheel:precise(0, 5000)];
    CHECK_ORIGIN(sv, 100, 0);
    [sv scrollWheel:precise(0, -5000)];
    CHECK_ORIGIN(sv, 100, 700);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered defer:NO];
        [window setReleasedWhenClosed:NO];
        test_wheel_notches_scroll_lines();
        test_wheel_clamps();
        test_precise_scrolls_points();
    }
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    puts("PASS");
    return 0;
}
