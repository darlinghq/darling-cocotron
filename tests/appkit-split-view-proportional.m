// Copyright (C) 2026 Lubos Dolezel
//
// -[NSSplitView adjustSubviews] and split view resizing keep the proportions of
// the subviews' lengths, and -addSubview: leaves the frames alone. The expected
// frames were observed on macOS 10.14.4 and 26.7.3 (black-box, both agree).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static NSSplitView *makeSplit(BOOL vertical, NSSplitViewDividerStyle style, int n, const CGFloat *lengths) {
    NSSplitView *split = [[[NSSplitView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    [split setVertical: vertical];
    [split setDividerStyle: style];
    for (int i = 0; i < n; i++) {
        NSRect frame = vertical ? NSMakeRect(0, 0, lengths[i], 100) : NSMakeRect(0, 0, 100, lengths[i]);
        [split addSubview: [[[NSView alloc] initWithFrame: frame] autorelease]];
    }
    return split;
}

// expected: origin and length along the split axis of each subview
static void expect(const char *what, NSSplitView *split, int n, const CGFloat *expected) {
    BOOL vertical = [split isVertical];
    for (int i = 0; i < n; i++) {
        NSRect f = [[[split subviews] objectAtIndex: i] frame];
        CGFloat origin = vertical ? f.origin.x : f.origin.y, length = vertical ? f.size.width : f.size.height;
        CGFloat across = vertical ? f.size.height : f.size.width;
        if (origin != expected[2 * i] || length != expected[2 * i + 1] || across != 100) {
            fprintf(stderr, "FAIL %s: subview %d {%g,%g,%g,%g}, expected origin %g length %g\n", what, i,
                    f.origin.x, f.origin.y, f.size.width, f.size.height, expected[2 * i], expected[2 * i + 1]);
            failures++;
        }
    }
}

static void test_add_subview_keeps_frames(void) {
    CGFloat lengths[] = { 40, 40 };
    for (int vertical = 0; vertical < 2; vertical++) {
        NSSplitView *split = makeSplit(vertical, NSSplitViewDividerStyleThick, 2, lengths);
        for (int i = 0; i < 2; i++) {
            NSRect f = [[[split subviews] objectAtIndex: i] frame];
            NSRect expected = vertical ? NSMakeRect(0, 0, 40, 100) : NSMakeRect(0, 0, 100, 40);
            if (!NSEqualRects(f, expected)) {
                fprintf(stderr, "FAIL addSubview: (vertical %d) moved subview %d to {%g,%g,%g,%g}\n", vertical, i,
                        f.origin.x, f.origin.y, f.size.width, f.size.height);
                failures++;
            }
        }
    }
}

// The documented proportional layout: two equal subviews stay (almost) equal.
static void test_proportional(void) {
    CGFloat lengths[] = { 40, 40 };
    for (int vertical = 0; vertical < 2; vertical++) {
        NSSplitView *split = makeSplit(vertical, NSSplitViewDividerStyleThick, 2, lengths);
        [split adjustSubviews];
        expect(vertical ? "thick vertical 40/40" : "thick horizontal 40/40", split, 2,
               (CGFloat[]) { 0, 46, 55, 45 });
        split = makeSplit(vertical, NSSplitViewDividerStyleThin, 2, lengths);
        [split adjustSubviews];
        expect(vertical ? "thin vertical 40/40" : "thin horizontal 40/40", split, 2, (CGFloat[]) { 0, 50, 51, 49 });
        split = makeSplit(vertical, NSSplitViewDividerStylePaneSplitter, 2, lengths);
        [split adjustSubviews];
        expect(vertical ? "pane vertical 40/40" : "pane horizontal 40/40", split, 2, (CGFloat[]) { 0, 45, 55, 45 });
    }
    CGFloat unequal[] = { 30, 50 };
    NSSplitView *split = makeSplit(YES, NSSplitViewDividerStyleThick, 2, unequal);
    [split adjustSubviews];
    expect("thick 30/50", split, 2, (CGFloat[]) { 0, 34, 43, 57 });
    // larger than the split view
    CGFloat large[] = { 200, 100 };
    split = makeSplit(YES, NSSplitViewDividerStyleThin, 2, large);
    [split adjustSubviews];
    expect("thin 200/100", split, 2, (CGFloat[]) { 0, 66, 67, 33 });
    // an empty subview stays empty
    CGFloat empty[] = { 0, 50 };
    split = makeSplit(YES, NSSplitViewDividerStyleThick, 2, empty);
    [split adjustSubviews];
    expect("thick 0/50", split, 2, (CGFloat[]) { 0, 0, 9, 91 });
}

// QUIRK: each subview ends at the running sum of the lengths before it, scaled
// and rounded to the nearest point (half points up). See -[NSSplitView _adjustSubviewLengths].
static void test_quirk_rounding(void) {
    CGFloat three[] = { 30, 30, 30 };
    NSSplitView *split = makeSplit(YES, NSSplitViewDividerStyleThick, 3, three);
    [split adjustSubviews];
    expect("thick 30/30/30", split, 3, (CGFloat[]) { 0, 27, 36, 28, 73, 27 });
    // resizing the split view keeps the proportions
    [split setFrameSize: NSMakeSize(200, 100)];
    expect("thick 30/30/30 at 200", split, 3, (CGFloat[]) { 0, 60, 69, 62, 140, 60 });
    [split setFrameSize: NSMakeSize(77, 100)];
    expect("thick 30/30/30 at 77", split, 3, (CGFloat[]) { 0, 19, 28, 21, 58, 19 });

    CGFloat mixed[] = { 20, 30, 40 };
    split = makeSplit(YES, NSSplitViewDividerStyleThin, 3, mixed);
    [split adjustSubviews];
    expect("thin 20/30/40", split, 3, (CGFloat[]) { 0, 22, 23, 32, 56, 44 });
    CGFloat four[] = { 25, 25, 25, 25 };
    split = makeSplit(YES, NSSplitViewDividerStylePaneSplitter, 4, four);
    [split adjustSubviews];
    expect("pane 25x4", split, 4, (CGFloat[]) { 0, 18, 28, 17, 55, 18, 83, 17 });
    split = makeSplit(YES, NSSplitViewDividerStyleThin, 4, four);
    [split adjustSubviews];
    expect("thin 25x4", split, 4, (CGFloat[]) { 0, 24, 25, 25, 51, 24, 76, 24 });
}

// QUIRK: a hidden subview keeps its frame and its divider, and takes no space.
// See -[NSSplitView _adjustSubviewLengths].
static void test_quirk_hidden_subviews(void) {
    CGFloat mixed[] = { 20, 30, 40 };
    NSSplitView *split = makeSplit(YES, NSSplitViewDividerStyleThin, 3, mixed);
    [[[split subviews] objectAtIndex: 1] setHidden: YES];
    [split adjustSubviews];
    expect("thin 20/30/40, middle hidden", split, 3, (CGFloat[]) { 0, 33, 0, 30, 35, 65 });
    CGFloat three[] = { 30, 30, 30 };
    split = makeSplit(YES, NSSplitViewDividerStyleThin, 3, three);
    [[[split subviews] objectAtIndex: 0] setHidden: YES];
    [split adjustSubviews];
    expect("thin 30x3, first hidden", split, 3, (CGFloat[]) { 0, 30, 1, 49, 51, 49 });
}

// A split view that a window resizes lays out its subviews proportionally.
static void test_window_resize(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    CGFloat lengths[] = { 20, 60 };
    NSSplitView *split = makeSplit(YES, NSSplitViewDividerStyleThick, 2, lengths);
    [split setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [window setContentView: split];
    expect("in window", split, 2, (CGFloat[]) { 0, 20, 0, 60 });
    [window setContentSize: NSMakeSize(200, 100)];
    expect("window 200", split, 2, (CGFloat[]) { 0, 48, 57, 143 });
    [window close];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_add_subview_keeps_frames();
        test_proportional();
        test_quirk_rounding();
        test_quirk_hidden_subviews();
        test_window_resize();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
