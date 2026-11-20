// Copyright (C) 2026 Lubos Dolezel
//
// The controls of toolbars look like the Aqua ones of macOS 10.14 in the light appearance: textured (rounded and
// square), recessed and round-rect buttons, textured segmented controls and pop-up buttons, search fields and the
// square and rounded bezels of text fields. The expected values were measured on renders of the same controls on
// Mac OS X 10.14.4 at 1x (black-box observation; QUIRK-tagged drawing in NSGraphicsStyle (NSTexturedControlsAqua,
// NSSearchFieldAqua, NSTextField), NSButtonCell, NSSegmentedCell, NSPopUpButtonCell, NSTextFieldCell and
// NSSearchFieldCell). Titles are drawn in fonts that differ between the systems, so only their colours are
// checked, not their shapes. Passes on macOS 10.14.4.
//
// Build: clang -framework AppKit appkit-toolbar-controls-aqua.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define NEAR(v, want, tol) ((v) >= (want) - (tol) && (v) <= (want) + (tol))

typedef struct {
    int gray, alpha, white; // unpremultiplied gray (red channel), alpha, and the value over a white background
    int r, g, b;
} Px;

// The controls are drawn in a key window of an active application, as in the renders the values come from: some of
// them look different in an inactive window.
@interface KeyWindow : NSWindow
@end
@implementation KeyWindow
- (BOOL) isKeyWindow {
    return YES;
}
- (BOOL) isMainWindow {
    return YES;
}
@end

@interface ActiveApplication : NSApplication
@end
@implementation ActiveApplication
- (BOOL) isActive {
    return YES;
}
@end

static NSWindow *window;

static NSBitmapImageRep *render(NSView *view) {
    if ([view window] != window) {
        [[window contentView] setSubviews: @[]];
        [[window contentView] addSubview: view];
    }
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    return rep;
}

// x and y in pixels from the top left corner of the render
static Px px(NSBitmapImageRep *rep, int x, int y) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    Px p;
    p.r = (int) lround([c redComponent] * 255);
    p.g = (int) lround([c greenComponent] * 255);
    p.b = (int) lround([c blueComponent] * 255);
    p.gray = p.r;
    p.alpha = (int) lround([c alphaComponent] * 255);
    p.white = (int) lround([c redComponent] * [c alphaComponent] * 255 + 255 * (1 - [c alphaComponent]));
    return p;
}

// the darkest and the brightest value over white in a rectangle of pixels
static void extremes(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1, int *darkest, int *brightest) {
    *darkest = 255;
    *brightest = 0;
    for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++) {
            Px p = px(rep, x, y);
            if (p.white < *darkest)
                *darkest = p.white;
            if (p.alpha > 230 && p.r > *brightest && p.r == p.g && p.g == p.b)
                *brightest = p.r;
        }
}

static void dump(const char *what, NSBitmapImageRep *rep, int x) {
    printf("%s column %d:", what, x);
    for (int y = 0; y < [rep pixelsHigh]; y++) {
        Px p = px(rep, x, y);
        printf(" %d/%d", p.gray, p.alpha);
    }
    printf("\n");
}

static NSButton *button(NSBezelStyle bezel, CGFloat height, NSControlSize size) {
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 60, height)] autorelease];
    [b setBezelStyle: bezel];
    [[b cell] setControlSize: size];
    [b setFont: [NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: size]]];
    [b setTitle: @""];
    [b setFrame: NSMakeRect(0, 0, 60, height)];
    return b;
}

static void setOn(NSButton *b, BOOL on) {
    [b setButtonType: NSPushOnPushOffButton];
    [b setState: on ? NSControlStateValueOn : NSControlStateValueOff];
}

static void test_quirk_textured_bezel(void) {
    NSButton *b = button(NSBezelStyleTexturedRounded, 23, NSControlSizeRegular);
    NSBitmapImageRep *rep = render(b);
    dump("textured", rep, 30);
    CHECK(px(rep, 30, 0).alpha >= 12 && px(rep, 30, 0).alpha <= 30);      // outline, black at 8%
    CHECK(px(rep, 30, 1).gray >= 250 && px(rep, 30, 1).alpha >= 240);     // white top line
    CHECK(NEAR(px(rep, 30, 10).gray, 250, 4) && NEAR(px(rep, 30, 10).alpha, 230, 10)); // light translucent fill
    CHECK(px(rep, 30, 20).gray < px(rep, 30, 3).gray);                    // the fill darkens downwards
    CHECK(NEAR(px(rep, 30, 21).alpha, 44, 12));                           // darker bottom line
    CHECK(px(rep, 30, 22).alpha <= 5);                                    // the point below the bezel is free
    CHECK(NEAR(px(rep, 0, 11).alpha, 20, 9));                             // side outline
    CHECK(px(rep, 0, 0).alpha <= 5 && px(rep, 1, 0).alpha <= 8);          // rounded corner
    CHECK(px(rep, 0, 2).alpha <= 15);

    [[b cell] setHighlighted: YES];
    rep = render(b);
    dump("textured pressed", rep, 30);
    CHECK(NEAR(px(rep, 30, 10).gray, 227, 6) && NEAR(px(rep, 30, 10).alpha, 232, 10));
    [[b cell] setHighlighted: NO];

    [b setEnabled: NO];
    rep = render(b);
    CHECK(NEAR(px(rep, 30, 10).gray, 250, 4) && NEAR(px(rep, 30, 10).alpha, 230, 10)); // disabled keeps the bezel
    [b setEnabled: YES];

    setOn(b, YES);
    rep = render(b);
    dump("textured on", rep, 30);
    CHECK(px(rep, 30, 10).gray <= 10 && NEAR(px(rep, 30, 10).alpha, 129, 12)); // black at 50%
    CHECK(NEAR(px(rep, 30, 0).alpha, 133, 12));
    CHECK(NEAR(px(rep, 30, 21).alpha, 145, 12));
    [[b cell] setHighlighted: YES];
    rep = render(b);
    CHECK(px(rep, 30, 10).gray <= 10 && NEAR(px(rep, 30, 10).alpha, 154, 12)); // pressed: 60%
    [[b cell] setHighlighted: NO];
    setOn(b, NO);

    // textured square: one point free at the top and the sides, two at the bottom
    NSButton *sq = button(NSBezelStyleTexturedSquare, 23, NSControlSizeRegular);
    rep = render(sq);
    dump("textured square", rep, 30);
    CHECK(px(rep, 30, 0).alpha <= 5);
    CHECK(NEAR(px(rep, 30, 1).alpha, 20, 9));
    CHECK(px(rep, 30, 2).gray >= 250 && px(rep, 30, 2).alpha >= 240);
    CHECK(NEAR(px(rep, 30, 20).alpha, 44, 12));
    CHECK(px(rep, 30, 21).alpha <= 5);
    CHECK(px(rep, 0, 11).alpha <= 5 && NEAR(px(rep, 1, 11).alpha, 20, 9));

    // the mini textured bezel is 16 points high with the free point
    NSButton *mini = button(NSBezelStyleTexturedRounded, 16, NSControlSizeMini);
    rep = render(mini);
    dump("textured mini", rep, 30);
    CHECK(NEAR(px(rep, 30, 0).alpha, 20, 9));
    CHECK(NEAR(px(rep, 30, 14).alpha, 44, 12));
    CHECK(px(rep, 30, 15).alpha <= 5);
}

static void test_quirk_bezel_heights(void) {
    // textured rounded: 23 points, centred, the odd point going below
    NSButton *b = button(NSBezelStyleTexturedRounded, 32, NSControlSizeRegular);
    NSBitmapImageRep *rep = render(b);
    dump("textured in 32", rep, 30);
    CHECK(px(rep, 30, 4).alpha <= 5);
    CHECK(NEAR(px(rep, 30, 5).alpha, 20, 9));
    CHECK(NEAR(px(rep, 30, 26).alpha, 44, 12));
    CHECK(px(rep, 30, 27).alpha <= 5);
    b = button(NSBezelStyleTexturedRounded, 25, NSControlSizeRegular);
    rep = render(b);
    CHECK(px(rep, 30, 0).alpha <= 5 && NEAR(px(rep, 30, 1).alpha, 20, 9) && NEAR(px(rep, 30, 22).alpha, 44, 12));

    // textured square follows the frame
    b = button(NSBezelStyleTexturedSquare, 32, NSControlSizeRegular);
    rep = render(b);
    CHECK(NEAR(px(rep, 30, 1).alpha, 20, 9) && NEAR(px(rep, 30, 29).alpha, 44, 12) && px(rep, 30, 30).alpha <= 5);

    // recessed and round-rect: 19 points
    b = button(NSBezelStyleRecessed, 25, NSControlSizeRegular);
    rep = render(b);
    dump("recessed in 25", rep, 30);
    CHECK(px(rep, 30, 2).alpha <= 5 && NEAR(px(rep, 30, 3).alpha, 82, 12) && NEAR(px(rep, 30, 20).alpha, 82, 12) &&
          px(rep, 30, 21).alpha <= 5);
    b = button(NSBezelStyleRoundRect, 25, NSControlSizeRegular);
    rep = render(b);
    dump("round rect in 25", rep, 30);
    CHECK(px(rep, 30, 2).alpha <= 5 && NEAR(px(rep, 30, 3).alpha, 77, 14) && NEAR(px(rep, 30, 20).alpha, 77, 14) &&
          px(rep, 30, 12).alpha <= 5);
}

static void test_quirk_recessed_bezel(void) {
    NSButton *b = button(NSBezelStyleRecessed, 19, NSControlSizeRegular);
    NSBitmapImageRep *rep = render(b);
    dump("recessed", rep, 30);
    CHECK(px(rep, 30, 9).gray <= 25 && NEAR(px(rep, 30, 9).alpha, 82, 12)); // translucent dark, also when off
    CHECK(NEAR(px(rep, 30, 0).alpha, 82, 12) && NEAR(px(rep, 30, 17).alpha, 82, 12) && px(rep, 30, 18).alpha <= 5);
    CHECK(px(rep, 0, 0).alpha <= 25 && NEAR(px(rep, 0, 9).alpha, 82, 12));
    setOn(b, YES);
    rep = render(b);
    CHECK(NEAR(px(rep, 30, 9).alpha, 94, 10));
    [[b cell] setHighlighted: YES];
    rep = render(b);
    CHECK(NEAR(px(rep, 30, 9).alpha, 125, 12));
    [[b cell] setHighlighted: NO];
    setOn(b, NO);
    [b setEnabled: NO];
    rep = render(b);
    CHECK(px(rep, 30, 9).alpha <= 5 && px(rep, 2, 9).alpha <= 5); // no bezel when disabled
}

static void test_quirk_round_rect_bezel(void) {
    NSButton *b = button(NSBezelStyleRoundRect, 19, NSControlSizeRegular);
    NSBitmapImageRep *rep = render(b);
    dump("round rect", rep, 30);
    CHECK(NEAR(px(rep, 30, 0).alpha, 77, 14) && NEAR(px(rep, 30, 17).alpha, 77, 14) && px(rep, 30, 18).alpha <= 5);
    CHECK(px(rep, 30, 9).alpha <= 5);                          // nothing inside
    CHECK(NEAR(px(rep, 0, 9).alpha, 77, 14) && px(rep, 0, 0).alpha <= 8);
    [[b cell] setHighlighted: YES];
    rep = render(b);
    CHECK(NEAR(px(rep, 30, 9).alpha, 26, 9) && NEAR(px(rep, 30, 0).alpha, 77, 14));
    [[b cell] setHighlighted: NO];
    setOn(b, YES);
    rep = render(b);
    CHECK(NEAR(px(rep, 30, 9).alpha, 26, 9));
    setOn(b, NO);
    [b setEnabled: NO];
    rep = render(b);
    CHECK(NEAR(px(rep, 30, 0).alpha, 39, 10) && px(rep, 30, 9).alpha <= 5);
}

static void test_quirk_title_colours(void) {
    int dark, bright;
    NSButton *b = button(NSBezelStyleTexturedRounded, 23, NSControlSizeRegular);
    [b setTitle: @"Button"];
    NSBitmapImageRep *rep = render(b);
    extremes(rep, 3, 3, 57, 19, &dark, &bright);
    printf("textured title darkest %d\n", dark);
    CHECK(dark >= 65 && dark <= 120); // black at about 65%
    [[b cell] setHighlighted: YES];
    rep = render(b);
    extremes(rep, 3, 3, 57, 19, &dark, &bright);
    printf("textured pressed title darkest %d\n", dark);
    CHECK(dark <= 65);
    [[b cell] setHighlighted: NO];
    [b setEnabled: NO];
    rep = render(b);
    extremes(rep, 3, 3, 57, 19, &dark, &bright);
    printf("textured disabled title darkest %d\n", dark);
    CHECK(dark >= 150 && dark <= 210);
    [b setEnabled: YES];
    setOn(b, YES);
    rep = render(b);
    extremes(rep, 3, 3, 57, 19, &dark, &bright);
    printf("textured on title brightest %d\n", bright);
    CHECK(bright >= 235); // white on the dark bezel

    NSButton *r = button(NSBezelStyleRecessed, 19, NSControlSizeRegular);
    [r setTitle: @"Button"];
    rep = render(r);
    extremes(rep, 3, 2, 57, 16, &dark, &bright);
    printf("recessed title darkest %d\n", dark);
    CHECK(dark <= 60);
    setOn(r, YES);
    rep = render(r);
    extremes(rep, 3, 2, 57, 16, &dark, &bright);
    printf("recessed on title brightest %d\n", bright);
    CHECK(bright >= 235);

    NSButton *rr = button(NSBezelStyleRoundRect, 19, NSControlSizeRegular);
    [rr setTitle: @"Button"];
    rep = render(rr);
    extremes(rep, 3, 2, 57, 16, &dark, &bright);
    printf("round rect title darkest %d\n", dark);
    CHECK(dark <= 60);
}

static NSSegmentedControl *segmented(NSSegmentStyle style, NSControlSize size) {
    NSSegmentedControl *sc = [[[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 200, 30)] autorelease];
    [sc setSegmentCount: 3];
    [sc setLabel: @"One" forSegment: 0];
    [sc setLabel: @"Two" forSegment: 1];
    [sc setLabel: @"Three" forSegment: 2];
    [sc setSegmentStyle: style];
    [[sc cell] setControlSize: size];
    [sc setFont: [NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: size]]];
    [[sc cell] setTrackingMode: NSSegmentSwitchTrackingSelectOne];
    [sc sizeToFit];
    return sc;
}

// the columns of row y that are darker than the bezel's fill but not dark (separator lines)
static int separators(NSBitmapImageRep *rep, int y, int *first) {
    int n = 0;
    *first = -1;
    for (int x = 3; x < [rep pixelsWide] - 3; x++) {
        Px p = px(rep, x, y);
        if (p.white < 240 && p.white > 200 && px(rep, x - 1, y).white > 240 && px(rep, x + 1, y).white > 240) {
            if (*first < 0)
                *first = x;
            n++;
        }
    }
    return n;
}

static void test_quirk_textured_segments(void) {
    NSSegmentedControl *sc = segmented(NSSegmentStyleTexturedRounded, NSControlSizeRegular);
    NSSegmentedControl *sq = segmented(NSSegmentStyleTexturedSquare, NSControlSizeRegular);
    printf("textured segmented %gx%g, square %gx%g\n", NSWidth([sc frame]), NSHeight([sc frame]), NSWidth([sq frame]),
           NSHeight([sq frame]));
    CHECK(NSHeight([sc frame]) == 23 && NSHeight([sq frame]) == 23);
    CHECK(NSWidth([sc frame]) == NSWidth([sq frame]) + 4); // the end segments of the rounded style are wider
    NSSegmentedControl *mini = segmented(NSSegmentStyleTexturedRounded, NSControlSizeMini);
    NSSegmentedControl *small = segmented(NSSegmentStyleTexturedRounded, NSControlSizeSmall);
    CHECK(NSHeight([small frame]) == 19 && NSHeight([mini frame]) == 16);

    // no selection: one bezel with two separators
    NSBitmapImageRep *rep = render(sc);
    int first, n = separators(rep, 4, &first);
    dump("segmented none", rep, 10);
    printf("separators %d, first at %d\n", n, first);
    CHECK(n == 2);
    if (first < 3) {
        fprintf(stderr, "FAIL: no separator found\n");
        failures++;
        return;
    }
    CHECK(NEAR(px(rep, 10, 0).alpha, 20, 9) && NEAR(px(rep, 10, 21).alpha, 44, 12) && px(rep, 10, 22).alpha <= 5);
    CHECK(NEAR(px(rep, 10, 10).gray, 250, 4) && NEAR(px(rep, 10, 10).alpha, 230, 10));
    // the separator spans the area between the outline lines
    CHECK(px(rep, first, 0).alpha < 40 && px(rep, first, 1).white < 245 && px(rep, first, 20).white < 245);

    // select one: the selected segment is dark with a white label, the separator next to it is gone
    [sc setSelectedSegment: 1];
    rep = render(sc);
    int mid = first + 10;
    dump("segmented selected", rep, mid);
    CHECK(px(rep, mid, 3).gray <= 10 && NEAR(px(rep, mid, 3).alpha, 128, 12));
    CHECK(NEAR(px(rep, first - 3, 3).alpha, 230, 10)); // the first segment stays light
    int dark, bright;
    extremes(rep, first + 2, 3, first + 30, 19, &dark, &bright);
    CHECK(bright >= 235);
    CHECK(separators(rep, 4, &n) == 0);
    [sc setEnabled: NO];
    rep = render(sc);
    CHECK(NEAR(px(rep, mid, 3).alpha, 128, 12)); // still dark when disabled
    [sc setEnabled: YES];

    // select any: a selected segment keeps the light bezel and shows its label in the accent colour
    [[sc cell] setTrackingMode: NSSegmentSwitchTrackingSelectAny];
    [sc setSelected: NO forSegment: 1];
    [sc setSelected: YES forSegment: 0];
    rep = render(sc);
    CHECK(NEAR(px(rep, 3, 3).alpha, 230, 10));
    int blue = 0;
    for (int y = 3; y < 19; y++)
        for (int x = 3; x < first; x++) {
            Px p = px(rep, x, y);
            blue += p.alpha > 200 && p.b - p.r > 100;
        }
    printf("blue label pixels %d\n", blue);
    CHECK(blue > 10);
    // a momentary control shows no selection
    [sc setSelected: NO forSegment: 0];
    [[sc cell] setTrackingMode: NSSegmentSwitchTrackingMomentary];
    [sc setSelected: YES forSegment: 1];
    rep = render(sc);
    CHECK(NEAR(px(rep, mid, 3).alpha, 230, 10));

    // in a taller frame the bezel is centred, the odd point going above
    [[sc cell] setTrackingMode: NSSegmentSwitchTrackingSelectOne];
    [sc setSelectedSegment: -1];
    [sc setFrameSize: NSMakeSize(NSWidth([sc frame]), 32)];
    rep = render(sc);
    dump("segmented in 32", rep, 10);
    CHECK(px(rep, 10, 3).alpha <= 5 && NEAR(px(rep, 10, 4).alpha, 20, 9) && NEAR(px(rep, 10, 25).alpha, 44, 12) &&
          px(rep, 10, 26).alpha <= 5);
}

static void test_quirk_textured_popup(void) {
    for (int pd = 0; pd < 2; pd++) {
        NSPopUpButton *p = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 23) pullsDown: pd] autorelease];
        if (pd)
            [p addItemWithTitle: @""];
        [p addItemsWithTitles: @[@"", @"Second"]];
        [p setBezelStyle: NSBezelStyleTexturedRounded];
        [p setFont: [NSFont systemFontOfSize: 13]];
        [p setFrame: NSMakeRect(0, 0, 100, 23)];
        NSRect title = [[p cell] titleRectForBounds: [p bounds]];
        printf("textured %s title rect {%g,%g,%g,%g}\n", pd ? "pull-down" : "pop-up", title.origin.x, title.origin.y,
               title.size.width, title.size.height);
        CHECK(NSMinX(title) == 7 && NSWidth(title) == (pd ? 76 : 77));
        NSBitmapImageRep *rep = render(p);
        dump("textured pop-up", rep, 91);
        CHECK(NEAR(px(rep, 50, 10).gray, 250, 4) && NEAR(px(rep, 50, 10).alpha, 230, 10)); // the textured bezel
        CHECK(px(rep, 50, 22).alpha <= 5);
        // the chevrons, centred 8.5 points left of the right edge: an up chevron over a down one, or one down
        // chevron in the middle of the bezel
        int up, down, middle, gap;
        extremes(rep, 87, 3, 96, 9, &up, &gap);
        extremes(rep, 87, 9, 96, 13, &middle, &gap);
        extremes(rep, 87, 13, 96, 19, &down, &gap);
        printf("chevrons %d %d %d\n", up, middle, down);
        if (pd)
            CHECK(middle < 150 && up > 225 && down > 225);
        else
            CHECK(up < 150 && down < 150 && middle > 225);
        [[p cell] setHighlighted: YES];
        rep = render(p);
        CHECK(NEAR(px(rep, 50, 10).gray, 227, 6));
    }
}

static void test_quirk_field_bezels(void) {
    NSTextField *t = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)] autorelease];
    NSBitmapImageRep *rep = render(t);
    CHECK(NEAR(px(rep, 70, 0).alpha, 51, 10) && NEAR(px(rep, 0, 11).alpha, 51, 10) && px(rep, 70, 11).white == 255);
    [t setEnabled: NO];
    rep = render(t);
    CHECK(NEAR(px(rep, 70, 0).alpha, 26, 8) && NEAR(px(rep, 0, 11).alpha, 26, 8)); // lighter when disabled
    [t setEnabled: YES];
    // the background colour fills the bezel inside a white line
    [t setDrawsBackground: YES];
    [t setBackgroundColor: [NSColor yellowColor]];
    rep = render(t);
    Px y = px(rep, 70, 11);
    CHECK(y.r > 240 && y.g > 240 && y.b < 30);
    CHECK(px(rep, 70, 1).b > 240);
    // without a background the bezel is still white
    [t setDrawsBackground: NO];
    rep = render(t);
    CHECK(px(rep, 70, 11).white == 255 && px(rep, 70, 11).alpha == 255);

    // the rounded bezel has a 4 point radius, and a fixed height centred in a taller frame
    NSTextField *r = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)] autorelease];
    [r setBezelStyle: NSTextFieldRoundedBezel];
    rep = render(r);
    dump("rounded field", rep, 0);
    CHECK(px(rep, 0, 0).alpha <= 5 && NEAR(px(rep, 0, 5).alpha, 51, 12) && NEAR(px(rep, 0, 11).alpha, 51, 10));
    CHECK(NEAR(px(rep, 70, 0).alpha, 51, 10) && px(rep, 70, 11).white == 255);
    [r setFrameSize: NSMakeSize(140, 32)];
    rep = render(r);
    dump("rounded field in 32", rep, 70);
    CHECK(px(rep, 70, 4).alpha <= 5 && NEAR(px(rep, 70, 5).alpha, 51, 10) && NEAR(px(rep, 70, 26).alpha, 51, 10) &&
          px(rep, 70, 27).alpha <= 5);

    NSSearchField *s = [[[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 160, 32)] autorelease];
    rep = render(s);
    CHECK(px(rep, 80, 4).alpha <= 5 && NEAR(px(rep, 80, 5).alpha, 51, 10) && NEAR(px(rep, 80, 26).alpha, 51, 10));
    [s setFrameSize: NSMakeSize(160, 22)];
    [s setEnabled: NO];
    rep = render(s);
    CHECK(NEAR(px(rep, 80, 0).alpha, 26, 8));

    // placeholders are drawn in the placeholder text colour, black at about 25%
    NSTextField *ph = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)] autorelease];
    [ph setPlaceholderString: @"Placeholder"];
    rep = render(ph);
    int dark, bright;
    extremes(rep, 2, 2, 138, 20, &dark, &bright);
    printf("placeholder darkest %d\n", dark);
    CHECK(dark >= 165 && dark <= 215);
}

static void test_quirk_search_glyphs(void) {
    NSSearchField *s = [[[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 160, 22)] autorelease];
    NSBitmapImageRep *rep = render(s);
    dump("search glass", rep, 6);
    // the magnifying glass: a ring about 10 points across centred at (11, 10), its handle down to the right
    CHECK(px(rep, 6, 9).white < 160 && px(rep, 15, 10).white < 160 && px(rep, 10, 5).white < 160 &&
          px(rep, 10, 14).white < 160);
    CHECK(px(rep, 11, 10).white > 240 && px(rep, 3, 10).white > 240);
    CHECK(px(rep, 16, 15).white < 190);
    // no cancel disc while empty
    CHECK(px(rep, 149, 5).white > 240);

    [s setStringValue: @"query"];
    rep = render(s);
    dump("search cancel", rep, 149);
    // the cancel disc: 14 points, black at 50%, a white cross
    CHECK(NEAR(px(rep, 149, 5).white, 127, 20) && NEAR(px(rep, 143, 11).white, 127, 25));
    CHECK(px(rep, 149, 3).white > 240 && px(rep, 149, 18).white > 240);
    CHECK(px(rep, 149, 11).white > 200 || px(rep, 149, 10).white > 200);
    [s setEnabled: NO];
    rep = render(s);
    CHECK(NEAR(px(rep, 149, 5).white, 127, 25)); // the same when disabled

    // the small field has a smaller glass and a smaller disc
    NSSearchField *small = [[[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 160, 19)] autorelease];
    [[small cell] setControlSize: NSControlSizeSmall];
    [small setFont: [NSFont systemFontOfSize: 11]];
    [small setStringValue: @"query"];
    rep = render(small);
    dump("small search glass", rep, 11);
    CHECK(px(rep, 11, 9).white > 240 && px(rep, 7, 8).white < 180 && px(rep, 5, 9).white > 240);
    int dark, bright;
    extremes(rep, 140, 2, 158, 17, &dark, &bright);
    printf("small cancel darkest %d\n", dark);
    CHECK(NEAR(dark, 127, 25));
    CHECK(px(rep, 150, 2).white > 240 && px(rep, 150, 16).white > 240);
}

int main(void) {
    @autoreleasepool {
        [ActiveApplication sharedApplication];
        window = [[KeyWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                              styleMask: NSWindowStyleMaskTitled
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
        [window makeKeyAndOrderFront: nil];
        test_quirk_textured_bezel();
        test_quirk_bezel_heights();
        test_quirk_recessed_bezel();
        test_quirk_round_rect_bezel();
        test_quirk_title_colours();
        test_quirk_textured_segments();
        test_quirk_textured_popup();
        test_quirk_field_bezels();
        test_quirk_search_glyphs();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
