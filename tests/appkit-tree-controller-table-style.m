// Copyright (C) 2026 Lubos Dolezel
//
// AppKit: NSTreeController builds a tree of NSTreeNode objects from content
// objects and a children key path, tracks selection index paths and selected
// objects; NSTableView dragging source operation masks, floatsGroupRows,
// rowSizeStyle (a new table is Custom, Default resolves to Medium, rowHeight
// is not tied to the style) and style (documented NSTableViewStyle values);
// NSOutlineView treats the nil root as expanded. Expected values for the table
// view were observed on macOS 27 (arm64).

#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(int ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Item : NSObject
@property(copy) NSString *name;
@property(strong) NSMutableArray *children;
+ (Item *) itemNamed: (NSString *) name children: (NSArray *) children;
@end
@implementation Item
+ (Item *) itemNamed: (NSString *) name children: (NSArray *) children {
    Item *item = [Item new];
    item.name = name;
    item.children = children ? [children mutableCopy] : nil;
    return item;
}
@end

static void testTreeController(void) {
    Item *a1 = [Item itemNamed: @"a1" children: nil];
    Item *a2 = [Item itemNamed: @"a2" children: nil];
    Item *a = [Item itemNamed: @"a" children: @[ a1, a2 ]];
    Item *b = [Item itemNamed: @"b" children: nil];

    NSTreeController *tree = [[NSTreeController alloc] initWithContent: nil];
    tree.childrenKeyPath = @"children";
    tree.content = @[ b, a ];
    tree.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES] ];
    [tree rearrangeObjects];

    NSTreeNode *root = tree.arrangedObjects;
    NSArray *top = [root childNodes];
    expect([top count] == 2, "two top-level nodes");
    expect([[[top objectAtIndex: 0] representedObject] isEqual: a], "nodes are sorted by the descriptors");
    NSTreeNode *nodeA = [top objectAtIndex: 0];
    expect([[nodeA childNodes] count] == 2, "children come from the children key path");
    expect([[[nodeA childNodes] objectAtIndex: 1] parentNode] == nodeA, "child nodes know their parent");
    expect([[top objectAtIndex: 1] isLeaf], "an item with no children is a leaf");
    expect(![nodeA isLeaf], "an item with children is not a leaf");

    NSIndexPath *path = [[NSIndexPath indexPathWithIndex: 0] indexPathByAddingIndex: 1];
    expect([tree setSelectionIndexPath: path], "setSelectionIndexPath: succeeds");
    expect([[tree selectionIndexPath] isEqual: path], "the selection index path round-trips");
    expect([[tree selectedObjects] isEqual: @[ a2 ]], "selectedObjects follows the selection");
    expect([[tree selectedNodes] count] == 1, "selectedNodes has the node");
    expect([[[[tree selectedNodes] objectAtIndex: 0] indexPath] isEqual: path],
           "a node reports its index path");
}

@interface Rows : NSObject <NSTableViewDataSource>
@end
@implementation Rows
- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
    return 3;
}
- (id) tableView: (NSTableView *) tableView objectValueForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    return @"x";
}
@end

static void testTableView(void) {
    NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    expect(table.floatsGroupRows == YES, "floatsGroupRows defaults to YES");
    table.floatsGroupRows = NO;
    expect(table.floatsGroupRows == NO, "floatsGroupRows round-trips");

    expect(table.rowSizeStyle == NSTableViewRowSizeStyleCustom, "rowSizeStyle defaults to Custom");
    table.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    expect(table.effectiveRowSizeStyle == NSTableViewRowSizeStyleMedium, "Default resolves to Medium");
    table.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    expect(table.effectiveRowSizeStyle == NSTableViewRowSizeStyleSmall, "Small resolves to itself");
    table.rowHeight = 30;
    table.rowSizeStyle = NSTableViewRowSizeStyleLarge;
    expect(table.rowHeight == 30, "-rowHeight is not tied to the row size style");

    expect(NSTableViewStyleAutomatic == 0 && NSTableViewStyleFullWidth == 1 && NSTableViewStyleInset == 2 &&
                   NSTableViewStyleSourceList == 3 && NSTableViewStylePlain == 4,
           "NSTableViewStyle has the documented values");
    table.style = NSTableViewStyleSourceList;
    expect(table.style == NSTableViewStyleSourceList, "style round-trips");
    table.style = NSTableViewStyleFullWidth;
    expect(table.style == NSTableViewStyleFullWidth, "FullWidth round-trips");

    NSTableView *fresh = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    expect([fresh draggingSourceOperationMaskForLocal: YES] == NSDragOperationEvery,
           "local drags default to every operation");
    expect([fresh draggingSourceOperationMaskForLocal: NO] == NSDragOperationNone,
           "external drags default to none");
    [fresh setDraggingSourceOperationMask: NSDragOperationCopy forLocal: NO];
    [fresh setDraggingSourceOperationMask: NSDragOperationMove forLocal: YES];
    expect([fresh draggingSourceOperationMaskForLocal: NO] == NSDragOperationCopy &&
                   [fresh draggingSourceOperationMaskForLocal: YES] == NSDragOperationMove,
           "the masks are stored per locality");
}

static void testOutlineRoot(void) {
    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
    expect([outline isItemExpanded: nil] == YES, "the nil root item is expanded");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        testTreeController();
        testTableView();
        testOutlineRoot();
    }
    printf("%s\n", failures ? "FAILED" : "PASSED");
    return failures != 0;
}
