/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: unarchiving a split view keeps the frames its subviews were archived with, also when the
// archive reaches a subview before the split view (a nib that connects the subview first), where the
// split view is decoded while that subview is not complete. The pane splitter style has a divider
// 10 points thick, as in the preferences window of many applications: two panes of 177 and 688 points
// in a split view of 875 stay at x 0 and x 187.
// Prints PASS or FAIL.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: %s\n", __LINE__, [[NSString stringWithFormat: __VA_ARGS__] UTF8String]); } } while (0)

static NSSplitView *makeSplit(NSView **first, NSView **second) {
    NSSplitView *split = [[NSSplitView alloc] initWithFrame: NSMakeRect(0, 0, 875, 448)];
    [split setVertical: YES];
    [split setDividerStyle: NSSplitViewDividerStylePaneSplitter];
    NSView *p1 = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 177, 448)];
    NSView *p2 = [[NSView alloc] initWithFrame: NSMakeRect(187, 0, 688, 448)];
    [split addSubview: p1];
    [split addSubview: p2];
    *first = p1;
    *second = p2;
    return split;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSView *p1, *p2;
        NSSplitView *split = makeSplit(&p1, &p2);
        CHECK(NSEqualRects([p1 frame], NSMakeRect(0, 0, 177, 448)) && NSEqualRects([p2 frame], NSMakeRect(187, 0, 688, 448)),
              @"the archived split view does not have the intended frames: %@ %@", NSStringFromRect([p1 frame]), NSStringFromRect([p2 frame]));

        // The split view first, then a subview first.
        for (int order = 0; order < 2; order++) {
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject: order == 0 ? @[ split, p1 ] : @[ p1, split ]];
            NSArray *back = [NSKeyedUnarchiver unarchiveObjectWithData: data];
            NSSplitView *s = (NSSplitView *) (order == 0 ? back[0] : back[1]);
            NSArray *panes = [s subviews];
            CHECK([s isKindOfClass: [NSSplitView class]] && [panes count] == 2, @"order %d: %lu subviews", order, (unsigned long) [panes count]);
            if ([panes count] == 2) {
                CHECK(NSEqualRects([panes[0] frame], NSMakeRect(0, 0, 177, 448)), @"order %d: first pane %@", order, NSStringFromRect([panes[0] frame]));
                CHECK(NSEqualRects([panes[1] frame], NSMakeRect(187, 0, 688, 448)), @"order %d: second pane %@", order, NSStringFromRect([panes[1] frame]));
            }
        }
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
