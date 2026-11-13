// Copyright (C) 2026 Lubos Dolezel
//
// Writes NSArchiver (typedstream) archives of scroll views, tables, split views and
// related containers into the directory given as argv[1], to be used as decoding
// fixtures. Build for x86_64 against the system frameworks and run on the Mac named
// by the fixture directory. The expected values are checked by
// tests/appkit-nonkeyed-containers.m.
#import <AppKit/AppKit.h>

static void put(NSString *dir, NSString *name, id root)
{
    @try {
        NSData *d = [NSArchiver archivedDataWithRootObject: root];
        [d writeToFile: [dir stringByAppendingPathComponent: name] atomically: NO];
        printf("%s %lu bytes\n", [name UTF8String], (unsigned long) [d length]);
    } @catch (NSException *e) {
        printf("%s EXC %s\n", [name UTF8String], [[e reason] UTF8String]);
    }
}

static NSTableView *makeTable(Class cls)
{
    NSTableView *tv = [[[cls alloc] initWithFrame: NSMakeRect(0, 0, 300, 120)] autorelease];
    NSTableColumn *c1 = [[[NSTableColumn alloc] initWithIdentifier: @"name"] autorelease];
    [c1 setWidth: 120];
    [c1 setMinWidth: 30];
    [c1 setMaxWidth: 400];
    [c1 setEditable: NO];
    [c1 setResizable: YES];
    [[c1 headerCell] setStringValue: @"Name"];
    NSTableColumn *c2 = [[[NSTableColumn alloc] initWithIdentifier: @"size"] autorelease];
    [c2 setWidth: 80];
    [c2 setMinWidth: 20];
    [c2 setMaxWidth: 200];
    [c2 setEditable: YES];
    [c2 setResizable: NO];
    [[c2 headerCell] setStringValue: @"Size"];
    [tv addTableColumn: c1];
    [tv addTableColumn: c2];
    [tv setRowHeight: 22];
    [tv setIntercellSpacing: NSMakeSize(4, 3)];
    [tv setAllowsMultipleSelection: YES];
    [tv setAllowsEmptySelection: NO];
    [tv setAllowsColumnReordering: NO];
    [tv setAllowsColumnResizing: YES];
    [tv setAllowsColumnSelection: YES];
    [tv setUsesAlternatingRowBackgroundColors: YES];
    [tv setGridStyleMask: NSTableViewSolidHorizontalGridLineMask];
    [tv setAutosaveName: @"fixtureTable"];
    [tv setAutosaveTableColumns: YES];
    [tv setDoubleAction: @selector(doubleClicked:)];
    return tv;
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *dir = [NSString stringWithUTF8String: argv[1]];

    [NSApplication sharedApplication];

    put(dir, @"tableview.typedstream", makeTable([NSTableView class]));
    put(dir, @"outlineview.typedstream", ({
        NSOutlineView *ov = (NSOutlineView *) makeTable([NSOutlineView class]);
        [ov setOutlineTableColumn: [ov tableColumnWithIdentifier: @"size"]];
        [ov setIndentationPerLevel: 11];
        [ov setIndentationMarkerFollowsCell: NO];
        [ov setAutoresizesOutlineColumn: NO];
        ov;
    }));

    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect(1, 2, 215, 140)] autorelease];
    [sv setHasVerticalScroller: YES];
    [sv setHasHorizontalScroller: NO];
    [sv setAutohidesScrollers: YES];
    [sv setBorderType: NSBezelBorder];
    [sv setLineScroll: 7];
    [sv setPageScroll: 33];
    [sv setDrawsBackground: NO];
    [sv setDocumentView: makeTable([NSTableView class])];
    put(dir, @"scrollview.typedstream", sv);

    NSScrollView *sv2 = [[[NSScrollView alloc] initWithFrame: NSMakeRect(3, 4, 100, 100)] autorelease];
    [sv2 setHasVerticalScroller: YES];
    [sv2 setHasHorizontalScroller: YES];
    [sv2 setBorderType: NSLineBorder];
    [sv2 setDocumentView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 500, 500)] autorelease]];
    put(dir, @"scrollview-both.typedstream", sv2);

    NSClipView *cv = [[[NSClipView alloc] initWithFrame: NSMakeRect(1, 1, 50, 60)] autorelease];
    [cv setBackgroundColor: [NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1]];
    [cv setDrawsBackground: NO];
    [cv setCopiesOnScroll: NO];
    [cv setDocumentView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)] autorelease]];
    put(dir, @"clipview.typedstream", cv);

    NSScroller *sc = [[[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 100)] autorelease];
    [sc setFloatValue: 0.25 knobProportion: 0.5];
    [sc setControlSize: NSSmallControlSize];
    [sc setEnabled: YES];
    [sc setAction: @selector(scrolled:)];
    put(dir, @"scroller.typedstream", sc);

    NSScroller *sch = [[[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 100, 15)] autorelease];
    [sch setFloatValue: 0.75 knobProportion: 0.1];
    put(dir, @"scroller-horizontal.typedstream", sch);

    NSSplitView *sp = [[[NSSplitView alloc] initWithFrame: NSMakeRect(5, 6, 300, 200)] autorelease];
    [sp setVertical: YES];
    [sp setDividerStyle: NSSplitViewDividerStyleThin];
    [sp addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 200)] autorelease]];
    [sp addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(101, 0, 199, 200)] autorelease]];
    [sp setAutosaveName: @"fixtureSplit"];
    put(dir, @"splitview.typedstream", sp);

    NSSplitView *sp2 = [[[NSSplitView alloc] initWithFrame: NSMakeRect(5, 6, 300, 200)] autorelease];
    [sp2 setVertical: NO];
    [sp2 setDividerStyle: NSSplitViewDividerStylePaneSplitter];
    put(dir, @"splitview-horizontal.typedstream", sp2);

    NSTableHeaderView *hv = [[[NSTableHeaderView alloc] initWithFrame: NSMakeRect(0, 0, 300, 17)] autorelease];
    put(dir, @"tableheaderview.typedstream", hv);

    NSComboBox *cb = [[[NSComboBox alloc] initWithFrame: NSMakeRect(0, 0, 140, 26)] autorelease];
    [cb addItemsWithObjectValues: [NSArray arrayWithObjects: @"One", @"Two", @"Three", nil]];
    [cb setNumberOfVisibleItems: 5];
    [cb setHasVerticalScroller: NO];
    [cb setCompletes: YES];
    [cb setIntercellSpacing: NSMakeSize(2, 3)];
    [cb setItemHeight: 20];
    [cb setButtonBordered: NO];
    [cb setStringValue: @"Two"];
    put(dir, @"combobox.typedstream", cb);

    [pool drain];
    return 0;
}
