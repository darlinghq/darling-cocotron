// Copyright (C) 2026 Lubos Dolezel
//
// +[NSImage imageWithSystemSymbolName:accessibilityDescription:] draws the shape of the named symbol. The
// documentation (https://developer.apple.com/documentation/appkit/nsimage/init(systemsymbolname:accessibilitydescription:))
// names the symbol by its SF Symbols name; the shape drawn for "plus" is a plus sign (two bars crossing at the
// centre, nothing in the corners), for "xmark" a cross of two diagonal strokes (nothing at the middles of the
// edges), and for "magnifyingglass" a lens with a handle towards the bottom right. Observed on macOS 26.7.3
// (x86_64) by drawing the template image in black into a 32 x 32 bitmap: for "plus" the centre and the
// middles of the four arms are opaque and the four corners clear; for "xmark" the centre is opaque and the
// middle of the top edge clear; for "magnifyingglass" the bottom right corner region has ink and the top right
// corner is clear.
// Build: clang -framework AppKit appkit-system-symbol-glyphs.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The symbol drawn into a 32 x 32 RGBA bitmap; pixel (x, y) from the top left.
static NSBitmapImageRep *render(NSString *name) {
    NSImage *image = [NSImage imageWithSystemSymbolName: name accessibilityDescription: nil];
    if (image == nil)
        return nil;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 32 pixelsHigh: 32
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: 128 bitsPerPixel: 32] autorelease];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [[NSColor blackColor] set];
    [image drawInRect: NSMakeRect(0, 0, 32, 32) fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

// Whether any pixel of the 5 x 5 block around (x, y) has alpha above 100 / is clear.
static BOOL inkAround(NSBitmapImageRep *rep, int x, int y) {
    for (int dy = -2; dy <= 2; dy++)
        for (int dx = -2; dx <= 2; dx++)
            if ([rep bitmapData][(y + dy) * [rep bytesPerRow] + (x + dx) * 4 + 3] > 100)
                return YES;
    return NO;
}

static BOOL clearAround(NSBitmapImageRep *rep, int x, int y) {
    for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++)
            if ([rep bitmapData][(y + dy) * [rep bytesPerRow] + (x + dx) * 4 + 3] > 40)
                return NO;
    return YES;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSBitmapImageRep *plus = render(@"plus");
    CHECK(plus != nil);
    if (plus != nil) {
        CHECK(inkAround(plus, 16, 16));
        CHECK(inkAround(plus, 16, 8) && inkAround(plus, 16, 24));
        CHECK(inkAround(plus, 8, 16) && inkAround(plus, 24, 16));
        CHECK(clearAround(plus, 5, 5) && clearAround(plus, 26, 5) && clearAround(plus, 5, 26) && clearAround(plus, 26, 26));
    }

    NSBitmapImageRep *xmark = render(@"xmark");
    CHECK(xmark != nil);
    if (xmark != nil) {
        CHECK(inkAround(xmark, 16, 16));
        CHECK(clearAround(xmark, 16, 5) && clearAround(xmark, 5, 16));
    }

    NSBitmapImageRep *lens = render(@"magnifyingglass");
    CHECK(lens != nil);
    if (lens != nil) {
        CHECK(inkAround(lens, 24, 24));
        CHECK(clearAround(lens, 28, 4));
    }

    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
