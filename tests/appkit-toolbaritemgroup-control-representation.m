// Copyright (C) 2026 Lubos Dolezel
//
// NSToolbarItemGroup controlRepresentation. The documentation (macOS 10.15) declares it as a
// read-write property that says how a toolbar displays a grouped toolbar item, of the enum
// NSToolbarItemGroupControlRepresentation with the cases automatic, expanded and collapsed.
// It states no default; macOS 26.7.3 starts at automatic and gives a copy the default too (probe
// tig.m, marked QUIRK for the copy).
// Build: clang -fobjc-arc -framework AppKit appkit-toolbaritemgroup-control-representation.m
// Not covered: any effect on how the group is displayed (the value is only stored). On
// master the selectors do not exist: with ARC the test does not compile against master's
// header, without ARC the first call raises an unrecognized selector.
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
- (void)setControlRepresentation:(NSToolbarItemGroupControlRepresentation)representation;
@end
@implementation MyGroup
- (void)setControlRepresentation:(NSToolbarItemGroupControlRepresentation)representation {
    (void)[self controlRepresentation];
    [super setControlRepresentation:representation];
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

static void checkDefault(NSToolbarItemGroup *group) {
    CHECK([group controlRepresentation] == NSToolbarItemGroupControlRepresentationAutomatic);   // observed on macOS 26.7.3
}

static void checkRoundTrip(NSToolbarItemGroup *group) {
    NSToolbarItemGroupControlRepresentation cases[] = {
        NSToolbarItemGroupControlRepresentationExpanded,
        NSToolbarItemGroupControlRepresentationCollapsed,
        NSToolbarItemGroupControlRepresentationAutomatic,
        NSToolbarItemGroupControlRepresentationCollapsed,
        NSToolbarItemGroupControlRepresentationExpanded };
    for (int i = 0; i < 5; i++) {
        [group setControlRepresentation:cases[i]];
        CHECK([group controlRepresentation] == cases[i]);
    }

    // the value and the group's other state do not overwrite one another
    [group setControlRepresentation:NSToolbarItemGroupControlRepresentationCollapsed];
    [group setSelectionMode:NSToolbarItemGroupSelectionModeMomentary];
    [group setLabel:@"Navigate"];
    [group setSubitems:@[]];
    CHECK([group controlRepresentation] == NSToolbarItemGroupControlRepresentationCollapsed);
    [group setControlRepresentation:NSToolbarItemGroupControlRepresentationExpanded];
    CHECK([group selectionMode] == NSToolbarItemGroupSelectionModeMomentary);
    CHECK([[group label] isEqualToString:@"Navigate"]);
    [group setSelectionMode:NSToolbarItemGroupSelectionModeSelectAny];
    CHECK([group controlRepresentation] == NSToolbarItemGroupControlRepresentationExpanded);
}

int main(void) {
    @autoreleasepool {
        CHECK([NSToolbarItemGroup instancesRespondToSelector:@selector(controlRepresentation)]);
        CHECK([NSToolbarItemGroup instancesRespondToSelector:@selector(setControlRepresentation:)]);

        NSToolbarItemGroup *plain = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"P"];
        checkDefault(plain);
        checkRoundTrip(plain);

        NSToolbarItemGroup *made = [NSToolbarItemGroup
            groupWithItemIdentifier:@"F" images:@[ [[NSImage alloc] initWithSize:NSMakeSize(8, 8)] ]
                      selectionMode:NSToolbarItemGroupSelectionModeSelectOne
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
        [first setControlRepresentation:NSToolbarItemGroupControlRepresentationCollapsed];
        checkDefault(second);

        // QUIRK (macOS 26.7.3, probe tig.m): a copy has the default value, and the two are independent
        NSToolbarItemGroup *original = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"C"];
        [original setControlRepresentation:NSToolbarItemGroupControlRepresentationExpanded];
        NSToolbarItemGroup *copy = [original copy];
        CHECK([copy controlRepresentation] == NSToolbarItemGroupControlRepresentationAutomatic);
        [copy setControlRepresentation:NSToolbarItemGroupControlRepresentationCollapsed];
        CHECK([original controlRepresentation] == NSToolbarItemGroupControlRepresentationExpanded);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
