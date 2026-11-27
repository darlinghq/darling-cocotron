// Copyright (C) 2026 Lubos Dolezel
//
// The background that NSPathCell and NSTextFieldCell draw. A cell whose background is clear or translucent
// composites it over what is already in the context (source-over), and a path cell without a background colour
// draws no background; neither replaces the destination pixels (NSRectFill's copy operation, or filling with
// the colour that is current in the graphics state). Contract: the drawsBackground and backgroundColor
// documentation of NSTextFieldCell
// (https://developer.apple.com/documentation/appkit/nstextfieldcell/backgroundcolor) and of NSPathCell
// (https://developer.apple.com/documentation/appkit/nspathcell/backgroundcolor); a clear colour leaves the
// content below visible. Observed on macOS 26.7.3 (x86_64) by drawing into a bitmap pre-filled with opaque
// green: a clear background leaves the green, a red background at 50% alpha gives a mix of red and green at the
// destination's alpha, and a path cell with no background colour leaves the green where no component is drawn.
// Build: clang -framework AppKit appkit-cell-background-compositing.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSBitmapImageRep *greenBitmap(void) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 120 pixelsHigh: 24
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: 480 bitsPerPixel: 32] autorelease];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [[NSColor colorWithDeviceRed: 0 green: 1 blue: 0 alpha: 1] setFill];
    NSRectFillUsingOperation(NSMakeRect(0, 0, 120, 24), NSCompositeCopy);
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static void draw(NSBitmapImageRep *rep, void (^block)(void)) {
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    block();
    [NSGraphicsContext restoreGraphicsState];
}

static void pixel(NSBitmapImageRep *rep, int x, int y, int *out) {
    const unsigned char *p = [rep bitmapData] + y * [rep bytesPerRow] + x * 4;
    for (int i = 0; i < 4; i++)
        out[i] = p[i];
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 120, 24)] autorelease];
    int p[4];

    // A text field cell with a clear background leaves the destination as it was.
    NSBitmapImageRep *rep = greenBitmap();
    NSTextFieldCell *text = [[[NSTextFieldCell alloc] initTextCell: @""] autorelease];
    [text setDrawsBackground: YES];
    [text setBackgroundColor: [NSColor clearColor]];
    draw(rep, ^{ [text drawWithFrame: NSMakeRect(0, 0, 120, 24) inView: view]; });
    pixel(rep, 60, 12, p);
    CHECK(p[0] < 4 && p[1] > 250 && p[2] < 4 && p[3] > 250);

    // A translucent background is blended with it.
    rep = greenBitmap();
    [text setBackgroundColor: [NSColor colorWithDeviceRed: 1 green: 0 blue: 0 alpha: 0.5]];
    draw(rep, ^{ [text drawWithFrame: NSMakeRect(0, 0, 120, 24) inView: view]; });
    pixel(rep, 60, 12, p);
    CHECK(p[0] > 100 && p[0] < 160 && p[1] > 100 && p[1] < 160 && p[3] > 250);

    // A path cell without a background colour draws none: the pixel past the last component is untouched, even
    // when another colour is the current one of the graphics state.
    rep = greenBitmap();
    NSPathCell *path = [[[NSPathCell alloc] init] autorelease];
    [path setBackgroundColor: nil];
    [path setURL: [NSURL fileURLWithPath: @"/tmp"]];
    draw(rep, ^{
        [[NSColor colorWithDeviceRed: 1 green: 0 blue: 0 alpha: 1] set];
        [path drawWithFrame: NSMakeRect(0, 0, 120, 24) inView: view];
    });
    pixel(rep, 116, 20, p);
    CHECK(p[0] < 4 && p[1] > 250 && p[2] < 4 && p[3] > 250);

    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
