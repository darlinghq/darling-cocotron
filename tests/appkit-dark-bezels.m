// Copyright (C) 2026 Lubos Dolezel
//
// Under NSAppearanceNameDarkAqua the bezels that NSButtonCell, NSPopUpButtonCell and textured NSSegmentedCell draw
// are dark: light-on-dark translucent bezels with light titles (a dark title on the light on-state bezel of textured
// and recessed buttons), and the Aqua appearance keeps its light bezels. Each style and state is rendered into a
// bitmap over a mid-dark backdrop with -cacheDisplayInRect:toBitmapImageRep:, the luminance of the bezel is sampled
// beside the title and the title's contrast with it is measured.
// Expected luminance ranges follow renders of the same buttons on macOS 10.14.4 (black-box observation; the dark
// bezels are QUIRK-tagged drawing in NSGraphicsStyle, NSButtonCell and NSSegmentedCell).
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

static NSWindow *aqua, *dark;

static double luma(NSBitmapImageRep *rep, int x, int y) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

    return 0.299 * [c redComponent] + 0.587 * [c greenComponent] + 0.114 * [c blueComponent];
}

typedef struct { double bezel, minLuma, maxLuma; } Sample;

// renders view over the backdrop; returns the bitmap (the view sits at (8, 8) of a 16 point larger backdrop)
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

// the bezel luminance at the left of the control, the darkest and brightest pixels of the title area
static Sample measure(NSBitmapImageRep *rep, int width, int height) {
    Sample s = {luma(rep, 8 + 12, 8 + height / 2), 1, 0};

    for (int x = 8 + width * 0.3; x < 8 + width * 0.7; x++)
        for (int y = 8 + height * 0.3; y < 8 + height * 0.7; y++) {
            double l = luma(rep, x, y);

            s.minLuma = MIN(s.minLuma, l);
            s.maxLuma = MAX(s.maxLuma, l);
        }
    return s;
}

enum { Normal, Pressed, Disabled, On };
static const char *stateNames[] = {"normal", "pressed", "disabled", "on"};

static NSButton *makeButton(NSInteger bezel, NSInteger type, int state, NSString *title) {
    NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 96, 32)];

    [b setButtonType: type];
    [b setBezelStyle: bezel];
    [b setTitle: title];
    if (state == Pressed) [[b cell] setHighlighted: YES];
    if (state == Disabled) [b setEnabled: NO];
    if (state == On) [b setState: NSOnState];
    return b;
}

// Checks one button style and state: the bezel luminance is in [lo, hi] in the dark appearance (and at least litMin
// in Aqua), and the title is lighter (titleLighter) or darker than the bezel by at least 0.25 in the dark appearance.
static void checkButton(const char *name, NSInteger bezel, NSInteger type, int state, double lo, double hi, double litMin,
                        int titleLighter)
{
    NSBitmapImageRep *d = render(dark, makeButton(bezel, type, state, @"Push"));
    NSBitmapImageRep *a = render(aqua, makeButton(bezel, type, state, @"Push"));
    Sample sd = measure(d, 96, 32), sa = measure(a, 96, 32);

    CHECK(sd.bezel >= lo && sd.bezel <= hi, "%s %s dark bezel luma %.2f not in [%.2f, %.2f]", name, stateNames[state], sd.bezel, lo, hi);
    if (litMin >= 0)
        CHECK(sa.bezel >= litMin, "%s %s Aqua bezel luma %.2f below %.2f", name, stateNames[state], sa.bezel, litMin);
    if (titleLighter > 0)
        CHECK(sd.maxLuma - sd.bezel >= 0.25, "%s %s dark title (max %.2f) not lighter than the bezel (%.2f)", name, stateNames[state], sd.maxLuma, sd.bezel);
    else if (titleLighter < 0)
        CHECK(sd.bezel - sd.minLuma >= 0.25, "%s %s dark title (min %.2f) not darker than the bezel (%.2f)", name, stateNames[state], sd.minLuma, sd.bezel);
}

static void testButtons(void) {
    // rounded push button: translucent light grey in the dark appearance, white in Aqua
    checkButton("rounded", NSRoundedBezelStyle, NSMomentaryPushInButton, Normal, 0.30, 0.55, 0.9, 1);
    checkButton("rounded", NSRoundedBezelStyle, NSMomentaryPushInButton, Disabled, 0.20, 0.40, 0.55, 0);
    // pressed: blue in both appearances, with light title
    {
        NSBitmapImageRep *d = render(dark, makeButton(NSRoundedBezelStyle, NSMomentaryPushInButton, Pressed, @"Push"));
        NSColor *c = [[d colorAtX: 20 y: 8 + 16] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
        Sample s = measure(d, 96, 32);

        CHECK([c blueComponent] > [c redComponent] + 0.3, "rounded pressed dark is not blue");
        CHECK(s.maxLuma > 0.8, "rounded pressed dark title is not light");
    }
    checkButton("regularsquare", NSRegularSquareBezelStyle, NSMomentaryPushInButton, Normal, 0.25, 0.50, 0.75, 1);
    checkButton("regularsquare", NSRegularSquareBezelStyle, NSMomentaryPushInButton, Pressed, 0.30, 0.60, 0.65, 1);
    checkButton("shadowless", NSShadowlessSquareBezelStyle, NSMomentaryPushInButton, Normal, 0.20, 0.50, 0.70, 1);
    checkButton("shadowless", NSShadowlessSquareBezelStyle, NSMomentaryPushInButton, Pressed, 0.25, 0.60, 0.45, 1);
    checkButton("textured", NSTexturedRoundedBezelStyle, NSPushOnPushOffButton, Normal, 0.30, 0.55, 0.9, 1);
    checkButton("textured", NSTexturedRoundedBezelStyle, NSPushOnPushOffButton, Pressed, 0.38, 0.65, 0.80, 1);
    checkButton("textured", NSTexturedRoundedBezelStyle, NSPushOnPushOffButton, Disabled, 0.30, 0.55, 0.9, 0);
    checkButton("textured", NSTexturedRoundedBezelStyle, NSPushOnPushOffButton, On, 0.55, 0.85, -1, -1);
    checkButton("texturedsquare", NSTexturedSquareBezelStyle, NSPushOnPushOffButton, Normal, 0.30, 0.55, 0.9, 1);
    checkButton("texturedsquare", NSTexturedSquareBezelStyle, NSPushOnPushOffButton, On, 0.55, 0.85, -1, -1);
    checkButton("recessed", NSRecessedBezelStyle, NSPushOnPushOffButton, Normal, 0.30, 0.55, -1, 1);
    checkButton("recessed", NSRecessedBezelStyle, NSPushOnPushOffButton, Pressed, 0.38, 0.65, -1, 1);
    checkButton("recessed", NSRecessedBezelStyle, NSPushOnPushOffButton, On, 0.50, 0.80, -1, -1);
    // round rect: only an outline and a faint fill; the title is light
    {
        NSBitmapImageRep *d = render(dark, makeButton(NSRoundRectBezelStyle, NSPushOnPushOffButton, Normal, @"Push"));
        // the outline's left edge, at the control's left edge and 16 high
        double edgeDark = MAX(luma(d, 8, 8 + 16), luma(d, 8 + 1, 8 + 16));
        Sample s = measure(d, 96, 32);

        CHECK(edgeDark > 50 / 255.0 + 0.1, "roundrect dark outline luma %.2f is not lighter than the backdrop", edgeDark);
        CHECK(s.maxLuma - s.bezel >= 0.25, "roundrect dark title not light");
    }
}

static void testToggles(void) {
    for (int radio = 0; radio < 2; radio++)
        for (int on = 0; on < 2; on++) {
            NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 96, 20)];
            [b setButtonType: radio ? NSRadioButton : NSSwitchButton];
            [b setTitle: @"Title"];
            if (on) [b setState: NSOnState];
            NSBitmapImageRep *d = render(dark, b);
            // the box of the 14 or 16 point box sits 2 points in from the left; sample off its centre, left of the mark
            double l = luma(d, 8 + 2 + 3, 8 + 10);

            if (!on)
                CHECK(l >= 0.2 && l <= 0.55, "%s off dark box luma %.2f", radio ? "radio" : "checkbox", l);
            // the title is light in the dark appearance
            double maxTitle = 0;
            for (int x = 8 + 22; x < 8 + 60; x++)
                for (int y = 8 + 4; y < 8 + 16; y++)
                    maxTitle = MAX(maxTitle, luma(d, x, y));
            CHECK(maxTitle > 0.7, "%s dark title not light (%.2f)", radio ? "radio" : "checkbox", maxTitle);
            if (!on) {
                NSButton *b2 = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 96, 20)];
                [b2 setButtonType: radio ? NSRadioButton : NSSwitchButton];
                [b2 setTitle: @"Title"];
                NSBitmapImageRep *a = render(aqua, b2);
                CHECK(luma(a, 8 + 2 + 3, 8 + 10) > 0.85, "%s off Aqua box is not white", radio ? "radio" : "checkbox");
            }
        }
}

static void testPopUp(void) {
    NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 96, 26) pullsDown: NO];
    [p addItemsWithTitles: @[@"Pop", @"Two"]];
    NSBitmapImageRep *d = render(dark, p);
    // left of the title, in the body of the bezel
    double l = luma(d, 8 + 8, 8 + 13);
    CHECK(l >= 0.28 && l <= 0.56, "popup dark bezel luma %.2f", l);
    // the chevrons of the end cap are light (when the cap is blue, white on blue; when not, light on grey)
    double brightest = 0;
    for (int x = 8 + 96 - 14; x < 8 + 96 - 3; x++)
        for (int y = 8 + 4; y < 8 + 22; y++)
            brightest = MAX(brightest, luma(d, x, y));
    CHECK(brightest > 0.75, "popup dark chevrons luma %.2f", brightest);

    NSPopUpButton *t = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 96, 26) pullsDown: NO];
    [t setBezelStyle: NSTexturedRoundedBezelStyle];
    [t addItemsWithTitles: @[@"Pop", @"Two"]];
    d = render(dark, t);
    l = luma(d, 8 + 4, 8 + 13);
    CHECK(l >= 0.28 && l <= 0.56, "textured popup dark bezel luma %.2f", l);
    brightest = 0;
    for (int x = 8 + 96 - 14; x < 8 + 96 - 3; x++)
        for (int y = 8 + 4; y < 8 + 22; y++)
            brightest = MAX(brightest, luma(d, x, y));
    CHECK(brightest - l > 0.3, "textured popup dark chevrons are not light on the bezel (%.2f on %.2f)", brightest, l);
}

static void testSegments(void) {
    NSSegmentedControl *s = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(0, 0, 150, 26)];
    [s setSegmentCount: 3];
    for (int i = 0; i < 3; i++) {
        [s setLabel: [NSString stringWithFormat: @"S%d", i] forSegment: i];
        [s setWidth: 48 forSegment: i];
    }
    [s setSegmentStyle: NSSegmentStyleTexturedRounded];
    [s setTrackingMode: NSSegmentSwitchTrackingSelectOne];
    [s setSelectedSegment: 1];
    NSBitmapImageRep *d = render(dark, s);
    double unselected = luma(d, 8 + 4, 8 + 13), selected = luma(d, 8 + 48 + 6, 8 + 13);

    CHECK(unselected >= 0.28 && unselected <= 0.58, "textured segment dark bezel luma %.2f", unselected);
    CHECK(selected > unselected + 0.15, "selected textured segment is not lighter (%.2f vs %.2f)", selected, unselected);
    // the selected label is dark on the light bezel, the others light on the dark one
    double minSel = 1, maxOther = 0;
    for (int x = 8 + 48 + 14; x < 8 + 48 + 34; x++)
        for (int y = 8 + 6; y < 8 + 20; y++)
            minSel = MIN(minSel, luma(d, x, y));
    for (int x = 8 + 14; x < 8 + 34; x++)
        for (int y = 8 + 6; y < 8 + 20; y++)
            maxOther = MAX(maxOther, luma(d, x, y));
    CHECK(selected - minSel > 0.25, "selected segment label not dark (%.2f on %.2f)", minSel, selected);
    CHECK(maxOther - unselected > 0.25, "segment label not light (%.2f on %.2f)", maxOther, unselected);
}

int main(void) {
    @autoreleasepool {
        [ActiveApp sharedApplication];
        aqua = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100) styleMask: NSTitledWindowMask
                                                 backing: NSBackingStoreBuffered defer: NO];
        dark = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100) styleMask: NSTitledWindowMask
                                                 backing: NSBackingStoreBuffered defer: NO];
        [aqua setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
        [dark setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]];
        testButtons();
        testToggles();
        testPopUp();
        testSegments();
    }
    printf("%s: %d checks, %d failures\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures != 0;
}
