// Alternating row backgrounds of NSTableView and NSOutlineView follow macOS 10.14's light
// appearance: white and light grey (not blue) rows, and stripes that continue below the last row.
// Values observed on macOS 10.14.4: controlAlternatingRowBackgroundColors and
// alternatingContentBackgroundColors are sRGB (255,255,255) and (244,245,245); in a bitmap from
// cacheDisplayInRect:toBitmapImageRep: the grey rows read about (246,247,247).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

@interface Rows : NSObject <NSTableViewDataSource, NSOutlineViewDataSource>
@end
@implementation Rows
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 5; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r { return @"x"; }
- (NSInteger)outlineView:(NSOutlineView *)o numberOfChildrenOfItem:(id)i { return i ? 0 : 5; }
- (id)outlineView:(NSOutlineView *)o child:(NSInteger)n ofItem:(id)i { return @"x"; }
- (BOOL)outlineView:(NSOutlineView *)o isItemExpandable:(id)i { return NO; }
- (id)outlineView:(NSOutlineView *)o objectValueForTableColumn:(NSTableColumn *)c byItem:(id)i { return @"x"; }
@end

static void rgb255(NSColor *color, int *out)
{
    NSColor *s = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    out[0] = (int)lround(s.redComponent * 255);
    out[1] = (int)lround(s.greenComponent * 255);
    out[2] = (int)lround(s.blueComponent * 255);
}

static BOOL isRGB(NSColor *color, int r, int g, int b, int tolerance)
{
    int v[3];
    rgb255(color, v);
    return abs(v[0] - r) <= tolerance && abs(v[1] - g) <= tolerance && abs(v[2] - b) <= tolerance;
}

static BOOL isWhite(NSColor *c) { return isRGB(c, 255, 255, 255, 1); }
static BOOL isGrey(NSColor *c) { return isRGB(c, 244, 245, 245, 3); }

// The pixel in the middle of the vertical extent [minY, maxY) given in the scroll view's coordinates
// (the bitmap rows run from the top whether or not the view is flipped)
static NSColor *pixelAt(NSBitmapImageRep *rep, NSScrollView *sv, CGFloat x, CGFloat minY, CGFloat maxY)
{
    CGFloat midY = (minY + maxY) / 2;
    return [rep colorAtX:(NSInteger)x y:(NSInteger)([sv isFlipped] ? midY : [sv bounds].size.height - midY)];
}

static void spin(void)
{
    for (int i = 0; i < 6; i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static void checkStripes(NSTableView *table, NSScrollView *sv, NSWindow *w, const char *name)
{
    [table setUsesAlternatingRowBackgroundColors:YES];
    spin();
    [w displayIfNeeded];
    NSBitmapImageRep *rep = [sv bitmapImageRepForCachingDisplayInRect:[sv bounds]];
    [sv cacheDisplayInRect:[sv bounds] toBitmapImageRep:rep];

    CGFloat x = [sv bounds].size.width - 40;
    for (NSInteger row = 0; row < 5; row++) {
        NSRect r = [sv convertRect:[table rectOfRow:row] fromView:table];
        NSColor *p = pixelAt(rep, sv, x, NSMinY(r), NSMaxY(r));
        BOOL ok = row % 2 == 0 ? isWhite(p) : isGrey(p);
        if (!ok) {
            int v[3]; rgb255(p, v);
            printf("%s row %ld has (%d,%d,%d)\n", name, (long)row, v[0], v[1], v[2]);
        }
        CHECK(ok);
    }
    // Below the last row the stripes carry on: rows 5, 6 and 7 would be grey, white, grey
    NSRect last = [sv convertRect:[table rectOfRow:4] fromView:table];
    CGFloat pitch = last.size.height;
    for (int k = 1; k <= 3; k++) {
        CGFloat d = [sv isFlipped] ? pitch * k : -pitch * k;
        CGFloat minY = NSMinY(last) + d, maxY = NSMaxY(last) + d;
        if (minY < 0 || maxY > [sv bounds].size.height) break; // out of the scroll view
        NSColor *p = pixelAt(rep, sv, x, minY, maxY);
        BOOL ok = k % 2 == 1 ? isGrey(p) : isWhite(p);
        if (!ok) {
            int v[3]; rgb255(p, v);
            printf("%s empty row %d has (%d,%d,%d)\n", name, k, v[0], v[1], v[2]);
        }
        CHECK(ok);
    }
    // A selected row is still highlighted, and the rows around it keep their stripes
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [w makeFirstResponder:table];
    spin();
    [w displayIfNeeded];
    rep = [sv bitmapImageRepForCachingDisplayInRect:[sv bounds]];
    [sv cacheDisplayInRect:[sv bounds] toBitmapImageRep:rep];
    NSRect r1 = [sv convertRect:[table rectOfRow:1] fromView:table];
    NSRect r2 = [sv convertRect:[table rectOfRow:2] fromView:table];
    CHECK(!isGrey(pixelAt(rep, sv, x, NSMinY(r1), NSMaxY(r1))));
    CHECK(isWhite(pixelAt(rep, sv, x, NSMinY(r2), NSMaxY(r2))));
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSArray<NSColor *> *c = [NSColor controlAlternatingRowBackgroundColors];
        CHECK([c count] == 2);
        if ([c count] == 2) {
            CHECK(isRGB(c[0], 255, 255, 255, 1));
            CHECK(isRGB(c[1], 244, 245, 245, 1));
        }
        c = [NSColor alternatingContentBackgroundColors];
        CHECK([c count] == 2);
        if ([c count] == 2) {
            CHECK(isRGB(c[0], 255, 255, 255, 1));
            CHECK(isRGB(c[1], 244, 245, 245, 1));
        }

        Rows *rows = [Rows new];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 300, 240)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        for (int kind = 0; kind < 2; kind++) {
            NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 280, 200)];
            NSTableView *t = kind ? [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 280, 100)]
                                  : [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 280, 100)];
            NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"A"];
            [col setWidth:270];
            [t addTableColumn:col];
            if (kind) [(NSOutlineView *)t setOutlineTableColumn:col];
            [t setDataSource:(id)rows];
            [sv setDocumentView:t];
            [w setContentView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 240)]];
            [[w contentView] addSubview:sv];
            [w makeKeyAndOrderFront:nil];
            checkStripes(t, sv, w, kind ? "outline" : "table");
        }
    }
    printf(g_failures ? "FAILED\n" : "PASS\n");
    return g_failures ? 1 : 0;
}
