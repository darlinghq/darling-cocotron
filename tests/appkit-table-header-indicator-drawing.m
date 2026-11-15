// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView header: an indicator image set for a column and the highlighted table
// column are visible in the drawn header.
#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSData *render(NSView *view)
{
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
    return [NSData dataWithBytes:[rep bitmapData] length:[rep bytesPerRow] * [rep pixelsHigh]];
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO] autorelease];
        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
        NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
        NSTableColumn *c0 = [[[NSTableColumn alloc] initWithIdentifier:@"c0"] autorelease];
        NSTableColumn *c1 = [[[NSTableColumn alloc] initWithIdentifier:@"c1"] autorelease];
        [c0 setWidth:150];
        [c1 setWidth:150];
        [[c0 headerCell] setStringValue:@"A"];
        [[c1 headerCell] setStringValue:@"B"];
        [table addTableColumn:c0];
        [table addTableColumn:c1];
        [scroll setDocumentView:table];
        [[window contentView] addSubview:scroll];

        NSView *header = [table headerView];
        expect(header != nil && NSWidth([header bounds]) > 100, @"header view");
        NSData *plain = render(header);

        NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(12, 12)] autorelease];
        [image lockFocus];
        [[NSColor redColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 12, 12));
        [image unlockFocus];
        [table setIndicatorImage:image inTableColumn:c0];
        NSData *withImage = render(header);
        expect(![plain isEqualToData:withImage], @"the indicator image changes the drawn header");
        [table setIndicatorImage:nil inTableColumn:c0];
        expect([plain isEqualToData:render(header)], @"removing the image restores the header");

        [table setHighlightedTableColumn:c1];
        expect(![plain isEqualToData:render(header)], @"the highlighted column draws differently");
        [table setHighlightedTableColumn:nil];
        expect([plain isEqualToData:render(header)], @"clearing the highlight restores the header");
    }
    printf("PASS\n");
    return 0;
}
