// Copyright (C) 2026 Lubos Dolezel
//
// A titled NSBrowser keeps the title area above its columns but draws nothing in it, as on macOS 10.14.4
// (black-box renders, mac-probes/aqua-table-header-2.m and -3.m; QUIRK-tagged code in NSBrowser and
// NSGraphicsStyle (NSBrowser)):
//  - test_quirk_title_area: the title area of a titled browser with titles set has one colour, no title ink;
//  - test_quirk_draw_title: -drawTitleOfColumn:inRect: called directly draws no pixels.
// Build: clang -framework AppKit appkit-browser-title-drawing.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Source : NSObject
@end
@implementation Source
- (NSInteger) browser: (NSBrowser *) b numberOfRowsInColumn: (NSInteger) col { return 3; }
- (void) browser: (NSBrowser *) b willDisplayCell: (id) cell atRow: (NSInteger) row column: (NSInteger) col {
    [cell setStringValue: @"Item"];
    [cell setLeaf: YES];
}
@end

static NSBrowser *makeBrowser(void) {
    NSBrowser *browser = [[NSBrowser alloc] initWithFrame: NSMakeRect(0, 0, 330, 150)];
    [browser setDelegate: (id) [Source new]];
    [browser setTitled: YES];
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 330, 150)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [[window contentView] addSubview: browser];
    [browser loadColumnZero];
    [browser setTitle: @"MMMM Title" ofColumn: 0];
    return browser;
}

static void pixel(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSUInteger p[4];
    [rep getPixel: p atX: x y: y];
    for (int i = 0; i < 4; i++)
        c[i] = (int) p[i];
}

static void test_quirk_title_area(void) {
    NSBrowser *browser = makeBrowser();
    NSRect title = [browser titleFrameOfColumn: 0];

    CHECK([browser isTitled] && [browser titleHeight] == 20);
    CHECK([[browser titleOfColumn: 0] isEqualToString: @"MMMM Title"]);
    NSBitmapImageRep *rep = [browser bitmapImageRepForCachingDisplayInRect: [browser bounds]];
    [browser cacheDisplayInRect: [browser bounds] toBitmapImageRep: rep];
    // rows from the top of the bitmap: the title area is at the top of the (unflipped) browser
    int first[4], c[4], top = (int) (NSHeight([browser bounds]) - NSMaxY(title));
    pixel(rep, (int) NSMinX(title) + 1, top + 1, first);
    for (int y = top; y < top + (int) NSHeight(title); y++)
        for (int x = (int) NSMinX(title); x < (int) NSMaxX(title); x++) {
            pixel(rep, x, y, c);
            if (c[0] != first[0] || c[1] != first[1] || c[2] != first[2] || c[3] != first[3]) {
                CHECK(!"title area has one colour");
                return;
            }
        }
}

static void test_quirk_draw_title(void) {
    NSBrowser *browser = makeBrowser();
    NSRect title = [browser titleFrameOfColumn: 0];
    NSBitmapImageRep *rep = [browser bitmapImageRepForCachingDisplayInRect: [browser bounds]];
    int c[4];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [[NSColor colorWithCalibratedRed: 1 green: 0 blue: 1 alpha: 1] set];
    NSRectFill([browser bounds]);
    [browser drawTitleOfColumn: 0 inRect: title];
    [NSGraphicsContext restoreGraphicsState];

    for (int y = 0; y < (int) [rep pixelsHigh]; y++)
        for (int x = 0; x < (int) [rep pixelsWide]; x++) {
            pixel(rep, x, y, c);
            if (c[0] != 255 || c[1] != 0 || c[2] != 255) {
                CHECK(!"drawTitleOfColumn:inRect: draws nothing");
                return;
            }
        }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_title_area();
        test_quirk_draw_title();
    }
    if (failures) {
        printf("FAIL (%d)\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
