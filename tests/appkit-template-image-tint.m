// Copyright (C) 2026 Lubos Dolezel
//
// Template images are drawn as masks in a colour the control chooses, not in their own colours.
// The image is a red 10 x 10 square in a 16 x 16 image. Observed on macOS 10.14.4 (black-box, light
// appearance), and checked here:
//  - test_quirk_template_image_colours: black at 50 % opacity in a borderless button and in an image
//    view, 25 % when the button is disabled; white on the dark bezel of a textured button in its on state;
//    a bordered button never shows the image's red. A plain (not template) image keeps its colours.
//  - test_quirk_textured_segment_selected_template: in a textured segmented control a selected segment
//    with a template image shows it in the accent colour (blue) and keeps the bezel of an unselected one;
//    an unselected segment shows it in gray.
// Passes on macOS 10.14.4.
//
// Build: clang -framework AppKit appkit-template-image-tint.m
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

typedef struct {
    CGFloat r, g, b, a;
} Pixel;

static NSImage *redSquare(BOOL isTemplate) {
    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(16, 16)];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1] set];
    NSRectFill(NSMakeRect(3, 3, 10, 10));
    [image unlockFocus];
    [image setTemplate: isTemplate];
    return [image autorelease];
}

// The colour at a point of the view (in its coordinates), unpremultiplied.
static Pixel sample(NSView *view, NSPoint point) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    CGFloat sx = [rep pixelsWide] / NSWidth([view bounds]), sy = [rep pixelsHigh] / NSHeight([view bounds]);
    NSInteger x = (NSInteger) (point.x * sx);
    NSInteger y = (NSInteger) (([view isFlipped] ? point.y : NSHeight([view bounds]) - point.y) * sy);
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    Pixel p = {[c redComponent], [c greenComponent], [c blueComponent], [c alphaComponent]};
    return p;
}

static void print(const char *what, Pixel p) {
    printf("%-40s (%.2f %.2f %.2f a%.2f)\n", what, p.r, p.g, p.b, p.a);
}

static NSButton *button(NSView *content, NSImage *image, BOOL bordered, NSBezelStyle bezel, NSInteger state) {
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect(10, 60, 40, 25)] autorelease];
    [b setButtonType: NSPushOnPushOffButton];
    [b setBezelStyle: bezel];
    [b setBordered: bordered];
    [b setImage: image];
    [b setImagePosition: NSImageOnly];
    [b setState: state];
    [content addSubview: b];
    return b;
}

static NSPoint middle(NSView *v) {
    return NSMakePoint(NSMidX([v bounds]), NSMidY([v bounds]));
}

static void test_quirk_template_image_colours(NSView *content) {
    NSImage *tmpl = redSquare(YES), *plain = redSquare(NO);

    NSButton *b = button(content, tmpl, NO, NSRegularSquareBezelStyle, 0);
    Pixel p = sample(b, middle(b));
    print("borderless", p);
    CHECK(p.r < 0.1 && p.g < 0.1 && p.b < 0.1 && fabs(p.a - 0.5) < 0.1);
    [b setEnabled: NO];
    p = sample(b, middle(b));
    print("borderless disabled", p);
    CHECK(p.r < 0.1 && fabs(p.a - 0.25) < 0.1);
    [b removeFromSuperview];

    b = button(content, plain, NO, NSRegularSquareBezelStyle, 0);
    p = sample(b, middle(b));
    print("borderless, plain image", p);
    CHECK(p.r > 0.9 && p.g < 0.1 && p.a > 0.9);
    [b removeFromSuperview];

    b = button(content, tmpl, YES, NSTexturedRoundedBezelStyle, 1);
    p = sample(b, middle(b));
    print("textured, on", p);
    CHECK(p.r > 0.9 && p.g > 0.9 && p.b > 0.9);
    [b removeFromSuperview];

    NSBezelStyle styles[3] = {NSRoundedBezelStyle, NSRegularSquareBezelStyle, NSTexturedRoundedBezelStyle};
    for (int s = 0; s < 3; s++) {
        b = button(content, tmpl, YES, styles[s], 0);
        p = sample(b, middle(b));
        print("bordered", p);
        // dark gray, never the red of the image
        CHECK(fabs(p.r - p.g) < 0.1 && fabs(p.g - p.b) < 0.1 && p.r < 0.6);
        [b removeFromSuperview];
    }

    NSImageView *view = [[[NSImageView alloc] initWithFrame: NSMakeRect(10, 100, 30, 30)] autorelease];
    [view setImage: tmpl];
    [content addSubview: view];
    p = sample(view, middle(view));
    print("image view", p);
    CHECK(p.r < 0.1 && p.g < 0.1 && fabs(p.a - 0.5) < 0.1);
    [view removeFromSuperview];
}

static void test_quirk_textured_segment_selected_template(NSView *content) {
    NSSegmentedControl *seg = [[[NSSegmentedControl alloc] initWithFrame: NSMakeRect(10, 10, 100, 25)] autorelease];
    [seg setSegmentCount: 2];
    [seg setSegmentStyle: NSSegmentStyleTexturedRounded];
    [[seg cell] setTrackingMode: NSSegmentSwitchTrackingSelectAny];
    [seg setImage: redSquare(YES) forSegment: 0];
    [seg setImage: redSquare(YES) forSegment: 1];
    [seg setWidth: 45 forSegment: 0];
    [seg setWidth: 45 forSegment: 1];
    [seg setSelected: YES forSegment: 0];
    [content addSubview: seg];
    CGFloat y = NSMidY([seg bounds]);
    Pixel selectedGlyph = sample(seg, NSMakePoint(24, y));
    Pixel selectedBezel = sample(seg, NSMakePoint(10, y));
    Pixel glyph = sample(seg, NSMakePoint(70, y));
    Pixel bezel = sample(seg, NSMakePoint(56, y));
    print("selected segment glyph", selectedGlyph);
    print("selected segment bezel", selectedBezel);
    print("segment glyph", glyph);
    print("segment bezel", bezel);
    CHECK(selectedGlyph.b > 0.8 && selectedGlyph.r < 0.3);
    CHECK(fabs(selectedBezel.r - bezel.r) < 0.1 && fabs(selectedBezel.b - bezel.b) < 0.1);
    CHECK(fabs(glyph.r - glyph.g) < 0.1 && fabs(glyph.g - glyph.b) < 0.1 && glyph.r < 0.6);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if ([NSApp respondsToSelector: @selector(setAppearance:)])
            [NSApp setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window makeKeyAndOrderFront: nil];
        test_quirk_template_image_colours([window contentView]);
        test_quirk_textured_segment_selected_template([window contentView]);
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
