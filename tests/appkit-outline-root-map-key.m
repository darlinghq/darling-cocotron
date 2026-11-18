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

@interface Source : NSObject
@end

@implementation Source
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    return item == nil ? 2 : 0;
}
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    return index == 0 ? @"first" : @"second";
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return NO;
}
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    return item;
}
@end

// The root item is nil: it has level -1 and no parent, as on macOS.
int main(void)
{
    @autoreleasepool
    {
        Source *source = [[Source alloc] init];
        NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
        [outline addTableColumn:column];
        outline.outlineTableColumn = column;
        outline.dataSource = (id)source;
        [outline reloadData];
        expect(outline.numberOfRows == 2, @"root children are rows");

        expect([outline levelForItem:nil] == -1, @"the root item has no level");
        expect([outline parentForItem:nil] == nil, @"the root item has no parent");
        NSLog(@"PASS: outline view root item level and parent");
    }
    return 0;
}
