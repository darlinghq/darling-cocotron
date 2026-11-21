// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// An outline view's data source hears of sort descriptor changes through outlineView:sortDescriptorsDidChange:,
// with the old descriptors, also when they are set programmatically; setting the same array again is no change.
// The program passes unchanged on macOS 26.7.3 and 10.14.4.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

@interface Source : NSObject <NSOutlineViewDataSource> {
@public
    NSInteger calls;
    NSArray *lastOld;
    NSArray *descriptorsDuringCall;
}
@end

@implementation Source
- (NSInteger) outlineView: (NSOutlineView *) view numberOfChildrenOfItem: (id) item {
    return item == nil ? 2 : 0;
}
- (id) outlineView: (NSOutlineView *) view child: (NSInteger) index ofItem: (id) item {
    return index == 0 ? @"a" : @"b";
}
- (BOOL) outlineView: (NSOutlineView *) view isItemExpandable: (id) item {
    return NO;
}
- (id) outlineView: (NSOutlineView *) view objectValueForTableColumn: (NSTableColumn *) column byItem: (id) item {
    return item;
}
- (void) outlineView: (NSOutlineView *) view sortDescriptorsDidChange: (NSArray *) old {
    calls++;
    [lastOld release];
    lastOld = [old retain];
    [descriptorsDuringCall release];
    descriptorsDuringCall = [[view sortDescriptors] retain];
}
@end

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: @"name"] autorelease];
    [outline addTableColumn: column];
    [outline setOutlineTableColumn: column];
    Source *source = [[Source alloc] init];
    [outline setDataSource: source];

    NSArray *byName = @[ [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES] ];
    [outline setSortDescriptors: byName];
    expect(source->calls == 1, "setting sort descriptors tells the data source");
    expect([source->lastOld count] == 0, "with the old descriptors (none)");
    expect([source->descriptorsDuringCall isEqual: byName], "the new ones are set when it is told");

    NSArray *bySize = @[ [NSSortDescriptor sortDescriptorWithKey: @"size" ascending: NO] ];
    [outline setSortDescriptors: bySize];
    expect(source->calls == 2 && [source->lastOld isEqual: byName], "a second change, with the previous descriptors");

    [outline setSortDescriptors: [outline sortDescriptors]];
    expect(source->calls == 2, "setting the same descriptors again is no change");

    [outline setDataSource: nil];
    [outline release];
    [source release];
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    [pool release];
    return failures != 0;
}
