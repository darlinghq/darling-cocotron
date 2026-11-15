// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView state properties (highlighted column, indicator images, drag and row-action
// flags), -rowForView: and -columnForView:.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@end
@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return 4; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return [NSTextField labelWithString:@"x"];
}
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
        NSTableColumn *c0 = [[[NSTableColumn alloc] initWithIdentifier:@"c0"] autorelease];
        NSTableColumn *c1 = [[[NSTableColumn alloc] initWithIdentifier:@"c1"] autorelease];
        [c0 setWidth:100];
        [c1 setWidth:100];
        [table addTableColumn:c0];
        [table addTableColumn:c1];

        expect([table highlightedTableColumn] == nil, @"no highlighted column");
        [table setHighlightedTableColumn:c1];
        expect([table highlightedTableColumn] == c1, @"highlighted column");
        expect([table draggingDestinationFeedbackStyle] == NSTableViewDraggingDestinationFeedbackStyleRegular, @"default feedback style");
        [table setDraggingDestinationFeedbackStyle:NSTableViewDraggingDestinationFeedbackStyleGap];
        expect([table draggingDestinationFeedbackStyle] == NSTableViewDraggingDestinationFeedbackStyleGap, @"feedback style");
        expect([table verticalMotionCanBeginDrag], @"vertical motion begins a drag by default");
        [table setVerticalMotionCanBeginDrag:NO];
        expect(![table verticalMotionCanBeginDrag], @"vertical motion flag");

        NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(8, 8)] autorelease];
        expect([table indicatorImageInTableColumn:c0] == nil, @"no indicator image");
        [table setIndicatorImage:image inTableColumn:c0];
        expect([table indicatorImageInTableColumn:c0] == image && [table indicatorImageInTableColumn:c1] == nil, @"indicator image per column");
        [table setIndicatorImage:nil inTableColumn:c0];
        expect([table indicatorImageInTableColumn:c0] == nil, @"indicator image removed");

        Source *source = [[[Source alloc] init] autorelease];
        [table setDataSource:source];
        [table setDelegate:source];
        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
        [scroll setDocumentView:table];
        [table reloadData];
        // (macOS raises when the row-action flag is switched on, so it is only read)
        expect(![table rowActionsVisible] && ![table usesStaticContents], @"flags default to NO");
        NSView *cell = [table viewAtColumn:1 row:2 makeIfNecessary:YES];
        expect(cell != nil, @"cell view");
        expect([table rowForView:cell] == 2 && [table columnForView:cell] == 1, @"row and column of a cell view");
        NSView *stranger = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
        expect([table rowForView:stranger] == -1 && [table columnForView:stranger] == -1, @"a view outside the table gives -1");
    }
    printf("PASS\n");
    return 0;
}
