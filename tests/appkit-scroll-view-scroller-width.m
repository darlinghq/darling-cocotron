// Copyright (C) 2026 Lubos Dolezel
//
// NSScrollView tiles its scrollers at the width their control size gives them
// (+[NSScroller scrollerWidthForControlSize:scrollerStyle:]); legacy scrollers
// take that space from the content, overlay scrollers take none and lie over
// the content along its whole length. The expected frames were observed on
// macOS 10.14.4 (black-box; 26.7.3 uses other scroller widths).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expectRect(const char *what, NSRect r, NSRect expected) {
    if (!NSEqualRects(r, expected)) {
        fprintf(stderr, "FAIL %s: {%g,%g,%g,%g}, expected {%g,%g,%g,%g}\n", what, r.origin.x, r.origin.y,
                r.size.width, r.size.height, expected.origin.x, expected.origin.y, expected.size.width,
                expected.size.height);
        failures++;
    }
}

static void expectSize(const char *what, NSSize s, NSSize expected) {
    if (!NSEqualSizes(s, expected)) {
        fprintf(stderr, "FAIL %s: {%g,%g}, expected {%g,%g}\n", what, s.width, s.height, expected.width,
                expected.height);
        failures++;
    }
}

static NSScrollView *makeScrollView(NSScrollerStyle style, NSControlSize size, NSBorderType border) {
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 150)] autorelease];
    [sv setBorderType: border];
    [sv setHasVerticalScroller: YES];
    [sv setHasHorizontalScroller: YES];
    [sv setScrollerStyle: style];
    [[sv verticalScroller] setControlSize: size];
    [[sv horizontalScroller] setControlSize: size];
    [sv setDocumentView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 500, 500)] autorelease]];
    [sv tile];
    return sv;
}

static void test_tiling(void) {
    static const struct {
        NSScrollerStyle style;
        NSControlSize size;
        NSBorderType border;
        NSRect vertical, horizontal, clip;
    } cases[] = {
        { NSScrollerStyleLegacy, NSControlSizeRegular, NSNoBorder, { { 185, 0 }, { 15, 135 } }, { { 0, 135 }, { 185, 15 } }, { { 0, 0 }, { 185, 135 } } },
        { NSScrollerStyleLegacy, NSControlSizeRegular, NSBezelBorder, { { 184, 1 }, { 15, 133 } }, { { 1, 134 }, { 183, 15 } }, { { 1, 1 }, { 183, 133 } } },
        { NSScrollerStyleLegacy, NSControlSizeSmall, NSNoBorder, { { 189, 0 }, { 11, 139 } }, { { 0, 139 }, { 189, 11 } }, { { 0, 0 }, { 189, 139 } } },
        { NSScrollerStyleLegacy, NSControlSizeSmall, NSBezelBorder, { { 188, 1 }, { 11, 137 } }, { { 1, 138 }, { 187, 11 } }, { { 1, 1 }, { 187, 137 } } },
        { NSScrollerStyleLegacy, NSControlSizeMini, NSNoBorder, { { 189, 0 }, { 11, 139 } }, { { 0, 139 }, { 189, 11 } }, { { 0, 0 }, { 189, 139 } } },
        { NSScrollerStyleOverlay, NSControlSizeRegular, NSNoBorder, { { 184, 0 }, { 16, 150 } }, { { 0, 134 }, { 200, 16 } }, { { 0, 0 }, { 200, 150 } } },
        { NSScrollerStyleOverlay, NSControlSizeRegular, NSBezelBorder, { { 183, 1 }, { 16, 148 } }, { { 1, 133 }, { 198, 16 } }, { { 1, 1 }, { 198, 148 } } },
        { NSScrollerStyleOverlay, NSControlSizeSmall, NSNoBorder, { { 186, 0 }, { 14, 150 } }, { { 0, 136 }, { 200, 14 } }, { { 0, 0 }, { 200, 150 } } },
        { NSScrollerStyleOverlay, NSControlSizeMini, NSBezelBorder, { { 185, 1 }, { 14, 148 } }, { { 1, 135 }, { 198, 14 } }, { { 1, 1 }, { 198, 148 } } },
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        NSScrollView *sv = makeScrollView(cases[i].style, cases[i].size, cases[i].border);
        char what[96];
        snprintf(what, sizeof what, "style %ld size %ld border %ld vertical", (long) cases[i].style,
                 (long) cases[i].size, (long) cases[i].border);
        expectRect(what, [[sv verticalScroller] frame], cases[i].vertical);
        snprintf(what, sizeof what, "style %ld size %ld border %ld horizontal", (long) cases[i].style,
                 (long) cases[i].size, (long) cases[i].border);
        expectRect(what, [[sv horizontalScroller] frame], cases[i].horizontal);
        snprintf(what, sizeof what, "style %ld size %ld border %ld clip", (long) cases[i].style,
                 (long) cases[i].size, (long) cases[i].border);
        expectRect(what, [[sv contentView] frame], cases[i].clip);
        snprintf(what, sizeof what, "style %ld size %ld border %ld contentSize", (long) cases[i].style,
                 (long) cases[i].size, (long) cases[i].border);
        expectSize(what, [sv contentSize], cases[i].clip.size);
    }
}

static void test_class_sizes(void) {
    Class scroller = [NSScroller class];
    expectSize("contentSizeForFrameSize legacy regular",
               [NSScrollView contentSizeForFrameSize: NSMakeSize(200, 150) horizontalScrollerClass: scroller
                               verticalScrollerClass: scroller borderType: NSNoBorder
                                         controlSize: NSControlSizeRegular scrollerStyle: NSScrollerStyleLegacy],
               NSMakeSize(185, 135));
    expectSize("contentSizeForFrameSize legacy small",
               [NSScrollView contentSizeForFrameSize: NSMakeSize(200, 150) horizontalScrollerClass: scroller
                               verticalScrollerClass: scroller borderType: NSNoBorder
                                         controlSize: NSControlSizeSmall scrollerStyle: NSScrollerStyleLegacy],
               NSMakeSize(189, 139));
    expectSize("contentSizeForFrameSize overlay",
               [NSScrollView contentSizeForFrameSize: NSMakeSize(200, 150) horizontalScrollerClass: scroller
                               verticalScrollerClass: scroller borderType: NSNoBorder
                                         controlSize: NSControlSizeRegular scrollerStyle: NSScrollerStyleOverlay],
               NSMakeSize(200, 150));
    expectSize("frameSizeForContentSize legacy mini bezel",
               [NSScrollView frameSizeForContentSize: NSMakeSize(200, 150) horizontalScrollerClass: scroller
                               verticalScrollerClass: scroller borderType: NSBezelBorder
                                         controlSize: NSControlSizeMini scrollerStyle: NSScrollerStyleLegacy],
               NSMakeSize(213, 163));
    expectSize("frameSizeForContentSize overlay bezel",
               [NSScrollView frameSizeForContentSize: NSMakeSize(200, 150) horizontalScrollerClass: scroller
                               verticalScrollerClass: scroller borderType: NSBezelBorder
                                         controlSize: NSControlSizeRegular scrollerStyle: NSScrollerStyleOverlay],
               NSMakeSize(202, 152));
}

static NSTableView *tableIn(NSScrollView *sv) {
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    for (int i = 0; i < 2; i++) {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]]
                autorelease];
        [column setWidth: 100];
        [table addTableColumn: column];
    }
    [sv setDocumentView: table];
    return table;
}

// The header is as wide as the space the vertical scroller leaves.
static void test_header_width(void) {
    NSControlSize sizes[] = { NSControlSizeRegular, NSControlSizeSmall };
    CGFloat widths[] = { 315, 319 };
    for (int i = 0; i < 2; i++) {
        NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 330, 200)] autorelease];
        [sv setHasVerticalScroller: YES];
        [sv setScrollerStyle: NSScrollerStyleLegacy];
        [[sv verticalScroller] setControlSize: sizes[i]];
        NSTableView *table = tableIn(sv);
        [sv tile];
        expectRect(i ? "header clip, small scroller" : "header clip, regular scroller",
                   [[[table headerView] superview] frame], NSMakeRect(0, 0, widths[i], 17));
    }
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 330, 200)] autorelease];
    [sv setScrollerStyle: NSScrollerStyleLegacy];
    NSTableView *table = tableIn(sv);
    [sv tile];
    expectRect("header clip, no vertical scroller", [[[table headerView] superview] frame],
               NSMakeRect(0, 0, 330, 17));
}

// QUIRK: the corner view is one point wider than the vertical scroller. See
// -[NSScrollView cornerViewFrame].
static void test_quirk_corner_view_frame(void) {
    NSControlSize sizes[] = { NSControlSizeRegular, NSControlSizeSmall, NSControlSizeMini };
    NSRect expected[] = { { { 315, 0 }, { 16, 17 } }, { { 319, 0 }, { 12, 17 } }, { { 319, 0 }, { 12, 17 } } };
    for (int i = 0; i < 3; i++) {
        NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 330, 200)] autorelease];
        [sv setHasVerticalScroller: YES];
        [sv setScrollerStyle: NSScrollerStyleLegacy];
        [[sv verticalScroller] setControlSize: sizes[i]];
        NSTableView *table = tableIn(sv);
        [sv tile];
        char what[64];
        snprintf(what, sizeof what, "legacy corner view, control size %d", (int) sizes[i]);
        expectRect(what, [[table cornerView] frame], expected[i]);
    }
    // a corner view the application sets is kept with overlay scrollers
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSView *corner = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 30, 30)] autorelease];
    [table setCornerView: corner];
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 330, 200)] autorelease];
    [sv setHasVerticalScroller: YES];
    [sv setScrollerStyle: NSScrollerStyleOverlay];
    [sv setDocumentView: table];
    [sv tile];
    expectRect("custom corner view, overlay", [corner frame], NSMakeRect(314, 0, 17, 17));
    if ([corner superview] != sv) {
        fprintf(stderr, "FAIL custom corner view is not in the scroll view\n");
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_tiling();
        test_class_sizes();
        test_header_width();
        test_quirk_corner_view_frame();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
