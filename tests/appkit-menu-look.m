// Copyright (C) 2026 Lubos Dolezel
//
// The look of menus: geometry, colours and shape of a pull-down or pop-up menu window, compared with
// numbers measured on macOS 10.14.4 (light appearance, Blue accent) from window images of the same menus
// (black-box, vd-upstream/mac-probes/menu-look/menuprobe.m) and through -[NSMenu size].
// The font differs between the systems, so text is only checked by where its ink starts and ends (with a
// tolerance of 2 points) and sizes that depend on text width are not compared.
//
// The drawing part renders the menu's view (NSSubmenuView, Darling's AppKit) into a bitmap and runs only
// where that class exists. With "-popup <kind> -secs <seconds>" the program instead shows that menu on screen
// for the given time (default 3), for screenshots.
#import <AppKit/AppKit.h>
#import <objc/message.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
#define NEAR(a, b, tol) (fabs((double)(a) - (double)(b)) <= (tol))

static NSMenu *makeMenu(int kind) {
    NSMenu *m = [[NSMenu alloc] initWithTitle: @"T"];
    [m setAutoenablesItems: NO];
    NSMenuItem *it;
    if (kind == 0) {
        [m addItemWithTitle: @"Plain" action: @selector(self) keyEquivalent: @""];
        [m addItemWithTitle: @"With Cmd N" action: @selector(self) keyEquivalent: @"n"];
        it = [m addItemWithTitle: @"All modifiers" action: @selector(self) keyEquivalent: @"k"];
        [it setKeyEquivalentModifierMask: NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift |
                                          NSEventModifierFlagControl];
        [m addItemWithTitle: @"Shift Cmd S" action: @selector(self) keyEquivalent: @"S"];
        it = [m addItemWithTitle: @"On state" action: @selector(self) keyEquivalent: @""];
        [it setState: NSControlStateValueOn];
        it = [m addItemWithTitle: @"Mixed state" action: @selector(self) keyEquivalent: @""];
        [it setState: NSControlStateValueMixed];
        it = [m addItemWithTitle: @"Disabled" action: @selector(self) keyEquivalent: @"d"];
        [it setEnabled: NO];
        [m addItem: [NSMenuItem separatorItem]];
        it = [m addItemWithTitle: @"Indented 1" action: @selector(self) keyEquivalent: @""];
        [it setIndentationLevel: 1];
        it = [m addItemWithTitle: @"Indented 2" action: @selector(self) keyEquivalent: @""];
        [it setIndentationLevel: 2];
        it = [m addItemWithTitle: @"With image" action: @selector(self) keyEquivalent: @""];
        [it setImage: [NSImage imageWithSize: NSMakeSize(16, 16) flipped: NO drawingHandler: ^BOOL(NSRect r) {
            [[NSColor redColor] setFill];
            NSRectFill(r);
            return YES;
        }]];
        it = [m addItemWithTitle: @"Submenu" action: nil keyEquivalent: @""];
        NSMenu *sub = [[NSMenu alloc] initWithTitle: @"S"];
        [sub addItemWithTitle: @"Sub one" action: @selector(self) keyEquivalent: @""];
        [it setSubmenu: sub];
        [m addItemWithTitle: @"A much longer menu item title to see the width" action: @selector(self) keyEquivalent: @""];
    } else if (kind == 1) {
        [m addItemWithTitle: @"First item" action: @selector(self) keyEquivalent: @""];
    } else if (kind == 2) {
        for (int i = 0; i < 120; i++)
            [m addItemWithTitle: [NSString stringWithFormat: @"Item %d", i] action: @selector(self) keyEquivalent: @""];
    } else if (kind == 3) {
        for (int i = 0; i < 4; i++)
            [m addItemWithTitle: [NSString stringWithFormat: @"Choice %d", i] action: @selector(self) keyEquivalent: @""];
    }
    return m;
}

static NSSize menuSize(NSMenu *m) {
    return ((NSSize (*)(id, SEL))objc_msgSend)(m, @selector(size));
}

// Heights of NSMenu's size on macOS 10.14.4 for menus of known content (NSMenu size, x86_64).
static void testSizes(void) {
    CHECK(NEAR(menuSize(makeMenu(1)).height, 29, 0.5), "one item: height %.1f, expected 29", menuSize(makeMenu(1)).height);
    CHECK(NEAR(menuSize(makeMenu(3)).height, 86, 0.5), "four items: height %.1f, expected 86", menuSize(makeMenu(3)).height);
    CHECK(NEAR(menuSize(makeMenu(2)).height, 2290, 0.5), "120 items: height %.1f, expected 2290", menuSize(makeMenu(2)).height);
    CHECK(NEAR(menuSize(makeMenu(0)).height, 252, 0.5), "representative menu: height %.1f, expected 252", menuSize(makeMenu(0)).height);

    NSMenu *m = [[NSMenu alloc] init];
    NSMenuItem *it = [m addItemWithTitle: @"A" action: nil keyEquivalent: @""];
    CGFloat h1 = menuSize(m).height;
    [m addItem: [NSMenuItem separatorItem]];
    CHECK(NEAR(menuSize(m).height, h1, 0.5), "a trailing separator changes the height: %.1f -> %.1f", h1, menuSize(m).height);
    [m addItemWithTitle: @"B" action: nil keyEquivalent: @""];
    CHECK(NEAR(menuSize(m).height, 10 + 19 * 2 + 12, 0.5), "item, separator, item: height %.1f, expected 60", menuSize(m).height);
    m = [[NSMenu alloc] init];
    it = [m addItemWithTitle: @"A" action: nil keyEquivalent: @""];
    [it setImage: [NSImage imageWithSize: NSMakeSize(16, 16) flipped: NO drawingHandler: ^BOOL(NSRect r) { return YES; }]];
    CHECK(NEAR(menuSize(m).height, 31, 0.5), "item with a 16 point image: height %.1f, expected 31", menuSize(m).height);
    // Widths: indentation adds 12 per level, a submenu adds a 39 point column, a key equivalent adds its
    // width and gap; all relative to the same title.
    NSMenu *a = [[NSMenu alloc] init], *b = [[NSMenu alloc] init];
    [a addItemWithTitle: @"First item" action: nil keyEquivalent: @""];
    it = [b addItemWithTitle: @"First item" action: nil keyEquivalent: @""];
    [it setIndentationLevel: 1];
    CHECK(NEAR(menuSize(b).width - menuSize(a).width, 12, 0.6), "indentation adds %.1f, expected 12", menuSize(b).width - menuSize(a).width);
    b = [[NSMenu alloc] init];
    it = [b addItemWithTitle: @"First item" action: nil keyEquivalent: @""];
    [it setSubmenu: [[NSMenu alloc] init]];
    CHECK(NEAR(menuSize(b).width - menuSize(a).width, 39, 0.6), "a submenu adds %.1f, expected 39", menuSize(b).width - menuSize(a).width);
    it = [[NSMenu alloc] init] ? nil : nil;
}

static NSBitmapImageRep *render(NSMenu *m, NSInteger selected, NSSize *outSize) {
    Class cls = NSClassFromString(@"NSSubmenuView");
    NSView *v = [[cls alloc] performSelector: @selector(initWithMenu:) withObject: m];
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(v, @selector(setSelectedItemIndex:), (NSUInteger)selected);
    NSRect b = [v bounds];
    *outSize = b.size;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect: b];
    [v cacheDisplayInRect: b toBitmapImageRep: rep];
    return rep;
}

typedef struct { int r, g, b, a; } Px;
static Px px(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    CGFloat r, g, bl, a;
    [c getRed: &r green: &g blue: &bl alpha: &a];
    Px p = { (int)lround(r * 255), (int)lround(g * 255), (int)lround(bl * 255), (int)lround(a * 255) };
    return p;
}
static BOOL isClose(Px p, int r, int g, int b, int tol) {
    return abs(p.r - r) <= tol && abs(p.g - g) <= tol && abs(p.b - b) <= tol;
}

// Ink: pixels that differ from the background by more than 40 in some channel, within a rectangle.
static BOOL inkBox(NSBitmapImageRep *rep, NSInteger x0, NSInteger x1, NSInteger y0, NSInteger y1, Px bg, NSInteger *ox0, NSInteger *ox1, NSInteger *oy0, NSInteger *oy1) {
    NSInteger minx = 99999, maxx = -1, miny = 99999, maxy = -1;
    for (NSInteger y = y0; y < y1; y++)
        for (NSInteger x = x0; x < x1; x++) {
            Px p = px(rep, x, y);
            if (abs(p.r - bg.r) > 40 || abs(p.g - bg.g) > 40 || abs(p.b - bg.b) > 40) {
                if (x < minx) minx = x;
                if (x > maxx) maxx = x;
                if (y < miny) miny = y;
                if (y > maxy) maxy = y;
            }
        }
    *ox0 = minx; *ox1 = maxx; *oy0 = miny; *oy1 = maxy;
    return maxx >= 0;
}

static void testDrawing(const char *outDir) {
    if (NSClassFromString(@"NSSubmenuView") == Nil) { printf("SKIP drawing: no NSSubmenuView (not Darling's AppKit)\n"); return; }
    NSMenu *m = makeMenu(0);
    NSSize size;
    NSBitmapImageRep *rep = render(m, 2, &size);
    NSInteger W = size.width, H = size.height;
    Px bg = { 246, 246, 246, 255 };

    // Row layout (y of the top of each row, counted from the window's top edge): 4 point padding, 19 point rows,
    // a 12 point separator after the seventh row, a 21 point row for the item with the 16 point image.
    CHECK(NEAR(H, 250, 0.5), "window height %ld, expected 250", (long)H);
    CHECK(fabs(menuSize(m).width - W) < 0.5, "menu width %ld differs from -[NSMenu size] width %.1f", (long)W, menuSize(m).width);

    // Corners are transparent, edges opaque; the corner has a radius of about 6 points (alphas at 1x).
    CHECK(px(rep, 0, 0).a < 30, "top-left corner pixel alpha %d, expected about 0", px(rep, 0, 0).a);
    CHECK(px(rep, W - 1, 0).a < 30, "top-right corner pixel alpha %d, expected about 0", px(rep, W - 1, 0).a);
    CHECK(px(rep, 0, H - 1).a < 30, "bottom-left corner pixel alpha %d, expected about 0", px(rep, 0, H - 1).a);
    CHECK(px(rep, 1, 1).a > 70 && px(rep, 1, 1).a < 210, "pixel (1,1) alpha %d, expected about 135", px(rep, 1, 1).a);
    CHECK(px(rep, 6, 0).a > 230, "pixel (6,0) alpha %d, expected opaque", px(rep, 6, 0).a);
    CHECK(px(rep, 0, 6).a > 230, "pixel (0,6) alpha %d, expected opaque", px(rep, 0, 6).a);
    CHECK(px(rep, 6, 6).a == 255, "pixel (6,6) alpha %d, expected opaque", px(rep, 6, 6).a);

    // Background grey, no frame line at the edge.
    CHECK(isClose(px(rep, 3, 12), 246, 246, 246, 2), "background is %d %d %d, expected 246", px(rep, 3, 12).r, px(rep, 3, 12).g, px(rep, 3, 12).b);
    CHECK(isClose(px(rep, 0, 12), 246, 246, 246, 3), "left edge pixel is %d %d %d, no frame line expected", px(rep, 0, 12).r, px(rep, 0, 12).g, px(rep, 0, 12).b);
    CHECK(isClose(px(rep, W / 2, 0), 246, 246, 246, 3), "top edge pixel is %d %d %d, no frame line expected", px(rep, W / 2, 0).r, px(rep, W / 2, 0).g, px(rep, W / 2, 0).b);

    // test_quirk_menu_highlight_pixel: the selected row (third, index 2) spans rows 42..60 and the full width.
    int first = -1, last = -1;
    for (int y = 0; y < H; y++)
        if (isClose(px(rep, 3, y), 0, 86, 217, 6)) { if (first < 0) first = y; last = y; }
    CHECK(first == 42 && last == 60, "highlight rows %d..%d, expected 42..60", first, last);
    CHECK(isClose(px(rep, 3, 50), 0, 86, 217, 6), "highlight at the left is %d %d %d, expected 0 86 217", px(rep, 3, 50).r, px(rep, 3, 50).g, px(rep, 3, 50).b);
    CHECK(isClose(px(rep, 0, 50), 0, 86, 217, 6), "highlight does not reach the left edge");
    CHECK(isClose(px(rep, W - 1, 50), 0, 86, 217, 6), "highlight does not reach the right edge");
    CHECK(isClose(px(rep, W - 4, 50), 0, 86, 217, 6), "highlight at the right is %d %d %d", px(rep, W - 4, 50).r, px(rep, W - 4, 50).g, px(rep, W - 4, 50).b);
    NSInteger a0, a1, b0, b1;
    BOOL white = NO;
    for (int y = 44; y < 59 && !white; y++)
        for (int x = 20; x < 110 && !white; x++)
            if (px(rep, x, y).r > 235 && px(rep, x, y).g > 235) white = YES;
    CHECK(white, "no white text in the highlighted row");

    // Separator: two pixel rows of grey 229 in the middle of the 12 point separator (rows 137..148), full width.
    int sepRows = 0, sepFirst = -1;
    for (int y = 130; y < 160; y++)
        if (isClose(px(rep, W / 2, y), 229, 229, 229, 4)) { sepRows++; if (sepFirst < 0) sepFirst = y; }
    CHECK(sepRows == 2 && sepFirst == 142, "separator: %d rows starting at %d, expected 2 starting at 142", sepRows, sepFirst);
    CHECK(isClose(px(rep, 0, 142), 229, 229, 229, 5) && isClose(px(rep, W - 1, 142), 229, 229, 229, 5), "separator does not span the full width");

    // Text start: the ink of "Plain" begins 22 points from the left and in rows 7..17 (font dependent: +-2).
    if (inkBox(rep, 8, 120, 5, 22, bg, &a0, &a1, &b0, &b1)) {
        CHECK(NEAR(a0, 22, 2), "'Plain' ink starts at x=%ld, expected 22", (long)a0);
        CHECK(b0 >= 5 && b1 <= 20 && NEAR((b0 + b1) / 2.0, 12, 2), "'Plain' ink rows %ld..%ld, expected about 7..17", (long)b0, (long)b1);
    } else CHECK(0, "no text in the first row");

    // Key equivalents end 10 points from the right edge (ink), two rows down: "With Cmd N".
    if (inkBox(rep, W / 2 + 40, W, 23, 40, bg, &a0, &a1, &b0, &b1))
        CHECK(NEAR(W - 1 - a1, 10, 2), "key equivalent ink ends %ld from the right edge, expected 10", (long)(W - 1 - a1));
    else CHECK(0, "no key equivalent in the second row");

    // State marks, in the gutter at the left.
    // On state, row 4 (rows 80..98): a tick 11x11 inside x 6..16, y 83..93.
    if (inkBox(rep, 0, 20, 80, 99, bg, &a0, &a1, &b0, &b1)) {
        CHECK(NEAR(a0, 6, 1.5) && NEAR(a1, 16, 1.5), "check mark x %ld..%ld, expected 6..16", (long)a0, (long)a1);
        CHECK(NEAR(b0, 83, 1.5) && NEAR(b1, 93, 1.5), "check mark y %ld..%ld, expected 83..93", (long)b0, (long)b1);
    } else CHECK(0, "no check mark");
    // Mixed state, row 5 (rows 99..117): a dash 10x2, x 6..15, y 108..109.
    if (inkBox(rep, 0, 20, 99, 118, bg, &a0, &a1, &b0, &b1)) {
        CHECK(NEAR(a0, 6, 1.5) && NEAR(a1, 15, 1.5), "dash x %ld..%ld, expected 6..15", (long)a0, (long)a1);
        CHECK(NEAR(b0, 108, 1.5) && NEAR(b1, 109, 1.5), "dash y %ld..%ld, expected 108..109", (long)b0, (long)b1);
    } else CHECK(0, "no mixed state mark");

    // Disabled text is translucent black: darkest pixel about 189 (row 6, rows 118..136).
    int darkest = 255;
    for (int y = 118; y < 137; y++)
        for (int x = 20; x < 120; x++) { int l = px(rep, x, y).r; if (l < darkest) darkest = l; }
    CHECK(darkest > 170 && darkest < 215, "disabled text darkest %d, expected about 189", darkest);

    // Indentation, 12 points per level: rows 149..167 and 168..186.
    NSInteger i1, i2, p1;
    if (inkBox(rep, 8, 150, 150, 167, bg, &i1, &a1, &b0, &b1) && inkBox(rep, 8, 150, 170, 186, bg, &i2, &a1, &b0, &b1) &&
        inkBox(rep, 8, 150, 5, 22, bg, &p1, &a1, &b0, &b1)) {
        CHECK(NEAR(i1 - p1, 12, 2), "level 1 starts %ld right of level 0, expected 12", (long)(i1 - p1));
        CHECK(NEAR(i2 - i1, 12, 1.5), "level 2 starts %ld right of level 1, expected 12", (long)(i2 - i1));
    } else CHECK(0, "indented rows have no text");

    // Image: 16x16 at x 21, rows 190..205; the title follows 3 points after it (ink starts at x 40).
    int redx0 = 9999, redx1 = -1, redy0 = 9999, redy1 = -1;
    for (int y = 180; y < 215; y++)
        for (int x = 0; x < 60; x++) {
            Px p = px(rep, x, y);
            if (p.r > 200 && p.g < 70 && p.b < 70) { if (x < redx0) redx0 = x; if (x > redx1) redx1 = x; if (y < redy0) redy0 = y; if (y > redy1) redy1 = y; }
        }
    CHECK(NEAR(redx0, 21, 1) && NEAR(redx1, 36, 1) && NEAR(redy0, 190, 1) && NEAR(redy1, 205, 1), "image at x %d..%d, y %d..%d, expected 21..36, 190..205", redx0, redx1, redy0, redy1);
    int tx = 9999;
    for (int y = 188; y < 207; y++)
        for (int x = 38; x < 130; x++) { Px p = px(rep, x, y); if (p.r < 150 && p.g < 150 && p.b < 150 && x < tx) tx = x; }
    CHECK(NEAR(tx, 40, 2), "title after the image starts at %d, expected 40", tx);

    // Submenu arrow, row 11 (rows 208..226): 8x10 at x W-21..W-14, y 212..221 (selected rendering is white).
    rep = render(m, 11, &size);
    int ax0 = 9999, ax1 = -1, ay0 = 9999, ay1 = -1;
    for (int y = 208; y < 227; y++)
        for (int x = W - 40; x < W; x++)
            if (px(rep, x, y).r > 200 && px(rep, x, y).g > 200) { if (x < ax0) ax0 = x; if (x > ax1) ax1 = x; if (y < ay0) ay0 = y; if (y > ay1) ay1 = y; }
    CHECK(ax1 >= 0 && NEAR(W - 1 - ax1, 13, 1.5) && NEAR(ax1 - ax0, 7, 1.5) && NEAR(ay1 - ay0, 9, 1.5), "arrow x %d..%d (right edge %d from the edge), y %d..%d, expected 8x10 ending 14 from the edge", ax0, ax1, W - 1 - ax1, ay0, ay1);
    CHECK(NEAR(ay0, 212, 1.5), "arrow top at %d, expected 212", ay0);
    // The image row's highlight is 21 rows high.
    rep = render(m, 10, &size);
    first = last = -1;
    for (int y = 0; y < H; y++)
        if (isClose(px(rep, 3, y), 0, 86, 217, 6)) { if (first < 0) first = y; last = y; }
    CHECK(first == 187 && last == 207, "image row highlight rows %d..%d, expected 187..207", first, last);

    if (outDir) {
        NSBitmapImageRep *shot = render(m, 2, &size);
        NSData *png = [shot representationUsingType: NSBitmapImageFileTypePNG properties: @{}];
        [png writeToFile: [[NSString stringWithUTF8String: outDir] stringByAppendingPathComponent: @"render.png"] atomically: NO];
    }
}

// A menu taller than the room it has scrolls and shows a scroll arrow, 10 wide and 8 high, in the middle of the
// last 19 points of a 580 point window (rows 566..573); once scrolled to the end the arrow is at the top.
static void testScrolling(void) {
    Class cls = NSClassFromString(@"NSSubmenuView");
    if (cls == Nil || ![cls instancesRespondToSelector: NSSelectorFromString(@"limitHeightTo:")]) { printf("SKIP scrolling\n"); return; }
    NSMenu *m = makeMenu(2);
    NSView *v = [[cls alloc] performSelector: @selector(initWithMenu:) withObject: m];
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(v, NSSelectorFromString(@"limitHeightTo:"), 580);
    CHECK(NEAR([v bounds].size.height, 580, 0.5), "limited view height %.1f, expected 580", [v bounds].size.height);
    CHECK(NEAR(menuSize(m).height, 2290, 0.5), "a menu's size follows its content, not its window: %.1f", menuSize(m).height);
    NSRect b = [v bounds];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect: b];
    [v cacheDisplayInRect: b toBitmapImageRep: rep];
    NSInteger W = b.size.width, a0, a1, b0, b1;
    Px bg = { 246, 246, 246, 255 };
    if (inkBox(rep, 4, W - 4, 562, 578, bg, &a0, &a1, &b0, &b1)) {
        CHECK(NEAR(a0, 43, 3) && NEAR(a1, 52, 3) && NEAR((a0 + a1) / 2.0, W / 2.0, 1.5), "bottom arrow x %ld..%ld in a %ld wide menu, expected 10 wide at the middle", (long)a0, (long)a1, (long)W);
        CHECK(NEAR(b0, 566, 1.5) && NEAR(b1, 573, 1.5), "bottom arrow rows %ld..%ld, expected 566..573", (long)b0, (long)b1);
    } else CHECK(0, "no scroll arrow at the bottom of a scrolling menu");
    CHECK(!inkBox(rep, 4, W - 4, 0, 4, bg, &a0, &a1, &b0, &b1), "ink above the first row of a menu scrolled to the top");
    // Selecting the last row scrolls it into view; the arrow moves to the top.
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(v, @selector(setSelectedItemIndex:), 119);
    rep = [v bitmapImageRepForCachingDisplayInRect: b];
    [v cacheDisplayInRect: b toBitmapImageRep: rep];
    int hl = 0;
    for (int y = 0; y < 580; y++)
        if (isClose(px(rep, 3, y), 0, 86, 217, 6)) hl++;
    CHECK(hl == 19, "selected last row is %d rows high, expected 19 (fully visible)", hl);
    CHECK(inkBox(rep, 4, W - 4, 0, 19, bg, &a0, &a1, &b0, &b1) && NEAR((a0 + a1) / 2.0, W / 2.0, 1.5), "no scroll arrow at the top of a menu scrolled to the end");
}

// The menu bar is 22 points high on a main menu and has no height on another menu.
static void testBar(void) {
    NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
    NSMenu *other = [[NSMenu alloc] initWithTitle: @"Other"];
    [NSApp setMainMenu: main];
    CHECK(NEAR(((CGFloat (*)(id, SEL))objc_msgSend)(main, @selector(menuBarHeight)), 22, 0.01), "menuBarHeight of the main menu is %.2f, expected 22", ((CGFloat (*)(id, SEL))objc_msgSend)(main, @selector(menuBarHeight)));
    CHECK(((CGFloat (*)(id, SEL))objc_msgSend)(other, @selector(menuBarHeight)) == 0, "menuBarHeight of another menu is not 0");
    CHECK(NEAR([[NSStatusBar systemStatusBar] thickness], 22, 0.01), "status bar thickness is %.2f, expected 22", [[NSStatusBar systemStatusBar] thickness]);
    // The font sizes: menus 14 (a new menu's font, the menu bar's) and 13 (menuFontOfSize:0).
    CHECK(NEAR([[NSFont menuFontOfSize: 0] pointSize], 13, 0.01), "menuFontOfSize:0 is %.1f, expected 13", [[NSFont menuFontOfSize: 0] pointSize]);
    CHECK(NEAR([[NSFont menuBarFontOfSize: 0] pointSize], 14, 0.01), "menuBarFontOfSize:0 is %.1f, expected 14", [[NSFont menuBarFontOfSize: 0] pointSize]);
    CHECK(NEAR([[[NSMenu alloc] init] font].pointSize, 14, 0.01), "a new menu's font is %.1f, expected 14", [[[NSMenu alloc] init] font].pointSize);
}

// A pop-up button's menu (NSPopUpView): 4 point padding, 18 point rows for the 13 point control font, the
// selected row highlighted, a check mark on it.
static void testPopUp(void) {
    Class cls = NSClassFromString(@"NSPopUpView");
    if (cls == Nil) { printf("SKIP pop-up view\n"); return; }
    NSMenu *m = makeMenu(3);
    NSView *v = [[cls alloc] initWithFrame: NSMakeRect(0, 0, 120, 80)];
    [v setMenu: m];
    ((void (*)(id, SEL, id))objc_msgSend)(v, @selector(setFont:), [NSFont systemFontOfSize: 13]);
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(v, @selector(selectItemAtIndex:), 1);
    NSSize sz = ((NSSize (*)(id, SEL))objc_msgSend)(v, @selector(sizeForContents));
    CHECK(NEAR(sz.height, 80, 0.5), "pop-up menu height %.1f for four items, expected 80", sz.height);
    [v setFrameSize: NSMakeSize(120, sz.height)];
    NSRect b = [v bounds];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect: b];
    [v cacheDisplayInRect: b toBitmapImageRep: rep];
    int first = -1, last = -1;
    for (int y = 0; y < 80; y++)
        if (isClose(px(rep, 3, y), 0, 86, 217, 6)) { if (first < 0) first = y; last = y; }
    CHECK(first == 22 && last == 39, "pop-up highlight rows %d..%d, expected 22..39", first, last);
    CHECK(px(rep, 0, 0).a < 30 && px(rep, 119, 79).a < 30, "pop-up menu corners are not transparent");
    CHECK(isClose(px(rep, 3, 12), 246, 246, 246, 2), "pop-up background is %d %d %d", px(rep, 3, 12).r, px(rep, 3, 12).g, px(rep, 3, 12).b);
    NSInteger a0, a1, b0, b1;
    Px bg = { 246, 246, 246, 255 };
    if (inkBox(rep, 8, 100, 5, 20, bg, &a0, &a1, &b0, &b1))
        CHECK(NEAR(a0, 22, 2), "pop-up title ink starts at %ld, expected 22", (long)a0);
    else CHECK(0, "no title in the first pop-up row");
}

@interface HV : NSView @end
static NSMenu *gMenu;
@implementation HV
- (void) dump: (NSTimer *) t {
    for (NSWindow *w in [NSApp windows]) NSLog(@"window %@ frame %@ opaque %d", NSStringFromClass([w class]), NSStringFromRect([w frame]), [w isOpaque]);
}
- (void) mouseDown: (NSEvent *) e {
    [[NSRunLoop currentRunLoop] addTimer: [NSTimer timerWithTimeInterval: 1.0 target: self selector: @selector(dump:) userInfo: nil repeats: NO] forMode: NSRunLoopCommonModes];
    [NSMenu popUpContextMenu: gMenu withEvent: e forView: self];
    exit(0);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // "-popup <kind> -secs <n>" (user defaults syntax, so that AppKit does not take them for files to open)
        // "-bar 1 -secs <n>": a window with a main menu (the menu bar, in the window by default) for screenshots
        if ([[NSUserDefaults standardUserDefaults] objectForKey: @"bar"] != nil) {
            NSMenu *main = [[NSMenu alloc] init];
            NSMenuItem *app = [main addItemWithTitle: @"Probe" action: nil keyEquivalent: @""];
            NSMenu *m0 = makeMenu(0); [m0 setTitle: @"Probe"]; [app setSubmenu: m0];
            NSMenuItem *file = [main addItemWithTitle: @"File" action: nil keyEquivalent: @""];
            NSMenu *m3 = makeMenu(3); [m3 setTitle: @"File"]; [file setSubmenu: m3];
            NSMenuItem *edit = [main addItemWithTitle: @"Edit" action: nil keyEquivalent: @""];
            NSMenu *m1 = makeMenu(1); [m1 setTitle: @"Edit"]; [edit setSubmenu: m1];
            [NSApp setMainMenu: main];
            NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 400, 600, 300)
                                                      styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                        backing: NSBackingStoreBuffered defer: NO];
            [w makeKeyAndOrderFront: nil];
            [NSApp activateIgnoringOtherApps: YES];
            [NSApp finishLaunching];
            double secs = [[NSUserDefaults standardUserDefaults] doubleForKey: @"secs"];
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow: secs > 0 ? secs : 10];
            while ([end timeIntervalSinceNow] > 0) {
                NSEvent *e = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode dequeue: YES];
                if (e) [NSApp sendEvent: e];
            }
            return 0;
        }
        if ([[NSUserDefaults standardUserDefaults] objectForKey: @"popup"] != nil) {
            gMenu = makeMenu((int)[[NSUserDefaults standardUserDefaults] integerForKey: @"popup"]);
            double secs = [[NSUserDefaults standardUserDefaults] objectForKey: @"secs"] ? [[NSUserDefaults standardUserDefaults] doubleForKey: @"secs"] : 3;
            NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 400, 400, 300)
                                                      styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                        backing: NSBackingStoreBuffered defer: NO];
            [w setContentView: [[HV alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)]];
            [w makeKeyAndOrderFront: nil];
            [NSApp activateIgnoringOtherApps: YES];
            [NSApp finishLaunching];
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
            NSEvent *ev = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown location: NSMakePoint(50, 250)
                                        modifierFlags: 0 timestamp: [[NSProcessInfo processInfo] systemUptime]
                                         windowNumber: [w windowNumber] context: nil eventNumber: 1 clickCount: 1 pressure: 1];
            [NSApp postEvent: ev atStart: NO];
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow: secs + 5];
            while ([end timeIntervalSinceNow] > 0) {
                NSEvent *e = [NSApp nextEventMatchingMask: NSEventMaskAny untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode dequeue: YES];
                if (e) [NSApp sendEvent: e];
            }
            return 0;
        }
        testSizes();
        testDrawing(argc > 1 ? argv[1] : NULL);
        testScrolling();
        testPopUp();
        testBar();
        if (failures) { printf("FAILED (%d)\n", failures); return 1; }
        printf("PASS\n");
    }
    return 0;
}
