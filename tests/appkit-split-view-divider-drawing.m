// Copyright (C) 2026 Lubos Dolezel
//
// How NSSplitView draws its dividers, as macOS 10.14.4 does in the light appearance. Split views of each divider
// style are drawn over white, side by side (vertical) and stacked (horizontal), 100 x 100 points, with two
// subviews:
//  - dividerColor is clear for the thick and pane splitter styles, and a black of alpha 0.098 for the thin style;
//  - test_quirk_dimple: a thick divider (9 points) shows only a dimple over the background: a 6 point disc in
//    its middle, a gray of about 0.86 inside and darker at its rim, darkest (about 0.73) at the top;
//  - test_quirk_pane_splitter: a pane splitter (10 points) is opaque: a gray line of 0.835 along its left (or
//    bottom) edge and one of 0.851 along its right (or top) edge, a near-white gradient between them, and
//    the same dimple;
//  - a thin divider is a line of about 0.90 over white;
//  - test_quirk_divider_color: a subclass's dividerColor fills a thick divider (under the dimple) and a thin
//    one, but not a pane splitter.
// The divider is put where -adjustSubviews puts it on 10.14.4 (46, 50 and 45 points for the thick, thin and
// pane splitter styles) with -setPosition:ofDividerAtIndex:. Values are from
// mac-probes/aqua-scroller-divider.m and -mixed.m run on 10.14.4; the test passes there.
// Build: clang -framework AppKit appkit-split-view-divider-drawing.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface WhiteView : NSView
@end
@implementation WhiteView
- (void) drawRect: (NSRect) rect {
    [[NSColor whiteColor] setFill];
    NSRectFill(rect);
}
@end

@interface RedSplitView : NSSplitView
@end
@implementation RedSplitView
- (NSColor *) dividerColor {
    return [NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1];
}
@end

static NSSplitView *makeSplit(Class cls, NSSplitViewDividerStyle style, BOOL vertical) {
    NSSplitView *split = [[cls alloc] initWithFrame:NSMakeRect(10, 10, 100, 100)];
    [split setVertical:vertical];
    [split setDividerStyle:style];
    for (int i = 0; i < 2; i++)
        [split addSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)]];
    [split adjustSubviews];
    // the divider where macOS 10.14.4 puts it for two 40 point subviews after -adjustSubviews
    [split setPosition:style == NSSplitViewDividerStyleThin ? 50 : style == NSSplitViewDividerStyleThick ? 46 : 45
      ofDividerAtIndex:0];
    return split;
}

// Draws the split view in a white 120 x 120 view; pixel (x, y) of the result is x, y points from the top left.
static NSBitmapImageRep *render(NSSplitView *split) {
    NSView *host = [[WhiteView alloc] initWithFrame:NSMakeRect(0, 0, 120, 120)];
    [host addSubview:split];
    NSWindow *w = [[NSWindow alloc] initWithContentRect:[host frame] styleMask:NSWindowStyleMaskTitled
            backing:NSBackingStoreBuffered defer:NO];
    [w setContentView:host];
    NSBitmapImageRep *rep = [host bitmapImageRepForCachingDisplayInRect:[host bounds]];
    [host cacheDisplayInRect:[host bounds] toBitmapImageRep:rep];
    return rep;
}

static NSColor *rgb(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    return [[rep colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
}

static CGFloat gray(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSColor *c = rgb(rep, x, y);
    return ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3;
}

#define NEAR(v, want, tol) (fabs((v) - (want)) < (tol))

// Checks the dimple whose top left pixel is (x, y): a 6 x 6 disc, nothing around it.
static void checkDimple(NSBitmapImageRep *rep, NSInteger x, NSInteger y, CGFloat background) {
    CHECK(NEAR(gray(rep, x + 2, y + 2), 0.86, 0.05));   // inside
    CHECK(NEAR(gray(rep, x + 3, y + 3), 0.86, 0.05));
    CHECK(NEAR(gray(rep, x + 2, y), 0.73, 0.06));       // the top of the rim
    CHECK(NEAR(gray(rep, x, y + 2), 0.78, 0.06));       // its sides
    CHECK(NEAR(gray(rep, x + 5, y + 3), 0.79, 0.06));
    CHECK(gray(rep, x + 2, y + 5) < background - 0.08); // its bottom
    CHECK(gray(rep, x, y) > background - 0.05);         // the corners of the square stay light
    CHECK(gray(rep, x + 5, y + 5) > background - 0.05);
    CHECK(NEAR(gray(rep, x + 2, y - 1), background, 0.03));   // nothing outside it
    CHECK(NEAR(gray(rep, x + 2, y + 6), background, 0.03));
    CHECK(NEAR(gray(rep, x - 1, y + 2), background, 0.03));
    CHECK(NEAR(gray(rep, x + 6, y + 2), background, 0.03));
}

static void test_divider_colors(void) {
    NSColor *thick = [[makeSplit([NSSplitView class], NSSplitViewDividerStyleThick, YES) dividerColor]
            colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSColor *pane = [[makeSplit([NSSplitView class], NSSplitViewDividerStylePaneSplitter, YES) dividerColor]
            colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSColor *thin = [[makeSplit([NSSplitView class], NSSplitViewDividerStyleThin, YES) dividerColor]
            colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

    CHECK([thick alphaComponent] == 0);
    CHECK([pane alphaComponent] == 0);
    CHECK(NEAR([thin alphaComponent], 0.098, 0.02) && [thin redComponent] < 0.05);
}

static void test_quirk_dimple(void) {
    // side by side: the divider is x 56..64 in the white view; the dimple is x 57..62, y 57..62
    NSBitmapImageRep *rep = render(makeSplit([NSSplitView class], NSSplitViewDividerStyleThick, YES));
    checkDimple(rep, 57, 57, 1);
    CHECK(NEAR(gray(rep, 60, 20), 1, 0.02));            // the divider shows the white background
    CHECK(NEAR(gray(rep, 56, 60), 1, 0.02));
    CHECK(NEAR(gray(rep, 64, 60), 1, 0.02));
    // stacked: the divider is y 56..64; the dimple is x 57..62, y 58..63
    rep = render(makeSplit([NSSplitView class], NSSplitViewDividerStyleThick, NO));
    checkDimple(rep, 57, 58, 1);
    CHECK(NEAR(gray(rep, 20, 60), 1, 0.02));
}

static void test_quirk_pane_splitter(void) {
    // side by side: the divider is x 55..64
    NSBitmapImageRep *rep = render(makeSplit([NSSplitView class], NSSplitViewDividerStylePaneSplitter, YES));
    CHECK(NEAR(gray(rep, 55, 20), 0.835, 0.03));
    CHECK(NEAR(gray(rep, 64, 20), 0.851, 0.03));
    CHECK(NEAR(gray(rep, 56, 20), 0.984, 0.012));
    CHECK(NEAR(gray(rep, 63, 20), 1.0, 0.012));
    CHECK(gray(rep, 56, 20) < gray(rep, 63, 20));
    CHECK(NEAR(gray(rep, 54, 20), 1, 0.02) && NEAR(gray(rep, 65, 20), 1, 0.02));
    checkDimple(rep, 57, 57, 0.99);
    // stacked: the divider is y 55..64, the lighter line at the top
    rep = render(makeSplit([NSSplitView class], NSSplitViewDividerStylePaneSplitter, NO));
    CHECK(NEAR(gray(rep, 20, 55), 0.851, 0.03));
    CHECK(NEAR(gray(rep, 20, 64), 0.835, 0.03));
    CHECK(NEAR(gray(rep, 20, 56), 1.0, 0.012));
    CHECK(NEAR(gray(rep, 20, 63), 0.984, 0.012));
    checkDimple(rep, 57, 57, 0.99);
}

static void test_thin_line(void) {
    NSBitmapImageRep *rep = render(makeSplit([NSSplitView class], NSSplitViewDividerStyleThin, YES));
    // side by side: the line is x 60
    CHECK(NEAR(gray(rep, 60, 20), 0.90, 0.03));
    CHECK(NEAR(gray(rep, 60, 60), 0.90, 0.03));
    CHECK(NEAR(gray(rep, 59, 20), 1, 0.02) && NEAR(gray(rep, 61, 20), 1, 0.02));
}

static void test_quirk_divider_color(void) {
    NSBitmapImageRep *rep = render(makeSplit([RedSplitView class], NSSplitViewDividerStyleThick, YES));
    NSColor *c = rgb(rep, 60, 20);
    CHECK([c redComponent] > 0.95 && [c greenComponent] < 0.05);
    c = rgb(rep, 60, 60);                               // the dimple darkens the red
    CHECK(NEAR([c redComponent], 0.86, 0.06) && [c greenComponent] < 0.06);

    rep = render(makeSplit([RedSplitView class], NSSplitViewDividerStyleThin, YES));
    c = rgb(rep, 60, 20);
    CHECK([c redComponent] > 0.95 && [c greenComponent] < 0.05);

    rep = render(makeSplit([RedSplitView class], NSSplitViewDividerStylePaneSplitter, YES));
    c = rgb(rep, 60, 20);
    CHECK([c redComponent] > 0.95 && [c greenComponent] > 0.95);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    test_divider_colors();
    test_quirk_dimple();
    test_quirk_pane_splitter();
    test_thin_line();
    test_quirk_divider_color();
    [pool release];
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
