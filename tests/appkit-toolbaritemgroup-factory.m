// Copyright (C) 2026 Lubos Dolezel
//
// +[NSToolbarItemGroup groupWithItemIdentifier:images:selectionMode:labels:target:action:]
// (the Objective-C name of init(itemIdentifier:images:selectionMode:labels:target:action:))
// and selectionMode. The documentation says: the factory (macOS 10.15) creates a grouped
// toolbar item with the given identifier from an array of images presented as subitems, a
// selection mode that says how the group presents selections, labels that correspond to the
// images, and the target and action the toolbar calls upon selection (with a nil target
// the action goes to the first responder and up the responder chain); a group's subitems
// are the NSToolbarItems returned by subitems, whose actions the group prefers over its own
// when they have one, and selectionMode is a read-write property of the three cases
// selectOne, selectAny and momentary. Everything marked GUESS pins this implementation's
// choice, not a documented or measured value: the identifier of a subitem (the group's
// identifier, a dot and the position), a missing label (the item's default, an empty
// string), labels beyond the images being ignored, the target and action being the group's
// own with none on the subitems, a copy of a group sharing its subitems' objects, and the
// default selection mode of a group made another way (selectOne).
// Build: clang -fobjc-arc -framework AppKit appkit-toolbaritemgroup-factory.m
// Not covered: how the group is drawn or selected (the mode is only stored), selectedIndex,
// isSelected(at:), the titles factory and controlRepresentation, which are not implemented.
// On master the factory and selectionMode do not exist: with ARC the test does not compile
// against master's header, without ARC the factory call raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>

// the group's selection mode and factory are macOS 10.15 API; the guest has them whatever
// the build's deployment target is
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface ActionTarget : NSObject
- (void)hit:(id)sender;
@end
@implementation ActionTarget
- (void)hit:(id)sender {}
@end

// An application subclass, the way a real application makes its own group class.
@interface MyGroup : NSToolbarItemGroup
@end
@implementation MyGroup
@end

static NSImage *image(void) { return [[NSImage alloc] initWithSize:NSMakeSize(16, 16)]; }

int main(void) {
    @autoreleasepool {
        CHECK([NSToolbarItemGroup respondsToSelector:
            @selector(groupWithItemIdentifier:images:selectionMode:labels:target:action:)]);
        CHECK([NSToolbarItemGroup instancesRespondToSelector:@selector(selectionMode)]);
        CHECK([NSToolbarItemGroup instancesRespondToSelector:@selector(setSelectionMode:)]);

        ActionTarget *target = [ActionTarget new];
        NSArray *images = @[ image(), image(), image() ];
        NSArray *labels = @[ @"One", @"Two", @"Three" ];

        NSToolbarItemGroup *group = [NSToolbarItemGroup
            groupWithItemIdentifier:@"Group" images:images
                      selectionMode:NSToolbarItemGroupSelectionModeSelectAny
                             labels:labels target:target action:@selector(hit:)];
        CHECK(group != nil);
        CHECK([group isMemberOfClass:[NSToolbarItemGroup class]]);
        CHECK([[group itemIdentifier] isEqualToString:@"Group"]);
        CHECK([group selectionMode] == NSToolbarItemGroupSelectionModeSelectAny);
        CHECK([group target] == target);
        CHECK([group action] == @selector(hit:));
        CHECK([[group label] length] == 0);
        CHECK([group toolbar] == nil);

        // one subitem per image, in order, with the image and the label at its position
        NSArray *subitems = [group subitems];
        CHECK([subitems count] == 3);
        NSMutableSet *identifiers = [NSMutableSet setWithObject:[group itemIdentifier]];
        for (NSUInteger i = 0; i < [subitems count]; i++) {
            NSToolbarItem *subitem = subitems[i];
            CHECK([subitem isKindOfClass:[NSToolbarItem class]]);
            CHECK([subitem image] == images[i]);
            CHECK([[subitem label] isEqualToString:labels[i]]);
            CHECK([subitem toolbar] == nil);
            // GUESS: no target or action of their own, so the group's apply
            CHECK([subitem target] == nil);
            CHECK([subitem action] == NULL);
            [identifiers addObject:[subitem itemIdentifier]];
        }
        // GUESS: the identifiers are the group's, a dot and the position
        CHECK([identifiers count] == 4);
        CHECK([[subitems[0] itemIdentifier] isEqualToString:@"Group.0"]);
        CHECK([[subitems[2] itemIdentifier] isEqualToString:@"Group.2"]);
        // the subitems are independent of the group
        [subitems[1] setLabel:@"Changed"];
        CHECK([[group label] length] == 0);
        CHECK([[subitems[0] label] isEqualToString:@"One"]);

        // every selection mode is kept, whatever the arguments
        NSToolbarItemGroupSelectionMode modes[] = {
            NSToolbarItemGroupSelectionModeSelectOne,
            NSToolbarItemGroupSelectionModeSelectAny,
            NSToolbarItemGroupSelectionModeMomentary };
        for (int i = 0; i < 3; i++) {
            NSToolbarItemGroup *g = [NSToolbarItemGroup
                groupWithItemIdentifier:@"M" images:@[ image() ] selectionMode:modes[i]
                                 labels:@[ @"x" ] target:nil action:NULL];
            CHECK([g selectionMode] == modes[i]);
            CHECK([[g subitems] count] == 1);
            CHECK([g target] == nil);
            CHECK([g action] == NULL);
        }

        // no labels: the subitems have the default label
        NSToolbarItemGroup *unlabeled = [NSToolbarItemGroup
            groupWithItemIdentifier:@"U" images:images
                      selectionMode:NSToolbarItemGroupSelectionModeSelectOne
                             labels:nil target:target action:@selector(hit:)];
        CHECK([[unlabeled subitems] count] == 3);
        for (NSToolbarItem *subitem in [unlabeled subitems])
            CHECK([[subitem label] length] == 0);

        // GUESS: fewer labels than images leave the last subitems without one, more labels
        // than images are ignored
        NSToolbarItemGroup *few = [NSToolbarItemGroup
            groupWithItemIdentifier:@"F" images:images
                      selectionMode:NSToolbarItemGroupSelectionModeSelectOne
                             labels:@[ @"A" ] target:nil action:NULL];
        CHECK([[few subitems] count] == 3);
        CHECK([[[few subitems][0] label] isEqualToString:@"A"]);
        CHECK([[[few subitems][2] label] length] == 0);
        NSToolbarItemGroup *many = [NSToolbarItemGroup
            groupWithItemIdentifier:@"G" images:@[ image() ]
                      selectionMode:NSToolbarItemGroupSelectionModeSelectOne
                             labels:labels target:nil action:NULL];
        CHECK([[many subitems] count] == 1);
        CHECK([[[many subitems][0] label] isEqualToString:@"One"]);

        // no images: an empty group, not nil
        NSToolbarItemGroup *empty = [NSToolbarItemGroup
            groupWithItemIdentifier:@"E" images:@[]
                      selectionMode:NSToolbarItemGroupSelectionModeMomentary
                             labels:@[] target:nil action:NULL];
        CHECK(empty != nil);
        CHECK([[empty subitems] count] == 0);
        CHECK([empty selectionMode] == NSToolbarItemGroupSelectionModeMomentary);

        // two groups made from the same arrays do not share subitems
        NSToolbarItemGroup *again = [NSToolbarItemGroup
            groupWithItemIdentifier:@"Group" images:images
                      selectionMode:NSToolbarItemGroupSelectionModeSelectAny
                             labels:labels target:target action:@selector(hit:)];
        CHECK([again subitems][0] != [group subitems][0]);

        // the factory is a class method of the receiving class: a subclass gets its own kind
        MyGroup *mine = [MyGroup
            groupWithItemIdentifier:@"Mine" images:images
                      selectionMode:NSToolbarItemGroupSelectionModeSelectOne
                             labels:labels target:target action:@selector(hit:)];
        CHECK([mine isMemberOfClass:[MyGroup class]]);
        CHECK([[mine subitems] count] == 3);

        // selectionMode as a property: set, read back, independent of the rest
        NSToolbarItemGroup *plain = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"P"];
        CHECK([plain selectionMode] == NSToolbarItemGroupSelectionModeSelectOne);   // GUESS
        for (int i = 0; i < 3; i++) {
            [plain setSelectionMode:modes[i]];
            CHECK([plain selectionMode] == modes[i]);
        }
        [plain setLabel:@"Navigate"];
        [plain setTag:9];
        [plain setSubitems:@[]];
        CHECK([plain selectionMode] == NSToolbarItemGroupSelectionModeMomentary);
        [plain setSelectionMode:NSToolbarItemGroupSelectionModeSelectAny];
        CHECK([[plain label] isEqualToString:@"Navigate"] && [plain tag] == 9);
        // another group is not affected
        NSToolbarItemGroup *other = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"O"];
        CHECK([other selectionMode] == NSToolbarItemGroupSelectionModeSelectOne);

        // a copy keeps the mode and has its own array of the same subitems (GUESS: the same
        // objects), and it stays valid after the original is gone: the copy must own what it
        // refers to
        NSToolbarItemGroup *copy;
        NSArray *originalSubitems;
        @autoreleasepool {
            NSToolbarItemGroup *original = [NSToolbarItemGroup
                groupWithItemIdentifier:@"Original" images:images
                          selectionMode:NSToolbarItemGroupSelectionModeSelectAny
                                 labels:labels target:target action:@selector(hit:)];
            originalSubitems = [[original subitems] copy];
            copy = [original copy];
            CHECK([copy subitems] != [original subitems]);
            [copy setSelectionMode:NSToolbarItemGroupSelectionModeMomentary];
            CHECK([original selectionMode] == NSToolbarItemGroupSelectionModeSelectAny);
        }
        // the original has been released here
        CHECK([copy selectionMode] == NSToolbarItemGroupSelectionModeMomentary);
        CHECK([[copy subitems] count] == 3);
        CHECK([[copy subitems] isEqualToArray:originalSubitems]);
        CHECK([[copy subitems][0] image] == images[0]);
        CHECK([[[copy subitems][2] label] isEqualToString:@"Three"]);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
