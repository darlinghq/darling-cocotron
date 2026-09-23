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

// Two groups with two leaves each, the shape of a sidebar source list.
@interface TreeSource : NSObject
@property(retain) NSDictionary *tree;
@property NSInteger shouldExpandCalls;
@end

@implementation TreeSource
- (NSArray *)childrenOf:(id)item
{
    return item == nil ? [[self.tree allKeys] sortedArrayUsingSelector:@selector(compare:)] : self.tree[item];
}
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    return [[self childrenOf:item] count];
}
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    return [self childrenOf:item][index];
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return self.tree[item] != nil;
}
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    return item;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
    expect(item != nil, @"the delegate is not asked about the root");
    self.shouldExpandCalls++;
    return YES;
}
@end

int main(void)
{
    @autoreleasepool
    {
        TreeSource *source = [[TreeSource alloc] init];
        source.tree = @{ @"Devices" : @[ @"Mac", @"iPhone" ], @"Reports" : @[ @"Crash", @"Spin" ] };

        NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
        [outline addTableColumn:column];
        outline.outlineTableColumn = column;
        outline.dataSource = (id)source;
        outline.delegate = (id)source;
        [outline reloadData];
        expect(outline.numberOfRows == 2, @"root children are rows");

        [outline expandItem:nil];
        expect(outline.numberOfRows == 2, @"expanding the root keeps the rows");

        [outline expandItem:nil expandChildren:YES];
        expect(outline.numberOfRows == 6, @"expanding the root's children shows every row");
        expect([[outline itemAtRow:1] isEqual:@"Mac"] && [[outline itemAtRow:4] isEqual:@"Crash"], @"rows in tree order");
        expect(source.shouldExpandCalls == 2, @"the delegate is asked about each group");

        [outline collapseItem:nil collapseChildren:YES];
        expect(outline.numberOfRows == 2, @"collapsing the root's children hides the leaves");

        [outline release];
        [source release];
        NSLog(@"PASS: NSOutlineView expands and collapses the nil root");
    }
    return 0;
}
