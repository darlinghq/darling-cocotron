// Copyright (C) 2026 Lubos Dolezel
//
// NSToolbarItemGroup selectedIndex. The documentation (macOS 10.15) declares it as a
// read-write NSInteger property, "the index of the most recently selected subitem", and
// says that with the selectAny or momentary selection mode the value must not be taken to
// be the selected subitem. It states no default and says nothing about an index outside
// the subitems. Everything marked GUESS pins this implementation's choice, not a
// documented or measured value: the default is 0, the setter stores any value (negative or
// past the last subitem included), and neither the setter nor setSubitems: checks it
// against the subitems.
// Build: clang -fobjc-arc -framework AppKit appkit-toolbaritemgroup-selected-index.m
// Not covered: any selection of a subitem or any effect on drawing (the value is only
// stored), and isSelectedAtIndex: and setSelected:atIndex: (not implemented). On master the
// selectors do not exist: with ARC the test does not compile against master's header,
// without ARC the first call raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>

// the property is macOS 10.15 API; the guest has it whatever the build's deployment target is
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// An application subclass whose setter wraps the superclass one (the failing receiver in a
// real application was a subclass).
@interface MyGroup : NSToolbarItemGroup
- (void)setSelectedIndex:(NSInteger)index;
@end
@implementation MyGroup
- (void)setSelectedIndex:(NSInteger)index {
    (void)[self selectedIndex];
    [super setSelectedIndex:index];
}
@end

// Stands in for the group in a keyed archive, with no keys: the unarchiver maps it to the
// class under test.
@interface ArchivedStandIn : NSObject <NSCoding>
@end
@implementation ArchivedStandIn
- (void)encodeWithCoder:(NSCoder *)coder {}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static NSToolbarItemGroup *decoded(void) {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:[ArchivedStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:[NSToolbarItemGroup class] forClassName:@"ArchivedStandIn"];
    return [unarchiver decodeObjectForKey:@"root"];
}

static NSArray *twoItems(NSString *prefix) {
    return @[ [[NSToolbarItem alloc] initWithItemIdentifier:[prefix stringByAppendingString:@"0"]],
              [[NSToolbarItem alloc] initWithItemIdentifier:[prefix stringByAppendingString:@"1"]] ];
}

static void checkDefault(NSToolbarItemGroup *group) {
    CHECK([group selectedIndex] == 0);   // GUESS
}

static void checkRoundTrip(NSToolbarItemGroup *group) {
    NSInteger values[] = { 1, 2, 0, 1, 5, -1, 0 };
    for (int i = 0; i < 7; i++) {
        [group setSelectedIndex:values[i]];
        CHECK([group selectedIndex] == values[i]);   // 5 and -1: GUESS, no validation
    }

    // the value and the group's other state do not overwrite one another
    [group setSelectedIndex:1];
    [group setSelectionMode:NSToolbarItemGroupSelectionModeMomentary];
    [group setControlRepresentation:NSToolbarItemGroupControlRepresentationCollapsed];
    [group setLabel:@"Navigate"];
    [group setTag:9];
    CHECK([group selectedIndex] == 1);
    [group setSelectedIndex:3];
    CHECK([group selectionMode] == NSToolbarItemGroupSelectionModeMomentary);
    CHECK([group controlRepresentation] == NSToolbarItemGroupControlRepresentationCollapsed);
    CHECK([[group label] isEqualToString:@"Navigate"] && [group tag] == 9);
    [group setSelectionMode:NSToolbarItemGroupSelectionModeSelectAny];
    [group setControlRepresentation:NSToolbarItemGroupControlRepresentationExpanded];
    CHECK([group selectedIndex] == 3);

    // replacing the subitems neither changes the value nor is changed by it
    NSArray *items = twoItems(@"R");
    [group setSubitems:items];
    CHECK([group selectedIndex] == 3);                 // GUESS: not reset, not clamped
    [group setSelectedIndex:7];
    CHECK([group selectedIndex] == 7);                 // GUESS: past the last subitem is stored
    CHECK([[group subitems] count] == 2);
    CHECK([[group subitems] objectAtIndex:1] == [items objectAtIndex:1]);
}

int main(void) {
    @autoreleasepool {
        CHECK([NSToolbarItemGroup instancesRespondToSelector:@selector(selectedIndex)]);
        CHECK([NSToolbarItemGroup instancesRespondToSelector:@selector(setSelectedIndex:)]);

        NSToolbarItemGroup *plain = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"P"];
        checkDefault(plain);
        checkRoundTrip(plain);

        NSToolbarItemGroup *made = [NSToolbarItemGroup
            groupWithItemIdentifier:@"F"
                             images:@[ [[NSImage alloc] initWithSize:NSMakeSize(8, 8)],
                                       [[NSImage alloc] initWithSize:NSMakeSize(8, 8)] ]
                      selectionMode:NSToolbarItemGroupSelectionModeSelectAny
                             labels:nil target:nil action:NULL];
        checkDefault(made);
        checkRoundTrip(made);

        MyGroup *mine = [[MyGroup alloc] initWithItemIdentifier:@"S"];
        checkDefault(mine);
        checkRoundTrip(mine);

        NSToolbarItemGroup *fromArchive = decoded();
        CHECK(fromArchive != nil);
        checkDefault(fromArchive);
        checkRoundTrip(fromArchive);

        // groups do not share the value
        NSToolbarItemGroup *first = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"A"];
        NSToolbarItemGroup *second = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"B"];
        [first setSelectedIndex:4];
        checkDefault(second);
        [second setSelectedIndex:2];
        CHECK([first selectedIndex] == 4);

        // a copy keeps the value, and the two are independent afterwards
        NSToolbarItemGroup *original = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"C"];
        [original setSubitems:twoItems(@"C")];
        [original setSelectedIndex:1];
        NSToolbarItemGroup *copy = [original copy];
        CHECK([copy selectedIndex] == 1);
        [copy setSelectedIndex:0];
        CHECK([original selectedIndex] == 1);
        [original setSelectedIndex:5];
        CHECK([copy selectedIndex] == 0);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
