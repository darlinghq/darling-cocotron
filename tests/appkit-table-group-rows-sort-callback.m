// Copyright (C) 2026 Lubos Dolezel
//
// View-based NSTableView: a row the delegate reports as a group row (tableView:isGroupRow:)
// gets one view requested without a column, and the data source is told through
// tableView:sortDescriptorsDidChange: when the sort descriptors change.
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

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
    NSMutableArray *_requests;
    NSArray *_oldDescriptors;
    NSInteger _sortCalls;
}
@property (retain) NSMutableArray *requests;
@property (retain) NSArray *oldDescriptors;
@property NSInteger sortCalls;
@end

@implementation Source
@synthesize requests = _requests, oldDescriptors = _oldDescriptors, sortCalls = _sortCalls;
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return 3; }
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row { return row == 0; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    [self.requests addObject:[NSString stringWithFormat:@"%@/%ld", column ? [column identifier] : @"(nil)", (long)row]];
    return [NSTextField labelWithString:@"x"];
}
- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    self.oldDescriptors = oldDescriptors;
    self.sortCalls++;
}
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
        NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
        for (int i = 0; i < 2; i++)
        {
            NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"c%d", i]] autorelease];
            [column setWidth:100];
            [table addTableColumn:column];
        }
        Source *source = [[[Source alloc] init] autorelease];
        source.requests = [NSMutableArray array];
        [table setDataSource:source];
        [table setDelegate:source];
        [scroll setDocumentView:table];
        [table reloadData];

        NSView *groupView = [table viewAtColumn:0 row:0 makeIfNecessary:YES];
        expect(groupView != nil, @"the group row has a view");
        expect([source.requests containsObject:@"(nil)/0"], @"the group row's view is requested without a column");
        expect(![source.requests containsObject:@"c0/0"] && ![source.requests containsObject:@"c1/0"],
               @"no per-column view is requested for the group row");

        NSView *cellView = [table viewAtColumn:1 row:1 makeIfNecessary:YES];
        expect(cellView != nil, @"an ordinary row has a view per column");

        // Sort descriptor notification
        expect(source.sortCalls == 0, @"no notification yet");
        NSArray *descriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"c0" ascending:YES]];
        [table setSortDescriptors:descriptors];
        expect(source.sortCalls == 1, @"data source told of the new sort descriptors");
        expect([source.oldDescriptors count] == 0, @"with the previous (empty) descriptors");
        [table setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"c1" ascending:NO]]];
        expect(source.sortCalls == 2 && [source.oldDescriptors count] == 1 &&
                   [[[source.oldDescriptors objectAtIndex:0] key] isEqualToString:@"c0"],
               @"second change reports the earlier descriptors");
    }
    printf("PASS\n");
    return 0;
}
