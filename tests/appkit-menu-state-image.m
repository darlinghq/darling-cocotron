// Copyright (C) 2026 Lubos Dolezel
//
// The state of a menu item is shown by an image: -onStateImage is a template check mark, -mixedStateImage a
// template dash, -offStateImage nil, and each can be replaced (nil removes it). Menus draw those images in the
// item's text colour (templates) or as they are, never as a text glyph from a font.
// The API part was observed on macOS 26.7.3 (black-box, x86_64): onStateImage is the named image NSMenuCheckmark
// (18x16, template), mixedStateImage NSMenuMixedState (18x4, template), offStateImage nil; setting nil gives nil.
// The drawing part renders Darling's menu views (NSSubmenuView for a menu, NSPopUpView for the menu of a pop-up
// button) and runs only where those classes exist; the check mark must look like the template image, not like a
// letter.
#import <AppKit/AppKit.h>
#import <objc/message.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void testAPI(void) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"x" action: NULL keyEquivalent: @""];
    NSImage *on = [item onStateImage], *mixed = [item mixedStateImage];
    CHECK(on != nil);
    CHECK([[on name] isEqualToString: @"NSMenuCheckmark"]);
    CHECK([on isTemplate]);
    CHECK(on == [NSImage imageNamed: @"NSMenuCheckmark"]);
    CHECK(mixed != nil);
    CHECK([[mixed name] isEqualToString: @"NSMenuMixedState"]);
    CHECK([mixed isTemplate]);
    CHECK([item offStateImage] == nil);

    NSImage *custom = [[NSImage alloc] initWithSize: NSMakeSize(5, 5)];
    [item setOnStateImage: custom];
    CHECK([item onStateImage] == custom);
    [item setOnStateImage: nil];
    CHECK([item onStateImage] == nil);
    [item setOffStateImage: custom];
    CHECK([item offStateImage] == custom);

    // Items made by the menu's own conveniences and copies have the same defaults.
    NSMenu *menu = [[NSMenu alloc] initWithTitle: @"m"];
    NSMenuItem *added = [menu addItemWithTitle: @"a" action: NULL keyEquivalent: @""];
    CHECK([[added onStateImage] isEqual: on]);
    NSMenuItem *copy = [added copy];
    CHECK([[copy onStateImage] isEqual: on]);
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 22) pullsDown: NO];
    [popup addItemWithTitle: @"5"];
    CHECK([[[popup itemAtIndex: 0] onStateImage] isEqual: on]);
}

static double lum(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    CGFloat r, g, b, a;
    [c getRed: &r green: &g blue: &b alpha: &a];
    return (r + g + b) / 3;
}

// Normalised correlation of the view's ink (distance from the background at the left edge) with the alpha of the
// image, best over all positions in the first 34 columns. About 1 when the image is drawn.
static double bestCorrelation(NSBitmapImageRep *rep, NSImage *image) {
    NSBitmapImageRep *mask = [NSBitmapImageRep imageRepWithData: [image TIFFRepresentation]];
    NSInteger mw = [mask pixelsWide], mh = [mask pixelsHigh];
    NSInteger W = [rep pixelsWide], H = [rep pixelsHigh];
    double best = 0;
    for (NSInteger oy = -2; oy <= H - mh + 2; oy++) {
        for (NSInteger ox = 0; ox <= 34 - mw && ox + mw <= W; ox++) {
            double sxy = 0, sxx = 0, syy = 0;
            for (NSInteger y = 0; y < mh; y++) {
                NSInteger py = oy + y;
                if (py < 0 || py >= H)
                    continue;
                double bg = lum(rep, 1, py);
                for (NSInteger x = 0; x < mw; x++) {
                    double ink = fabs(lum(rep, ox + x, py) - bg);
                    double alpha = [[mask colorAtX: x y: y] alphaComponent];
                    sxy += ink * alpha;
                    sxx += ink * ink;
                    syy += alpha * alpha;
                }
            }
            if (sxx > 0 && syy > 0 && sxy / sqrt(sxx * syy) > best)
                best = sxy / sqrt(sxx * syy);
        }
    }
    return best;
}

static double inkInColumns(NSBitmapImageRep *rep, NSInteger x0, NSInteger x1) {
    double total = 0;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++) {
        double bg = lum(rep, 1, y);
        for (NSInteger x = x0; x < x1; x++)
            total += fabs(lum(rep, x, y) - bg);
    }
    return total;
}

static NSBitmapImageRep *render(NSView *view) {
    NSRect b = [view bounds];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: b];
    [view cacheDisplayInRect: b toBitmapImageRep: rep];
    return rep;
}

static NSView *submenuView(NSMenu *menu, NSInteger selected) {
    NSView *view = [[NSClassFromString(@"NSSubmenuView") alloc] performSelector: @selector(initWithMenu:)
                                                                    withObject: menu];
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(view, @selector(setSelectedItemIndex:), selected);
    return view;
}

static NSView *popUpView(NSMenu *menu, NSInteger selected) {
    NSView *view = [[NSClassFromString(@"NSPopUpView") alloc] initWithFrame: NSMakeRect(0, 0, 140, 40)];
    [view setMenu: menu];
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(view, @selector(selectItemAtIndex:), selected);
    NSSize size = ((NSSize (*)(id, SEL))objc_msgSend)(view, @selector(sizeForContents));
    [view setFrameSize: size];
    return view;
}

static NSMenu *oneItemMenu(NSControlStateValue state) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle: @"m"];
    [menu setAutoenablesItems: NO];
    NSMenuItem *item = [menu addItemWithTitle: @"Show 5 recent tracks" action: @selector(self) keyEquivalent: @""];
    [item setTarget: menu];
    [item setState: state];
    return menu;
}

static void testDrawing(NSView *(*make)(NSMenu *, NSInteger), const char *kind) {
    NSImage *check = [NSImage imageNamed: @"NSMenuCheckmark"];
    NSImage *dash = [NSImage imageNamed: @"NSMenuMixedState"];

    // The popup view marks the initially selected item with the check mark whatever its state; for a menu the
    // state decides. Not selected (-1) in the menu view, so the row is not highlighted.
    NSInteger sel = make == popUpView ? 0 : -1;
    double on = bestCorrelation(render(make(oneItemMenu(NSControlStateValueOn), sel)), check);
    if (on < 0.8)
        fprintf(stderr, "%s: check mark correlation %.2f\n", kind, on);
    CHECK(on >= 0.8);

    if (make == submenuView) {
        NSBitmapImageRep *offRep = render(make(oneItemMenu(NSControlStateValueOff), -1));
        double offInk = inkInColumns(offRep, 2, 10);
        if (offInk >= 0.5)
            fprintf(stderr, "%s: off item has %.2f ink in the state column\n", kind, offInk);
        CHECK(offInk < 0.5);
        double mixed = bestCorrelation(render(make(oneItemMenu(NSControlStateValueMixed), -1)), dash);
        if (mixed < 0.8)
            fprintf(stderr, "%s: dash correlation %.2f\n", kind, mixed);
        CHECK(mixed >= 0.8);
    }

    // A custom, non-template image is drawn as it is.
    NSMenu *menu = oneItemMenu(NSControlStateValueOn);
    NSImage *red = [[NSImage alloc] initWithSize: NSMakeSize(10, 10)];
    [red lockFocus];
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 10, 10));
    [red unlockFocus];
    [[[menu itemArray] objectAtIndex: 0] setOnStateImage: red];
    NSBitmapImageRep *rep = render(make(menu, sel));
    int redPixels = 0;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
        for (NSInteger x = 0; x < 34 && x < [rep pixelsWide]; x++) {
            NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
            if ([c redComponent] > 0.8 && [c greenComponent] < 0.3 && [c blueComponent] < 0.3)
                redPixels++;
        }
    if (redPixels < 40)
        fprintf(stderr, "%s: %d red pixels\n", kind, redPixels);
    CHECK(redPixels >= 40);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        testAPI();
        if (NSClassFromString(@"NSSubmenuView") != Nil && NSClassFromString(@"NSPopUpView") != Nil) {
            testDrawing(submenuView, "menu");
            testDrawing(popUpView, "pop-up");
        } else
            puts("SKIP drawing: not Darling's AppKit");
    }
    puts(failures ? "FAIL" : "PASS");
    return failures != 0;
}
