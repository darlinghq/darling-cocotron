// Copyright (C) 2026 Lubos Dolezel
//
// Menu colours and drawing in the light appearance with the Blue accent.
// The colour values and the menu metrics are what macOS 10.14 returns through the public API
// (+[NSColor ...] converted to sRGB, -[NSMenu size]); they pass there as well. The drawing part renders
// the menu's view into a bitmap and runs only where that view class exists (Darling's AppKit).
#import <AppKit/AppKit.h>
#import <objc/message.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void expectColor(const char *name, NSColor *c, double r, double g, double b, double a) {
    NSColor *s = [c colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    CGFloat cr = -1, cg = -1, cb = -1, ca = -1;
    [s getRed: &cr green: &cg blue: &cb alpha: &ca];
    CHECK(fabs(cr - r) < 0.002 && fabs(cg - g) < 0.002 && fabs(cb - b) < 0.002 && fabs(ca - a) < 0.002,
          "%s is sRGB %.3f %.3f %.3f %.3f, expected %.3f %.3f %.3f %.3f", name, cr, cg, cb, ca, r, g, b, a);
}

static NSSize menuSize(NSMenu *m) {
    return ((NSSize (*)(id, SEL))objc_msgSend)(m, @selector(size));
}

static void testColours(void) {
    expectColor("selectedMenuItemColor", [NSColor selectedMenuItemColor], 0.259, 0.467, 0.957, 1.0);
    expectColor("selectedMenuItemTextColor", [NSColor selectedMenuItemTextColor], 1, 1, 1, 1);
    expectColor("controlAccentColor", [NSColor controlAccentColor], 0.0, 0.478, 1.0, 1.0);
    expectColor("disabledControlTextColor", [NSColor disabledControlTextColor], 0, 0, 0, 0.247);
    expectColor("separatorColor", [NSColor separatorColor], 0, 0, 0, 0.098);
}

static void testMenuSize(void) {
    NSMenu *m = [[NSMenu alloc] initWithTitle: @"M"];
    for (int i = 1; i <= 4; i++) {
        [m addItemWithTitle: @"First item" action: NULL keyEquivalent: @""];
        CHECK(fabs(menuSize(m).height - (10 + 19 * i)) < 0.5, "%d items: height %.1f, expected %d", i, menuSize(m).height, 10 + 19 * i);
    }
}

static double lum(NSBitmapImageRep *rep, NSInteger x, NSInteger y, double *r, double *g, double *b) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    CGFloat cr, cg, cb, ca;
    [c getRed: &cr green: &cg blue: &cb alpha: &ca];
    if (r) *r = cr; if (g) *g = cg; if (b) *b = cb;
    return (cr + cg + cb) / 3;
}

// Darkest and brightest luminance within a row, over the area right of the left margin.
static void rowRange(NSBitmapImageRep *rep, NSInteger y0, NSInteger y1, double *lo, double *hi) {
    *lo = 2; *hi = -1;
    for (NSInteger y = y0; y < y1; y++)
        for (NSInteger x = 4; x < [rep pixelsWide] - 4; x++) {
            double l = lum(rep, x, y, NULL, NULL, NULL);
            if (l < *lo) *lo = l;
            if (l > *hi) *hi = l;
        }
}

static void testDrawing(void) {
    Class cls = NSClassFromString(@"NSSubmenuView");
    if (cls == Nil) { printf("SKIP drawing: no NSSubmenuView (not Darling's AppKit)\n"); return; }
    NSMenu *m = [[NSMenu alloc] initWithTitle: @"M"];
    [m setAutoenablesItems: NO];
    [m addItemWithTitle: @"Enabled item" action: @selector(self) keyEquivalent: @""];
    [m addItemWithTitle: @"Highlighted item" action: @selector(self) keyEquivalent: @""];
    [m addItem: [NSMenuItem separatorItem]];
    NSMenuItem *dis = [m addItemWithTitle: @"Disabled item" action: @selector(self) keyEquivalent: @""];
    [dis setEnabled: NO];
    for (NSMenuItem *i in [m itemArray]) if (![i isSeparatorItem] && i != dis) [i setTarget: m];

    NSView *v = [[cls alloc] performSelector: @selector(initWithMenu:) withObject: m];
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(v, @selector(setSelectedItemIndex:), 1);
    NSRect b = [v bounds];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect: b];
    [v cacheDisplayInRect: b toBitmapImageRep: rep];
    NSInteger H = [rep pixelsHigh], W = [rep pixelsWide];
    CHECK(fabs(b.size.height - menuSize(m).height) < 0.5, "view height %.1f, menu size %.1f", b.size.height, menuSize(m).height);

    // Row boundaries from the metrics: 5 point padding, 19 point rows, then the separator.
    NSInteger row1a = 5 + 19, row1b = 5 + 38;
    double r, g, bl;
    lum(rep, W / 2, (row1a + row1b) / 2, &r, &g, &bl);
    // Blend of text pixels is avoided by sampling the row's left margin, where there is no text.
    lum(rep, 3, (row1a + row1b) / 2, &r, &g, &bl);
    CHECK(fabs(r - 0.259) < 0.03 && fabs(g - 0.467) < 0.03 && fabs(bl - 0.957) < 0.03,
          "highlight pixel is %.3f %.3f %.3f, expected 0.259 0.467 0.957", r, g, bl);
    lum(rep, 1, (row1a + row1b) / 2, &r, &g, &bl);
    CHECK(fabs(r - 0.259) < 0.03 && fabs(bl - 0.957) < 0.03, "highlight does not reach the menu's left edge: %.3f %.3f %.3f", r, g, bl);
    lum(rep, W - 2, (row1a + row1b) / 2, &r, &g, &bl);
    CHECK(fabs(r - 0.259) < 0.03 && fabs(bl - 0.957) < 0.03, "highlight does not reach the menu's right edge: %.3f %.3f %.3f", r, g, bl);
    lum(rep, 3, row1a - 3, &r, &g, &bl);
    CHECK(fabs(r - 0.945) < 0.03 && fabs(bl - 0.945) < 0.03, "unhighlighted row is %.3f %.3f %.3f, expected a light grey", r, g, bl);

    double lo, hi;
    rowRange(rep, row1a + 2, row1b - 2, &lo, &hi);
    CHECK(hi > 0.97, "highlighted row has no white text pixel (brightest %.3f)", hi);
    rowRange(rep, 5 + 2, 5 + 17, &lo, &hi);
    CHECK(lo < 0.3, "normal text is not dark (darkest %.3f)", lo);

    // Separator: one hairline, in the separator colour over the background, no light line below it.
    NSInteger sepTop = 5 + 38, sepRows = 9, found = 0;
    for (NSInteger y = sepTop; y < sepTop + sepRows; y++) {
        double l = lum(rep, W / 2, y, NULL, NULL, NULL);
        if (l < 0.9) { found++; CHECK(l > 0.78 && l < 0.90, "separator line luminance %.3f, expected about 0.85", l); }
        CHECK(l < 0.98, "white line in the separator row at %ld", (long)y);
    }
    CHECK(found == 1, "separator is %ld pixels thick, expected 1", (long)found);

    // Disabled text: translucent black over the background (about 0.71), no light shadow.
    NSInteger dy0 = sepTop + sepRows + 2, dy1 = sepTop + sepRows + 17;
    if (dy1 > H) dy1 = H;
    rowRange(rep, dy0, dy1, &lo, &hi);
    CHECK(lo > 0.62 && lo < 0.80, "disabled text darkest pixel %.3f, expected about 0.71", lo);
    CHECK(hi < 0.96, "disabled row has a light shadow pixel (brightest %.3f)", hi);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        testColours();
        testMenuSize();
        testDrawing();
        if (failures) { printf("FAILED (%d)\n", failures); return 1; }
        printf("PASS\n");
    }
    return 0;
}
