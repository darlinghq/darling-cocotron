// Copyright (C) 2026 Lubos Dolezel
//
// Under NSAppearanceNameDarkAqua a rounded NSSegmentedControl and an NSTabView draw a dark look: a translucent light
// strip over the window colour with light labels, a deeper blue selected segment in an active window, a light selected
// segment with dark text in an inactive one, dark dividers and a faintly lighter box. The Aqua appearance keeps
// its white strip. Each control is rendered with -cacheDisplayInRect:toBitmapImageRep: over a mid-dark backdrop and the
// luminance of the strip, the selected segment, the dividers, the box and the labels is sampled.
// The expected values follow renders of the same controls on macOS 10.14.4 (black-box observation, tier 2): the dark
// strip is the backdrop (luma 0.196) plus 25% white (0.396), the inactive selected segment 0.60, the box 0.22.
// This covers the QUIRK-tagged drawing in NSGraphicsStyle (NSTabViewAqua), NSSegmentedCell and NSTabViewItem.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures, checks;
#define CHECK(c, ...) do { checks++; if (!(c)) { fprintf(stderr, "FAIL line %d: %s: ", __LINE__, #c); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); failures++; } } while (0)

@interface ActiveWindow : NSWindow
@end
@implementation ActiveWindow
- (BOOL) isKeyWindow { return YES; }
- (BOOL) isMainWindow { return YES; }
@end

@interface InactiveWindow : NSWindow
@end
@implementation InactiveWindow
- (BOOL) isKeyWindow { return NO; }
- (BOOL) isMainWindow { return NO; }
@end

@interface ActiveApp : NSApplication
@end
@implementation ActiveApp
- (BOOL) isActive { return YES; }
@end

@interface Backdrop : NSView
@end
@implementation Backdrop
- (void) drawRect: (NSRect) r {
    [[NSColor colorWithCalibratedWhite: 50 / 255.0 alpha: 1] setFill];
    NSRectFill([self bounds]);
}
@end

static NSWindow *aquaActive, *darkActive, *darkInactive;

static double luma(NSBitmapImageRep *rep, int x, int y) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

    return 0.299 * [c redComponent] + 0.587 * [c greenComponent] + 0.114 * [c blueComponent];
}

static void rgb(NSBitmapImageRep *rep, int x, int y, double *r, double *b) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

    *r = [c redComponent];
    *b = [c blueComponent];
}

// renders view over the backdrop; the view sits at (8, 8) of a 16 point larger backdrop
static NSBitmapImageRep *render(NSWindow *window, NSView *view) {
    NSRect vf = [view frame];
    Backdrop *box = [[Backdrop alloc] initWithFrame: NSMakeRect(0, 0, vf.size.width + 16, vf.size.height + 16)];

    [view setFrameOrigin: NSMakePoint(8, 8)];
    [box addSubview: view];
    [[window contentView] setSubviews: @[]];
    [window setContentSize: [box frame].size];
    [[window contentView] addSubview: box];
    [box displayIfNeeded];
    NSBitmapImageRep *rep = [box bitmapImageRepForCachingDisplayInRect: [box bounds]];
    [box cacheDisplayInRect: [box bounds] toBitmapImageRep: rep];
    [view removeFromSuperview];
    return rep;
}

static int compareDoubles(const void *a, const void *b) {
    double x = *(const double *) a, y = *(const double *) b;

    return x < y ? -1 : (x > y);
}

// the median luminance along a row (not thrown off by the pixels of the text)
static double rowMedian(NSBitmapImageRep *rep, int y, int x0, int x1) {
    double v[512];
    int n = 0;

    for (int x = x0; x < x1 && n < 512; x++)
        v[n++] = luma(rep, x, y);
    qsort(v, n, sizeof(double), compareDoubles);
    return v[n / 2];
}

static double rowMax(NSBitmapImageRep *rep, int y0, int y1, int x0, int x1) {
    double m = 0;

    for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++)
            m = MAX(m, luma(rep, x, y));
    return m;
}

static double rowMin(NSBitmapImageRep *rep, int y0, int y1, int x0, int x1) {
    double m = 1;

    for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++)
            m = MIN(m, luma(rep, x, y));
    return m;
}

// the x of the first pixel along a row that is lighter than the backdrop by a margin (the left end of the strip)
static int firstLit(NSBitmapImageRep *rep, int y, int x0, int x1) {
    for (int x = x0; x < x1; x++)
        if (luma(rep, x, y) > 0.28)
            return x;
    return x0;
}

static NSSegmentedControl *segmented(NSInteger selected) {
    NSSegmentedControl *s = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 150, 26)];

    [s setSegmentCount: 3];
    for (int i = 0; i < 3; i++) {
        [s setLabel: [NSString stringWithFormat: @"S%d", i] forSegment: i];
        [s setWidth: 48 forSegment: i];
    }
    [s setSegmentStyle: NSSegmentStyleRounded];
    [s setTrackingMode: NSSegmentSwitchTrackingSelectOne];
    [s setSelectedSegment: selected];
    return s;
}

static NSTabView *tabs(NSInteger selected) {
    NSTabView *t = [[NSTabView alloc] initWithFrame: NSMakeRect(0, 0, 220, 110)];

    for (int i = 0; i < 3; i++) {
        NSTabViewItem *it = [[NSTabViewItem alloc] initWithIdentifier: [NSString stringWithFormat: @"%d", i]];

        [it setLabel: [NSString stringWithFormat: @"Tab%d", i]];
        [t addTabViewItem: it];
    }
    [t selectTabViewItemAtIndex: selected];
    return t;
}

static void testSegmented(void) {
    // aqua: white strip; dark: translucent white strip over the backdrop (0.196 + 0.25 * 0.804 = 0.40)
    NSBitmapImageRep *a = render(aquaActive, segmented(2)), *d = render(darkActive, segmented(2));
    double aquaStrip = luma(a, 8 + 6, 8 + 13), darkStrip = luma(d, 8 + 6, 8 + 13);

    CHECK(aquaStrip > 0.95, "aqua rounded segmented strip luma %.2f", aquaStrip);
    CHECK(darkStrip >= 0.33 && darkStrip <= 0.46, "dark rounded segmented strip luma %.2f", darkStrip);

    // the divider between the first two segments is darker than the strip
    double divider = luma(d, 8 + 48, 8 + 13);

    CHECK(darkStrip - divider > 0.03, "dark segmented divider (%.2f) is not darker than the strip (%.2f)", divider, darkStrip);

    // the selected segment of an active window is blue: deeper than the aqua blue
    double r, b;

    rgb(d, 8 + 96 + 6, 8 + 13, &r, &b);
    CHECK(b - r > 0.4, "dark selected segment is not blue (r %.2f b %.2f)", r, b);
    CHECK(luma(d, 8 + 96 + 6, 8 + 13) < 0.5, "dark selected segment is as light as the aqua one (%.2f)", luma(d, 8 + 96 + 6, 8 + 13));

    // the labels are light on the strip
    double text = rowMax(d, 8 + 5, 8 + 21, 8 + 12, 8 + 36);

    CHECK(text - darkStrip > 0.3, "dark segment label (%.2f) does not contrast with the strip (%.2f)", text, darkStrip);

    // inactive: the selected segment is a light one with dark text
    NSBitmapImageRep *i = render(darkInactive, segmented(1));
    double selected = luma(i, 8 + 48 + 5, 8 + 13), other = luma(i, 8 + 6, 8 + 13);
    double selText = rowMin(i, 8 + 5, 8 + 21, 8 + 48 + 12, 8 + 48 + 36);

    CHECK(selected >= 0.5 && selected <= 0.7, "dark inactive selected segment luma %.2f", selected);
    CHECK(selected - other > 0.12, "dark inactive selected segment (%.2f) is not lighter than the others (%.2f)", selected, other);
    CHECK(selected - selText > 0.3, "dark inactive selected segment label (%.2f) is not dark on it (%.2f)", selText, selected);
}

static void testTabs(void) {
    NSBitmapImageRep *a = render(aquaActive, tabs(0)), *d = render(darkActive, tabs(0));
    double aquaStrip = rowMedian(a, 8 + 9, 8 + 30, 8 + 190), darkStrip = rowMedian(d, 8 + 9, 8 + 30, 8 + 190);
    double darkBox = rowMedian(d, 8 + 70, 8 + 20, 8 + 200);

    CHECK(aquaStrip > 0.95, "aqua tab strip luma %.2f", aquaStrip);
    CHECK(darkStrip >= 0.33 && darkStrip <= 0.46, "dark tab strip luma %.2f", darkStrip);
    CHECK(darkBox >= 0.20 && darkBox <= 0.27, "dark tab box luma %.2f (the backdrop is 0.196)", darkBox);
    CHECK(darkStrip - darkBox > 0.1, "dark tab strip (%.2f) does not stand out from the box (%.2f)", darkStrip, darkBox);

    // the unselected labels are light on the strip
    double text = rowMax(d, 8 + 4, 8 + 18, 8 + 100, 8 + 200);

    CHECK(text - darkStrip > 0.3, "dark tab label (%.2f) does not contrast with the strip (%.2f)", text, darkStrip);

    // the selected tab of an active window is blue
    double r, b;
    int left = firstLit(d, 8 + 9, 8, 8 + 100);

    rgb(d, left + 3, 8 + 9, &r, &b);
    CHECK(b - r > 0.3, "dark selected tab is not blue (r %.2f b %.2f)", r, b);

    // inactive window: the selected tab is a light one
    NSBitmapImageRep *i = render(darkInactive, tabs(0));
    double selected = luma(i, firstLit(i, 8 + 9, 8, 8 + 100) + 3, 8 + 9);

    CHECK(selected >= 0.5 && selected <= 0.7 && selected - darkStrip > 0.12, "dark inactive selected tab luma %.2f", selected);
}

int main(void) {
    @autoreleasepool {
        [ActiveApp sharedApplication];
        NSRect frame = NSMakeRect(100, 100, 200, 100);

        aquaActive = [[ActiveWindow alloc] initWithContentRect: frame styleMask: NSTitledWindowMask
                                                       backing: NSBackingStoreBuffered defer: NO];
        darkActive = [[ActiveWindow alloc] initWithContentRect: frame styleMask: NSTitledWindowMask
                                                       backing: NSBackingStoreBuffered defer: NO];
        darkInactive = [[InactiveWindow alloc] initWithContentRect: frame styleMask: NSTitledWindowMask
                                                           backing: NSBackingStoreBuffered defer: NO];
        [aquaActive setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
        [darkActive setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]];
        [darkInactive setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]];
        testSegmented();
        testTabs();
    }
    printf("%s: %d checks, %d failures\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures != 0;
}
