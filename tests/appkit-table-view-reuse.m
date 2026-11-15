// Copyright (C) 2026 Lubos Dolezel
//
// View-based table: views the delegate creates itself (no registered nib) must not pile up
// in the table. Redisplaying and reloading reuse them through makeViewWithIdentifier:owner:.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static int created;

static void expect(BOOL ok, NSString *what)
{
    if (!ok) {
        NSLog(@"FAIL: %@", what);
        failures++;
    }
}

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return 6; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSTextField *field = [tv makeViewWithIdentifier:@"cell" owner:self];
    if (field == nil) {
        field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 17)] autorelease];
        [field setIdentifier:@"cell"];
        created++;
    }
    [field setStringValue:[NSString stringWithFormat:@"%ld/%@", (long)row, [column identifier]]];
    return field;
}
@end

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
        for (int i = 0; i < 2; i++) {
            NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"c%d", i]] autorelease];
            [column setWidth:150];
            [table addTableColumn:column];
        }
        Source *source = [[Source new] autorelease];
        [table setDataSource:source];
        [table setDelegate:source];
        [scroll setDocumentView:table];
        [[window contentView] addSubview:scroll];

        for (int round = 0; round < 5; round++) {
            for (int draw = 0; draw < 4; draw++) {
                [table setNeedsDisplay:YES];
                [table displayRectIgnoringOpacity:[table bounds]];
            }
            [table reloadData];
        }
        for (int draw = 0; draw < 4; draw++) {
            [table setNeedsDisplay:YES];
            [table displayRectIgnoringOpacity:[table bounds]];
        }
        NSUInteger cellViews = 0;
        for (NSView *subview in [table subviews])
            if ([subview isKindOfClass:[NSTextField class]])
                cellViews++;
        expect(cellViews <= 12, [NSString stringWithFormat:@"at most one view per cell stays in the table (found %lu)", (unsigned long)cellViews]);
        expect(created <= 14, [NSString stringWithFormat:@"views are reused instead of created again (created %d)", created]);

        // A view taken out of the table by reloadData is handed out again for its identifier
        [table reloadData];
        NSView *again = [table makeViewWithIdentifier:@"cell" owner:source];
        expect(again != nil && [again superview] == nil, @"reloadData makes the views reusable");
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
