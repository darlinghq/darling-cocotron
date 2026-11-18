// Copyright (C) 2026 Lubos Dolezel
//
// The selected row of NSTableView and NSOutlineView follows macOS 10.14: an emphasized selection (the table is
// the first responder of the key window) is drawn in alternateSelectedControlColor, any other selection in
// secondarySelectedControlColor, and NSTableViewSelectionHighlightStyleNone draws no highlight.
// Class colours measured on macOS 10.14.4 (Blue tint, sRGB): selectedControlColor (179,215,255),
// alternateSelectedControlColor and selectedContentBackgroundColor (0,99,225), secondarySelectedControlColor and
// unemphasizedSelectedContentBackgroundColor (220,220,220), alternateSelectedControlTextColor white. The drawn
// pixels of the emphasized selection could not be measured on that system (the process never becomes active over
// ssh), so they are checked against the class colours; the unemphasized render on 10.14.4 reads (227,227,227).
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

static BOOL isRGB(NSColor *color, int r, int g, int b, int tolerance)
{
    NSColor *s = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return abs((int)lround(s.redComponent * 255) - r) <= tolerance &&
           abs((int)lround(s.greenComponent * 255) - g) <= tolerance &&
           abs((int)lround(s.blueComponent * 255) - b) <= tolerance;
}

static void spin(void)
{
    for (int i = 0; i < 6; i++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

// The pixel of the middle of row 1 at the right of the table (clear of the cell text)
static NSColor *selectedPixel(NSTableView *table, NSScrollView *sv, NSWindow *w)
{
    spin();
    [w displayIfNeeded];
    NSBitmapImageRep *rep = [sv bitmapImageRepForCachingDisplayInRect:[sv bounds]];
    [sv cacheDisplayInRect:[sv bounds] toBitmapImageRep:rep];
    NSRect r = [sv convertRect:[table rectOfRow:1] fromView:table];
    CGFloat midY = NSMidY(r);
    return [rep colorAtX:(NSInteger)([sv bounds].size.width - 40)
                       y:(NSInteger)([sv isFlipped] ? midY : [sv bounds].size.height - midY)];
}

static void report(NSColor *c, const char *what)
{
    NSColor *s = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    printf("%s pixel (%.0f,%.0f,%.0f)\n", what, s.redComponent * 255, s.greenComponent * 255, s.blueComponent * 255);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        CHECK(isRGB([NSColor selectedControlColor], 179, 215, 255, 1));
        CHECK(isRGB([NSColor alternateSelectedControlColor], 0, 99, 225, 1));
        CHECK(isRGB([NSColor selectedContentBackgroundColor], 0, 99, 225, 1));
        CHECK(isRGB([NSColor secondarySelectedControlColor], 220, 220, 220, 1));
        CHECK(isRGB([NSColor unemphasizedSelectedContentBackgroundColor], 220, 220, 220, 1));
        CHECK(isRGB([NSColor alternateSelectedControlTextColor], 255, 255, 255, 1));

        Rows *rows = [Rows new];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 300, 240)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        for (int kind = 0; kind < 2; kind++) {
            const char *name = kind ? "outline" : "table";
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
            spin();
            [t selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];

            // Not the first responder: unemphasized grey (a render reads about 227 on macOS 10.14.4)
            [w makeFirstResponder:[w contentView]];
            NSColor *p = selectedPixel(t, sv, w);
            report(p, name);
            CHECK(isRGB(p, 220, 220, 220, 10));

            // First responder of the key window: emphasized blue
            [w makeFirstResponder:t];
            if ([w isKeyWindow] && [w firstResponder] == t) {
                p = selectedPixel(t, sv, w);
                report(p, name);
                CHECK(isRGB(p, 0, 99, 225, 8));

                // The key window changes: the selection becomes unemphasized again
                [w makeFirstResponder:nil];
                p = selectedPixel(t, sv, w);
                CHECK(isRGB(p, 220, 220, 220, 10));
                [w makeFirstResponder:t];
            } else {
                printf("%s: window is not key, emphasized check skipped\n", name);
            }

            // No highlight with the None style, whichever the responder
            [t setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
            p = selectedPixel(t, sv, w);
            report(p, name);
            CHECK(isRGB(p, 255, 255, 255, 3) || isRGB(p, 244, 245, 245, 3));
        }
    }
    printf(g_failures ? "FAILED\n" : "PASS\n");
    return g_failures ? 1 : 0;
}
