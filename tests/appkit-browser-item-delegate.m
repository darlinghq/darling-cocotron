// Copyright (C) 2026 Lubos Dolezel
//
// NSBrowser with an item-based delegate (macOS 10.6 and later) and the browser's column and click
// properties. The contract is the documentation of NSBrowserDelegate
// (https://developer.apple.com/documentation/appkit/nsbrowserdelegate): rootItemForBrowser:,
// browser:numberOfChildrenOfItem:, browser:child:ofItem:, browser:isLeafItem: and browser:objectValueForItem:
// give the content of the columns; -[NSBrowser itemAtRow:inColumn:] and -parentForItemsInColumn: answer
// with the items of the delegate. The properties minColumnWidth, defaultColumnWidth, autohidesScroller,
// prefersAllColumnUserResizing, rowHeight, columnsAutosaveName, columnResizingType, clickedColumn and
// clickedRow are documented; NSMatrix's selectionByRect defaults to YES
// (https://developer.apple.com/documentation/appkit/nsmatrix/isselectionbyrect).
// Observed on macOS 26.7.3 (x86_64): the first column shows the root's children; selecting a row of a column
// that is not a leaf adds a column with the children of the selected item (leaf items add none); itemAtRow:inColumn:
// asks the delegate for the child. clickedColumn and
// clickedRow are -1 before a click; the property setters keep their values.
// Build: clang -framework AppKit appkit-browser-item-delegate.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// A tree of dictionaries: the item is a dictionary with @"name" and an optional @"children" array.
static NSDictionary *node(NSString *name, NSArray *children) {
    return children != nil ? [NSDictionary dictionaryWithObjectsAndKeys: name, @"name", children, @"children", nil]
                           : [NSDictionary dictionaryWithObjectsAndKeys: name, @"name", nil];
}

@interface TreeDelegate : NSObject <NSBrowserDelegate> {
@public
    NSDictionary *root;
}
@end

@implementation TreeDelegate
- (id) rootItemForBrowser: (NSBrowser *) browser { return root; }
- (NSInteger) browser: (NSBrowser *) browser numberOfChildrenOfItem: (id) item { return [[item objectForKey: @"children"] count]; }
- (id) browser: (NSBrowser *) browser child: (NSInteger) index ofItem: (id) item { return [[item objectForKey: @"children"] objectAtIndex: index]; }
- (BOOL) browser: (NSBrowser *) browser isLeafItem: (id) item { return [item objectForKey: @"children"] == nil; }
- (id) browser: (NSBrowser *) browser objectValueForItem: (id) item { return [item objectForKey: @"name"]; }
@end

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSDictionary *fruit = node(@"fruit", [NSArray arrayWithObjects: node(@"apple", nil), node(@"pear", nil), nil]);
    NSDictionary *veg = node(@"veg", [NSArray arrayWithObjects: node(@"leek", nil), node(@"kale", nil), node(@"beet", nil), nil]);
    NSDictionary *note = node(@"note", nil);
    TreeDelegate *delegate = [[[TreeDelegate alloc] init] autorelease];
    delegate->root = node(@"root", [NSArray arrayWithObjects: fruit, veg, note, nil]);

    NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 200)
                                                    styleMask: NSBorderlessWindowMask
                                                      backing: NSBackingStoreBuffered
                                                        defer: NO] autorelease];
    NSBrowser *browser = [[[NSBrowser alloc] initWithFrame: NSMakeRect(0, 0, 400, 200)] autorelease];
    [window setContentView: browser];
    [browser setDelegate: delegate];
    [browser loadColumnZero];

    CHECK([browser clickedColumn] == -1);
    CHECK([browser clickedRow] == -1);
    CHECK([browser lastColumn] == 0);
    CHECK([[browser itemAtRow: 0 inColumn: 0] isEqual: fruit]);
    CHECK([[browser itemAtRow: 1 inColumn: 0] isEqual: veg]);
    CHECK([[browser itemAtRow: 2 inColumn: 0] isEqual: note]);
    CHECK([[browser parentForItemsInColumn: 0] isEqual: delegate->root]);

    [browser selectRow: 1 inColumn: 0];
    CHECK([browser lastColumn] == 1);
    [browser selectRow: 2 inColumn: 1];
    CHECK([browser selectedRowInColumn: 1] == 2);
    CHECK([[browser parentForItemsInColumn: 1] isEqual: veg]);
    CHECK([[browser itemAtRow: 2 inColumn: 1] isEqual: [[veg objectForKey: @"children"] objectAtIndex: 2]]);

    [browser selectRow: 2 inColumn: 0];
    CHECK([browser lastColumn] == 0);

    // Properties.
    [browser setMinColumnWidth: 120];
    CHECK([browser minColumnWidth] == 120);
    [browser setDefaultColumnWidth: 150];
    CHECK([browser defaultColumnWidth] == 150);
    [browser setAutohidesScroller: YES];
    CHECK([browser autohidesScroller]);
    [browser setPrefersAllColumnUserResizing: YES];
    CHECK([browser prefersAllColumnUserResizing]);
    [browser setRowHeight: 30];
    CHECK([browser rowHeight] == 30);
    [browser setColumnsAutosaveName: @"vd-test-browser"];
    CHECK([[browser columnsAutosaveName] isEqualToString: @"vd-test-browser"]);
    [browser setColumnResizingType: NSBrowserUserColumnResizing];
    CHECK([browser columnResizingType] == NSBrowserUserColumnResizing);

    // A matrix selects by rectangle unless told otherwise.
    NSMatrix *matrix = [[[NSMatrix alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    CHECK([matrix isSelectionByRect]);
    [matrix setSelectionByRect: NO];
    CHECK(![matrix isSelectionByRect]);

    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
