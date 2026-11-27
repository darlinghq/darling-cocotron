// Copyright (C) 2026 Lubos Dolezel
//
// A view that draws its background colour composites it over what is below: a clear background leaves the
// pixels alone and a translucent one is blended, instead of replacing them (and a view without a colour
// draws nothing). The test displays NSTableView, NSTextView, NSClipView and NSCollectionView into a bitmap
// that was filled with opaque red (calling -drawRect: with the bitmap as the current context) and reads the pixels back. Observed through the public API on macOS 26.7.3:
// table and text view keep the red for clear and blend white at 50% to (255,128,128); the clip view keeps
// the red for clear. Needs no window on screen (the views live in an unordered window).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

static void render(NSView *view, int *rgba)
{
    // The views are 150 points square; a table without rows would report a smaller bounds.
    NSRect b = NSMakeRect(0, 0, 150, 150);
    size_t rowBytes = (size_t) b.size.width * 4;
    unsigned char *storage = calloc(rowBytes, (size_t) b.size.height);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: &storage pixelsWide: b.size.width
                                                                    pixelsHigh: b.size.height bitsPerSample: 8
                                                               samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                                                                colorSpaceName: NSDeviceRGBColorSpace
                                                                   bytesPerRow: rowBytes bitsPerPixel: 32];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: ctx];
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(0, 0, b.size.width, b.size.height));
    [NSGraphicsContext restoreGraphicsState];
    // The view draws itself into the bitmap context, as it does inside a window.
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: ctx];
    [view drawRect: b];
    [NSGraphicsContext restoreGraphicsState];
    const unsigned char *data = storage + 5 * rowBytes + 5 * 4;
    for (int i = 0; i < 4; i++)
        rgba[i] = data[i];
    printf("%s pixel (5,5): %d,%d,%d,%d\n", [NSStringFromClass([view class]) UTF8String], rgba[0], rgba[1], rgba[2], rgba[3]);
    [rep release];
    free(storage);
}

static BOOL near(int a, int b) { return abs(a - b) <= 2; }

@interface Items : NSObject <NSCollectionViewDataSource>
@end
@implementation Items
- (NSInteger) collectionView: (NSCollectionView *) cv numberOfItemsInSection: (NSInteger) s { return 0; }
- (NSCollectionViewItem *) collectionView: (NSCollectionView *) cv itemForRepresentedObjectAtIndexPath: (NSIndexPath *) p { return nil; }
@end

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered defer: YES];
        NSColor *clear = [NSColor clearColor];
        NSColor *half = [NSColor colorWithCalibratedWhite: 1 alpha: 0.5];
        int px[4];

        NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 150, 150)];
        [table addTableColumn: [[[NSTableColumn alloc] initWithIdentifier: @"a"] autorelease]];
        [table setUsesAlternatingRowBackgroundColors: NO];
        [[w contentView] addSubview: table];
        [table setBackgroundColor: clear];
        render(table, px);
        expect(px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255, @"table view: a clear background keeps the pixels");
        [table setBackgroundColor: half];
        render(table, px);
        expect(px[0] == 255 && near(px[1], 128) && near(px[2], 128), @"table view: a translucent background is blended");

        NSTextView *text = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 150, 150)];
        [[w contentView] addSubview: text];
        [text setDrawsBackground: YES];
        [text setBackgroundColor: clear];
        render(text, px);
        expect(px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255, @"text view: a clear background keeps the pixels");
        [text setBackgroundColor: half];
        render(text, px);
        expect(px[0] == 255 && near(px[1], 128) && near(px[2], 128), @"text view: a translucent background is blended");
        expect(![text isOpaque], @"text view: a translucent background is not opaque");

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 150, 150)];
        [[w contentView] addSubview: scroll];
        NSClipView *clip = [scroll contentView];
        [clip setDrawsBackground: YES];
        [clip setBackgroundColor: clear];
        [clip setFrame: NSMakeRect(0, 0, 150, 150)];
        render(clip, px);
        expect(px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255, @"clip view: a clear background keeps the pixels");
        expect(![clip isOpaque], @"clip view: a clear background is not opaque");

        Items *items = [[Items alloc] init];
        NSCollectionView *collection = [[NSCollectionView alloc] initWithFrame: NSMakeRect(0, 0, 150, 150)];
        [collection setDataSource: items];
        [[w contentView] addSubview: collection];
        [collection setBackgroundColors: @[ clear ]];
        render(collection, px);
        expect(px[0] == 255 && px[1] == 0 && px[2] == 0 && px[3] == 255, @"collection view: a clear background keeps the pixels");
        [collection setBackgroundColors: @[ half ]];
        render(collection, px);
        expect(px[0] == 255 && near(px[1], 128) && near(px[2], 128), @"collection view: a translucent background is blended");
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
