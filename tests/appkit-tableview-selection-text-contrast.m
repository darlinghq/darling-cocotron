// CFLAGS: -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// The text of a selected row of a table stays readable in both states of the selection. While the table is the
// first responder of the key window the row is highlighted in the accent colour (white text); otherwise (the
// table is not the first responder, or the window is not key) the highlight is grey and the text keeps its normal,
// dark colour. The test draws the row into a bitmap and compares the text's colour with the row's background: the
// contrast ratio must be at least 3 in each state. On macOS 26.7.3 the offscreen drawing shows the inactive state
// (light grey, background luminance 0.87, dark text, contrast 3.64), which passes unchanged. Needs a display.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

@interface Source : NSObject <NSTableViewDataSource>
@end
@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return 4; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return @[ @"Keyboard", @"Display", @"Identity", @"Security" ][row];
}
@end

static double Luminance(double r, double g, double b)
{
    double c[3] = { r, g, b };
    for (int i = 0; i < 3; i++)
        c[i] = c[i] <= 0.03928 ? c[i] / 12.92 : pow((c[i] + 0.055) / 1.055, 2.4);
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

// The contrast between the background of the row (its left edge) and the pixel of the row farthest from it
// in colour, which is a pixel of the text.
static double RowContrast(NSTableView *table, NSInteger row, double *bgLuma)
{
    // drawn through the window's content view, which has the backgrounds behind the table
    NSView *content = [[table window] contentView];
    NSRect rect = [content convertRect:[table rectOfRow:row] fromView:table];
    rect = NSIntersectionRect(rect, [content bounds]);
    NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:rect];
    [content cacheDisplayInRect:rect toBitmapImageRep:rep];
    NSColor *bg = [[rep colorAtX:1 y:[rep pixelsHigh] / 2] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    double best = 0, textLuma = 0;
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
        for (NSInteger x = 0; x < [rep pixelsWide] / 2; x++) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            double d = fabs([c redComponent] - [bg redComponent]) + fabs([c greenComponent] - [bg greenComponent]) + fabs([c blueComponent] - [bg blueComponent]);
            if (d > best) {
                best = d;
                textLuma = Luminance([c redComponent], [c greenComponent], [c blueComponent]);
            }
        }
    double bgL = Luminance([bg redComponent], [bg greenComponent], [bg blueComponent]);
    if (bgLuma) *bgLuma = bgL;
    double hi = MAX(bgL, textLuma), lo = MIN(bgL, textLuma);
    return (hi + 0.05) / (lo + 0.05);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        Source *source = [[Source alloc] init];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered defer:NO];
        NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"c"];
        [column setWidth:196];
        [table addTableColumn:column];
        [table setHeaderView:nil];
        [table setRowHeight:24];
        [table setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
        [table setDataSource:source];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        [scroll setDocumentView:table];
        [[window contentView] addSubview:scroll];
        [window makeKeyAndOrderFront:nil];
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];

        double bg, contrast;
        // the key window, the table is not the first responder: grey highlight, dark text
        [window makeFirstResponder:window];
        contrast = RowContrast(table, 1, &bg);
        printf("not first responder: background luminance %.3f, contrast %.2f\n", bg, contrast);
        expect(contrast >= 3, @"selected row text is readable while the table is not the first responder");
        expect(bg > 0.5, @"and the highlight is light grey then");

        // the first responder of the key window: accent highlight, white text
        [window makeFirstResponder:table];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        contrast = RowContrast(table, 1, &bg);
        printf("first responder: background luminance %.3f, contrast %.2f\n", bg, contrast);
        expect(contrast >= 3, @"selected row text is readable while the table is the first responder");

        // the window gives up being key: grey again
        [window orderOut:nil];
        NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(500, 400, 100, 100) styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered defer:NO];
        [window orderFront:nil];
        [other makeKeyAndOrderFront:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        if (![window isKeyWindow]) {
            contrast = RowContrast(table, 1, &bg);
            printf("window not key: background luminance %.3f, contrast %.2f\n", bg, contrast);
            expect(contrast >= 3, @"selected row text is readable while the window is not key");
        }
    }
    printf(failures ? "FAILED: %d\n" : "ALL PASSED\n", failures);
    return failures != 0;
}
