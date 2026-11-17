// Copyright (C) 2026 Lubos Dolezel
//
// NSScrollView magnification as macOS 10.14.4 and 26.7.3 do it (both gave the same results in a probe of every
// value below, on x86_64).
//  - Defaults: magnification 1, minimum 0.25, maximum 4, allowsMagnification NO.
//  - setMagnification: clamps to the range, keeps the middle of the visible area in place, and acts on the
//    content view's bounds (frame size / magnification) only: the document view frame is untouched.
//    allowsMagnification only governs the user's gestures.
//  - setMagnification:centeredAtPoint: keeps the document point where it is on screen (the point is in
//    document view coordinates), clamped to the document.
//  - magnifyToFitRect: picks the magnification that fits the rect, clamped, and puts the rect in the middle.
//  - Resizing the scroll view keeps the magnification, and the scrollers follow the visible area.
//  - Programmatic changes post no live-magnify notifications.
//  - test_quirk_min_max_range: the minimum is raised to 0.0001, a minimum above the maximum or a maximum below
//    the minimum raises NSInvalidArgumentException, and a new range does not re-clamp the magnification.
//  - test_quirk_fit_rect_origin: magnifyToFitRect: rounds the bounds origin down to whole units.
// Build: clang -framework AppKit appkit-scroll-view-magnification.m
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

// Declared here too so the calls are typed on SDKs that lack them.
@interface NSScrollView (MagnificationTest)
- (void)setMagnification:(CGFloat)magnification centeredAtPoint:(NSPoint)point;
- (void)magnifyToFitRect:(NSRect)rect;
@end

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define NEAR(a, b) (fabs((double)(a) - (double)(b)) < 0.001)
#define CHECK_BOUNDS(sv, ex, ey, ew, eh) do { NSRect b_ = [[sv contentView] bounds]; \
    if (!(NEAR(b_.origin.x, ex) && NEAR(b_.origin.y, ey) && NEAR(b_.size.width, ew) && NEAR(b_.size.height, eh))) { \
        fprintf(stderr, "FAIL line %d: bounds %g,%g %gx%g, expected %g,%g %gx%g\n", __LINE__, b_.origin.x, \
                b_.origin.y, b_.size.width, b_.size.height, (double)(ex), (double)(ey), (double)(ew), (double)(eh)); \
        failures++; } } while (0)

static int boundsChanges, liveMagnifyNotes;

@interface Counter : NSObject
@end
@implementation Counter
- (void)bounds:(NSNotification *)n { boundsChanges++; }
- (void)live:(NSNotification *)n { liveMagnifyNotes++; }
@end

static NSView *document;

// 200x100 scroll view without scrollers (so the content view fills it) over a 1000x800 document view.
static NSScrollView *makeScrollView(void) {
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    [sv setHasVerticalScroller:NO];
    [sv setHasHorizontalScroller:NO];
    document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 800)];
    [sv setDocumentView:document];
    return sv;
}

static BOOL raisesInvalidArgument(void (^block)(void)) {
    @try {
        block();
    } @catch (NSException *e) {
        return [[e name] isEqualToString:NSInvalidArgumentException];
    }
    return NO;
}

static void test_defaults(void) {
    NSScrollView *sv = makeScrollView();
    CHECK([sv magnification] == 1.0);
    CHECK([sv minMagnification] == 0.25);
    CHECK([sv maxMagnification] == 4.0);
    CHECK(![sv allowsMagnification]);
    CHECK_BOUNDS(sv, 0, 0, 200, 100);
    NSScrollView *bare = [[NSScrollView alloc] init];
    CHECK([bare magnification] == 1.0 && [bare minMagnification] == 0.25 && [bare maxMagnification] == 4.0);
}

static void test_set_magnification(void) {
    NSScrollView *sv = makeScrollView();
    Counter *counter = [Counter new];
    [[NSNotificationCenter defaultCenter] addObserver:counter selector:@selector(bounds:)
                                                 name:NSViewBoundsDidChangeNotification object:[sv contentView]];
    [[NSNotificationCenter defaultCenter] addObserver:counter selector:@selector(live:)
                                                 name:NSScrollViewWillStartLiveMagnifyNotification object:sv];
    [[NSNotificationCenter defaultCenter] addObserver:counter selector:@selector(live:)
                                                 name:NSScrollViewDidEndLiveMagnifyNotification object:sv];
    boundsChanges = liveMagnifyNotes = 0;

    [sv setMagnification:2];
    CHECK([sv magnification] == 2.0);
    CHECK_BOUNDS(sv, 50, 25, 100, 50);
    CHECK(NSEqualRects([document frame], NSMakeRect(0, 0, 1000, 800)));
    CHECK(NSEqualRects([sv documentVisibleRect], NSMakeRect(50, 25, 100, 50)));
    CHECK(NSEqualRects([[sv contentView] frame], NSMakeRect(0, 0, 200, 100)));
    CHECK(boundsChanges >= 1);
    CHECK(liveMagnifyNotes == 0);

    [sv setMagnification:0.5];
    CHECK_BOUNDS(sv, 0, 0, 400, 200);
    CHECK(NSEqualRects([sv documentVisibleRect], NSMakeRect(0, 0, 400, 200)));

    [sv setMagnification:100];
    CHECK([sv magnification] == 4.0);
    CHECK_BOUNDS(sv, 175, 87.5, 50, 25);
    [sv setMagnification:0.001];
    CHECK([sv magnification] == 0.25);
    CHECK_BOUNDS(sv, 0, 0, 800, 400);
    [sv setMagnification:0];
    CHECK([sv magnification] == 0.25);
    [sv setMagnification:-1];
    CHECK([sv magnification] == 0.25);
    [sv setMagnification:1];
    CHECK_BOUNDS(sv, 300, 150, 200, 100);

    // The middle of the visible area stays put after scrolling, too.
    [[sv contentView] scrollToPoint:NSMakePoint(300, 200)];
    [sv reflectScrolledClipView:[sv contentView]];
    [sv setMagnification:2];
    CHECK_BOUNDS(sv, 350, 225, 100, 50);

    // Not re-applied when the value is the same.
    boundsChanges = 0;
    [sv setMagnification:2];
    CHECK(boundsChanges == 0);

    // A document smaller than the visible area sits at the origin.
    [sv setMagnification:1];
    [document setFrameSize:NSMakeSize(100, 50)];
    [sv setMagnification:2];
    CHECK_BOUNDS(sv, 0, 0, 100, 50);
    [[NSNotificationCenter defaultCenter] removeObserver:counter];
}

static void test_allows_magnification_is_for_gestures(void) {
    NSScrollView *sv = makeScrollView();
    [sv setAllowsMagnification:NO];
    [sv setMagnification:2];
    CHECK([sv magnification] == 2.0);
    CHECK_BOUNDS(sv, 50, 25, 100, 50);
    CHECK(![sv allowsMagnification]);
    [sv setMagnification:1];
    CHECK([sv magnification] == 1.0);
}

static void test_quirk_min_max_range(void) {
    NSScrollView *sv = makeScrollView();
    [sv setMaxMagnification:3];
    [sv setMagnification:5];
    CHECK([sv magnification] == 3.0);
    [sv setMinMagnification:0.5];
    [sv setMagnification:0.1];
    CHECK([sv magnification] == 0.5);

    // a new range does not re-clamp the current magnification
    [sv setMaxMagnification:4];
    [sv setMagnification:2];
    [sv setMinMagnification:3];
    CHECK([sv minMagnification] == 3.0 && [sv magnification] == 2.0);
    [sv setMinMagnification:1];
    [sv setMaxMagnification:1.5];
    CHECK([sv maxMagnification] == 1.5 && [sv magnification] == 2.0);
    [sv setMagnification:2];
    CHECK([sv magnification] == 1.5);

    // the range must stay ordered
    CHECK(raisesInvalidArgument(^{ [sv setMaxMagnification:0.5]; }));
    CHECK(raisesInvalidArgument(^{ [sv setMinMagnification:2]; }));
    CHECK([sv minMagnification] == 1.0 && [sv maxMagnification] == 1.5);
    [sv setMinMagnification:1.5];
    CHECK([sv minMagnification] == 1.5 && [sv maxMagnification] == 1.5);

    // minimum floor
    [sv setMinMagnification:0];
    CHECK(NEAR([sv minMagnification], 0.0001));
    [sv setMinMagnification:-1];
    CHECK(NEAR([sv minMagnification], 0.0001));
    [sv setMinMagnification:0.00001];
    CHECK(NEAR([sv minMagnification], 0.0001));
    CHECK(raisesInvalidArgument(^{ [sv setMaxMagnification:0]; }));
    CHECK(raisesInvalidArgument(^{ [sv setMaxMagnification:-1]; }));
    [sv setMaxMagnification:1e9];
    [sv setMagnification:1e8];
    CHECK([sv magnification] == 1e8);
}

static void test_centered_at_point(void) {
    NSScrollView *sv = makeScrollView();
    [sv setMagnification:2 centeredAtPoint:NSMakePoint(0, 0)];
    CHECK_BOUNDS(sv, 0, 0, 100, 50);
    // the same magnification again does not move anything
    [sv setMagnification:2 centeredAtPoint:NSMakePoint(400, 250)];
    CHECK_BOUNDS(sv, 0, 0, 100, 50);
    // (400, 250) was at 400 / 200 of the way along the view: it stays there
    [sv setMagnification:4 centeredAtPoint:NSMakePoint(400, 250)];
    CHECK_BOUNDS(sv, 200, 125, 50, 25);
    // zooming out about it runs into the document's edge: clamped
    [sv setMagnification:1 centeredAtPoint:NSMakePoint(400, 250)];
    CHECK_BOUNDS(sv, 0, 0, 200, 100);
    // out of range values are clamped
    [sv setMagnification:100 centeredAtPoint:NSMakePoint(400, 250)];
    CHECK([sv magnification] == 4.0);
    CHECK_BOUNDS(sv, 300, 187.5, 50, 25);
    [sv setMagnification:0.01 centeredAtPoint:NSMakePoint(400, 250)];
    CHECK([sv magnification] == 0.25);
    CHECK_BOUNDS(sv, 0, 0, 800, 400);
    // a point outside the document is still clamped to the document
    [sv setMagnification:3 centeredAtPoint:NSMakePoint(-50, -50)];
    CHECK_BOUNDS(sv, 0, 0, 200.0 / 3, 100.0 / 3);
    // fractions are kept
    [sv setMagnification:1];
    [sv setMagnification:2.5 centeredAtPoint:NSMakePoint(500.5, 400.5)];
    CHECK([sv magnification] == 2.5);
    CHECK(!NEAR([[sv contentView] bounds].origin.x, floor([[sv contentView] bounds].origin.x)));
}

static void test_magnify_to_fit_rect(void) {
    NSScrollView *sv = makeScrollView();
    [sv magnifyToFitRect:NSMakeRect(100, 100, 100, 50)];
    CHECK([sv magnification] == 2.0);
    CHECK_BOUNDS(sv, 100, 100, 100, 50);
    // limited by the width, centred on the other axis
    [sv magnifyToFitRect:NSMakeRect(400, 300, 200, 20)];
    CHECK([sv magnification] == 1.0);
    CHECK_BOUNDS(sv, 400, 260, 200, 100);
    // clamped to the minimum, the rect is centred beyond the document
    [sv magnifyToFitRect:NSMakeRect(0, 0, 1000, 800)];
    CHECK([sv magnification] == 0.25);
    CHECK_BOUNDS(sv, 100, 200, 800, 400);
    [sv magnifyToFitRect:NSMakeRect(0, 0, 5000, 5000)];
    CHECK([sv magnification] == 0.25);
    // clamped to the maximum
    [sv magnifyToFitRect:NSMakeRect(500, 400, 10, 10)];
    CHECK([sv magnification] == 4.0);
    CHECK_BOUNDS(sv, 480, 392, 50, 25);
    [sv magnifyToFitRect:NSMakeRect(400, 300, 0, 0)];
    CHECK([sv magnification] == 4.0);
    CHECK_BOUNDS(sv, 375, 287, 50, 25);
    // the content view's frame and the document are unchanged
    CHECK(NSEqualRects([[sv contentView] frame], NSMakeRect(0, 0, 200, 100)));
    CHECK(NSEqualRects([document frame], NSMakeRect(0, 0, 1000, 800)));
}

static void test_quirk_fit_rect_origin(void) {
    NSScrollView *sv = makeScrollView();
    // 100x50 fits at exactly 2: the origin is the rect's, and the fraction is dropped (not rounded)
    [sv magnifyToFitRect:NSMakeRect(100.25, 100.25, 100, 50)];
    CHECK_BOUNDS(sv, 100, 100, 100, 50);
    [sv magnifyToFitRect:NSMakeRect(100.75, 100.75, 100, 50)];
    CHECK_BOUNDS(sv, 100, 100, 100, 50);
    // 70x40 fits at exactly 2.5 (bounds 80x40): the origin is 95.5, 100.5
    [sv magnifyToFitRect:NSMakeRect(100.5, 100.5, 70, 40)];
    CHECK_BOUNDS(sv, 95, 100, 80, 40);
}

static void test_resize_keeps_magnification(void) {
    NSScrollView *sv = makeScrollView();
    [sv setMagnification:2];
    [sv setFrameSize:NSMakeSize(300, 200)];
    CHECK([sv magnification] == 2.0);
    NSRect clip = [[sv contentView] frame], b = [[sv contentView] bounds];
    CHECK(NEAR(b.size.width, clip.size.width / 2) && NEAR(b.size.height, clip.size.height / 2));
    [sv tile];
    clip = [[sv contentView] frame];
    b = [[sv contentView] bounds];
    CHECK([sv magnification] == 2.0);
    CHECK(NEAR(b.size.width, clip.size.width / 2) && NEAR(b.size.height, clip.size.height / 2));
    CHECK(NSEqualRects([document frame], NSMakeRect(0, 0, 1000, 800)));
    [sv setFrameSize:NSMakeSize(200, 100)];
    CHECK([sv magnification] == 2.0);
    b = [[sv contentView] bounds];
    clip = [[sv contentView] frame];
    CHECK(NEAR(b.size.width, clip.size.width / 2));
}

static void test_scrollers_follow_magnification(void) {
    NSScrollView *sv = makeScrollView();
    [sv setHasVerticalScroller:YES];
    [sv setHasHorizontalScroller:YES];
    [sv tile];
    [sv setMagnification:2];
    NSRect b = [[sv contentView] bounds];
    CHECK(NEAR([[sv verticalScroller] knobProportion], b.size.height / 800));
    CHECK(NEAR([[sv horizontalScroller] knobProportion], b.size.width / 1000));
    // scrolling with the scroller's target still works while magnified
    [sv setMagnification:2];
    [[sv contentView] scrollToPoint:NSMakePoint(400, 300)];
    [sv reflectScrolledClipView:[sv contentView]];
    CHECK(NEAR([[sv horizontalScroller] doubleValue], 400.0 / (1000 - [[sv contentView] bounds].size.width)));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_defaults();
        test_set_magnification();
        test_allows_magnification_is_for_gestures();
        test_quirk_min_max_range();
        test_centered_at_point();
        test_magnify_to_fit_rect();
        test_quirk_fit_rect_origin();
        test_resize_keeps_magnification();
        test_scrollers_follow_magnification();
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("ok");
    return 0;
}
