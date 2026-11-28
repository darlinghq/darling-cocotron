// Copyright (C) 2026 Lubos Dolezel
//
// A check box, radio button or borderless button that is the window's default button cell (or whose key equivalent
// is Return, which makes it the default cell) draws exactly what it draws otherwise: it has no bezel to emphasise.
// It used to be drawn over a black rectangle. Each control is rendered with -cacheDisplayInRect:toBitmapImageRep:
// with and without being the default cell, in the Aqua and the DarkAqua appearance; the two renderings must be
// identical and the control's area must not be filled with black.
// The expectation is the observation of a rendering on macOS 10.14.4 and 26.7.3 (identical with and without the
// default cell for these controls), tier 2 black-box.
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

static NSBitmapImageRep *render(NSWindow *w, NSButton *b, BOOL makeDefault) {
    [[w contentView] setSubviews: @[]];
    [[w contentView] addSubview: b];
    [w setDefaultButtonCell: nil];
    if (makeDefault) {
        [b setKeyEquivalent: @"\r"];
        [w setDefaultButtonCell: [b cell]];
    }
    [b displayIfNeeded];
    NSBitmapImageRep *rep = [b bitmapImageRepForCachingDisplayInRect: [b bounds]];
    [b cacheDisplayInRect: [b bounds] toBitmapImageRep: rep];
    return rep;
}

static BOOL blackPixels(NSBitmapImageRep *rep) {
    // the control area is mostly the window colour: a black fill shows as many opaque near-black pixels
    int black = 0, w = (int) [rep pixelsWide], h = (int) [rep pixelsHigh];

    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

            if ([c alphaComponent] > 0.9 && [c redComponent] < 0.1 && [c greenComponent] < 0.1 && [c blueComponent] < 0.1)
                black++;
        }
    return black > w * h / 4;
}

static void probe(NSWindow *w, const char *look, const char *name, NSInteger type, BOOL bordered, BOOL on) {
    NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 120, 24)];

    [b setButtonType: type];
    if (type == NSMomentaryPushInButton)
        [b setBezelStyle: NSRoundedBezelStyle];
    if (type != NSSwitchButton && type != NSRadioButton)
        [b setBordered: bordered];
    [b setTitle: @"Title"];
    if (on)
        [b setState: NSOnState];
    NSBitmapImageRep *plain = [render(w, b, NO) retain];
    NSBitmapImageRep *dflt = render(w, b, YES);

    CHECK([plain bytesPerRow] == [dflt bytesPerRow] &&
          memcmp([plain bitmapData], [dflt bitmapData], [plain bytesPerRow] * [plain pixelsHigh]) == 0,
          "%s %s%s: the default cell draws differently from the same cell otherwise", look, name, on ? " (on)" : "");
    CHECK(!blackPixels(dflt), "%s %s%s: a black rectangle is drawn for the default cell", look, name, on ? " (on)" : "");
    [plain release];
    [b release];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (int d = 0; d < 2; d++) {
            NSWindow *w = [[ActiveWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 100)
                                                          styleMask: NSTitledWindowMask
                                                            backing: NSBackingStoreBuffered defer: NO];
            const char *look = d ? "dark" : "aqua";

            [w setAppearance: [NSAppearance appearanceNamed: d ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
            probe(w, look, "check box", NSSwitchButton, YES, NO);
            probe(w, look, "check box", NSSwitchButton, YES, YES);
            probe(w, look, "radio button", NSRadioButton, YES, NO);
            probe(w, look, "radio button", NSRadioButton, YES, YES);
            probe(w, look, "borderless push button", NSMomentaryPushInButton, NO, NO);
            probe(w, look, "borderless toggle button", NSPushOnPushOffButton, NO, NO);
            [w release];
        }
    }
    printf("%s: %d checks, %d failures\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures != 0;
}
