#import <AppKit/AppKit.h>
#include <stdio.h>

#define EXPECT(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } } while (0)

// The members are the ones Apple's documentation lists (numberOfItemsInSection: throws for an unknown section is
// documented). Everything marked GUESS is not in the public documentation: raising for a duplicate identifier or an
// absent anchor, the sections surviving deleteAllItems, the reload marks. Each GUESS EXPECT pins one of those.
static BOOL raisesNamed(NSString *name, void (^block)(void)) {
    @try {
        block();
    } @catch (NSException *exception) {
        return [[exception name] isEqual: name];
    }
    return NO;
}
static BOOL raises(void (^block)(void)) { return raisesNamed(NSInvalidArgumentException, block); }
static BOOL notUnique(void (^block)(void)) { return raisesNamed(NSInternalInconsistencyException, block); }

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    Class cls = NSClassFromString(@"NSDiffableDataSourceSnapshot");
    EXPECT(cls != Nil, "NSDiffableDataSourceSnapshot is a class");
    NSDiffableDataSourceSnapshot *s = [[cls alloc] init];
    EXPECT([s isKindOfClass: [NSObject class]] && [s conformsToProtocol: @protocol(NSCopying)], "an NSObject that is NSCopying");

    EXPECT(s.numberOfItems == 0 && s.numberOfSections == 0 && [s.sectionIdentifiers count] == 0 &&
           [s.itemIdentifiers count] == 0, "a new snapshot is empty");

    NSString *a = [NSString stringWithFormat: @"%@", @"A"], *b = [NSString stringWithFormat: @"%@", @"B"];
    [s appendSectionsWithIdentifiers: @[ a, b ]];
    EXPECT(s.numberOfSections == 2 && [s.sectionIdentifiers isEqual: (@[ @"A", @"B" ])], "sections append in order");
    EXPECT([s numberOfItemsInSection: @"A"] == 0, "an empty section has 0 items");
    [s appendItemsWithIdentifiers: @[ @"a1", @"a2" ] intoSectionWithIdentifier: @"A"];
    [s appendItemsWithIdentifiers: @[ @"b1" ]];
    EXPECT([[s itemIdentifiersInSectionWithIdentifier: @"B"] isEqual: @[ @"b1" ]],
           "appendItems without a section goes to the last section");
    EXPECT(s.numberOfItems == 3 && [s.itemIdentifiers isEqual: (@[ @"a1", @"a2", @"b1" ])], "items in section order");
    EXPECT([s numberOfItemsInSection: @"A"] == 2, "numberOfItemsInSection");
    EXPECT([s indexOfItemIdentifier: @"b1"] == 2 && [s indexOfItemIdentifier: @"a2"] == 1, "item index counts across sections");
    EXPECT([s indexOfSectionIdentifier: @"B"] == 1, "section index");
    EXPECT([s indexOfItemIdentifier: @"zz"] == NSNotFound && [s indexOfSectionIdentifier: @"Z"] == NSNotFound,
           "an absent identifier has index NSNotFound");
    EXPECT([[s sectionIdentifierForSectionContainingItemIdentifier: @"b1"] isEqual: @"B"], "section of an item");
    EXPECT([s sectionIdentifierForSectionContainingItemIdentifier: @"zz"] == nil, "section of an absent item is nil");

    [s insertItemsWithIdentifiers: @[ @"a0" ] beforeItemWithIdentifier: @"a1"];
    [s insertItemsWithIdentifiers: @[ @"a3", @"a4" ] afterItemWithIdentifier: @"a2"];
    EXPECT([[s itemIdentifiersInSectionWithIdentifier: @"A"] isEqual: (@[ @"a0", @"a1", @"a2", @"a3", @"a4" ])],
           "insert before and after an item");
    [s insertSectionsWithIdentifiers: @[ @"S0" ] beforeSectionWithIdentifier: @"A"];
    [s insertSectionsWithIdentifiers: @[ @"S1" ] afterSectionWithIdentifier: @"B"];
    EXPECT([s.sectionIdentifiers isEqual: (@[ @"S0", @"A", @"B", @"S1" ])], "insert sections before and after");

    [s moveItemWithIdentifier: @"a4" beforeItemWithIdentifier: @"a0"];
    [s moveItemWithIdentifier: @"a0" afterItemWithIdentifier: @"b1"];
    EXPECT([[s itemIdentifiersInSectionWithIdentifier: @"A"] isEqual: (@[ @"a4", @"a1", @"a2", @"a3" ])] &&
           [[s itemIdentifiersInSectionWithIdentifier: @"B"] isEqual: (@[ @"b1", @"a0" ])],
           "move an item within and across sections");
    [s moveSectionWithIdentifier: @"S1" beforeSectionWithIdentifier: @"S0"];
    [s moveSectionWithIdentifier: @"S0" afterSectionWithIdentifier: @"B"];
    EXPECT([s.sectionIdentifiers isEqual: (@[ @"S1", @"A", @"B", @"S0" ])], "move sections");

    [s deleteItemsWithIdentifiers: @[ @"a4", @"a3" ]];
    EXPECT([[s itemIdentifiersInSectionWithIdentifier: @"A"] isEqual: (@[ @"a1", @"a2" ])], "delete items");
    [s deleteItemsWithIdentifiers: @[ @"a1", @"a2" ]];
    EXPECT([s.sectionIdentifiers containsObject: @"A"] && [s numberOfItemsInSection: @"A"] == 0,
           "GUESS: deleting the last item of a section keeps the section");
    [s deleteSectionsWithIdentifiers: @[ @"S0", @"S1" ]];
    EXPECT([s.sectionIdentifiers isEqual: (@[ @"A", @"B" ])] && s.numberOfItems == 2, "delete sections");
    [s deleteAllItems];
    EXPECT(s.numberOfItems == 0 && s.numberOfSections == 2, "GUESS: deleteAllItems keeps the sections");

    [s appendItemsWithIdentifiers: @[ @"x", @"y" ] intoSectionWithIdentifier: @"B"];
    NSDiffableDataSourceSnapshot *copy = [s copy];
    [s deleteItemsWithIdentifiers: @[ @"x" ]];
    [s appendSectionsWithIdentifiers: @[ @"C" ]];
    EXPECT([copy.itemIdentifiers isEqual: (@[ @"x", @"y" ])] && copy.numberOfSections == 2 && copy != s,
           "copy is independent of later changes");
    [copy deleteItemsWithIdentifiers: @[ @"y" ]];
    EXPECT([s.itemIdentifiers isEqual: @[ @"y" ]], "changes to a copy do not reach the original");

    EXPECT(raises(^{ [s numberOfItemsInSection: @"nope"]; }), "numberOfItemsInSection: an unknown section raises");
    EXPECT(notUnique(^{ [s appendSectionsWithIdentifiers: @[ @"A" ]]; }), "GUESS: a duplicate section raises NSInternalInconsistencyException");
    EXPECT(notUnique(^{ [s appendSectionsWithIdentifiers: @[ @"Q", @"Q" ]]; }) && s.numberOfSections == 3,
           "GUESS: duplicates within one call raise before anything is added");
    EXPECT(notUnique(^{ [s appendItemsWithIdentifiers: @[ @"y" ]]; }), "GUESS: a duplicate item raises NSInternalInconsistencyException");
    EXPECT(notUnique(^{ [s appendItemsWithIdentifiers: @[ @"fresh", @"fresh" ]]; }) && s.numberOfItems == 1,
           "GUESS: duplicates within one append call raise before anything is added");
    EXPECT(notUnique(^{ [s insertItemsWithIdentifiers: @[ @"y" ] beforeItemWithIdentifier: @"y"]; }) && s.numberOfItems == 1,
           "GUESS: inserting an identifier that is already present raises");
    EXPECT(notUnique(^{ [s insertSectionsWithIdentifiers: @[ @"A" ] afterSectionWithIdentifier: @"B"]; }) && s.numberOfSections == 3,
           "GUESS: inserting a section identifier that is already present raises");
    EXPECT(raises(^{ [s appendItemsWithIdentifiers: @[ @"n" ] intoSectionWithIdentifier: @"nope"]; }),
           "GUESS: an absent section raises");
    EXPECT(raises(^{ [s insertItemsWithIdentifiers: @[ @"n" ] beforeItemWithIdentifier: @"nope"]; }),
           "GUESS: an absent item anchor raises");
    EXPECT(raises(^{ [s insertSectionsWithIdentifiers: @[ @"N" ] afterSectionWithIdentifier: @"nope"]; }),
           "GUESS: an absent section anchor raises");
    EXPECT(raises(^{ [s deleteItemsWithIdentifiers: @[ @"nope" ]]; }), "GUESS: deleting an absent item raises");
    EXPECT(raises(^{ [s moveItemWithIdentifier: @"y" afterItemWithIdentifier: @"y"]; }),
           "GUESS: moving an item relative to itself raises");
    EXPECT(raises(^{ [s moveSectionWithIdentifier: @"A" beforeSectionWithIdentifier: @"nope"]; }),
           "GUESS: an absent move anchor raises");
    NSDiffableDataSourceSnapshot *none = [[cls alloc] init];
    EXPECT(raises(^{ [none appendItemsWithIdentifiers: @[ @"n" ]]; }), "GUESS: appending items with no section raises");

    [s reloadItemsWithIdentifiers: @[ @"y" ]];
    [s reloadSectionsWithIdentifiers: @[ @"A" ]];
    EXPECT([s.reloadedItemIdentifiers isEqual: @[ @"y" ]] && [s.reloadedSectionIdentifiers isEqual: @[ @"A" ]],
           "GUESS: reload marks the identifiers");
    EXPECT(raises(^{ [s reloadItemsWithIdentifiers: @[ @"nope" ]]; }), "GUESS: reloading an absent item raises");

    // Atomic: a call with an absent identifier changes nothing.
    NSDiffableDataSourceSnapshot *atomic = [[cls alloc] init];
    [atomic appendSectionsWithIdentifiers: @[ @"S1", @"S2" ]];
    [atomic appendItemsWithIdentifiers: @[ @"i1", @"i2" ] intoSectionWithIdentifier: @"S1"];
    EXPECT(raises(^{ [atomic deleteItemsWithIdentifiers: @[ @"i1", @"missing" ]]; }) && atomic.numberOfItems == 2,
           "GUESS: deleteItems with an absent identifier raises and deletes nothing");
    EXPECT(raises(^{ [atomic deleteSectionsWithIdentifiers: @[ @"S1", @"missing" ]]; }) && atomic.numberOfSections == 2,
           "GUESS: deleteSections with an absent identifier raises and deletes nothing");
    EXPECT(raises(^{ [atomic reloadItemsWithIdentifiers: @[ @"i1", @"missing" ]]; }) && [atomic.reloadedItemIdentifiers count] == 0,
           "GUESS: reloadItems with an absent identifier raises and marks nothing");
    EXPECT(raises(^{ [atomic reloadSectionsWithIdentifiers: @[ @"S1", @"missing" ]]; }) && [atomic.reloadedSectionIdentifiers count] == 0,
           "GUESS: reloadSections with an absent identifier raises and marks nothing");
    // Deleting a section drops its reload marks and its items' reload marks.
    [atomic reloadSectionsWithIdentifiers: @[ @"S1" ]];
    [atomic reloadItemsWithIdentifiers: @[ @"i1", @"i2" ]];
    [atomic deleteSectionsWithIdentifiers: @[ @"S1" ]];
    EXPECT([atomic.reloadedSectionIdentifiers count] == 0, "GUESS: deleting a section clears its reload mark");
    EXPECT([atomic.reloadedItemIdentifiers count] == 0, "GUESS: deleting a section clears the reload marks of its items");
    // Results are snapshots of the content, not live views of it.
    [atomic appendItemsWithIdentifiers: @[ @"j1" ] intoSectionWithIdentifier: @"S2"];
    NSArray *inSection = [atomic itemIdentifiersInSectionWithIdentifier: @"S2"];
    NSArray *all = atomic.itemIdentifiers, *sections = atomic.sectionIdentifiers;
    [atomic appendItemsWithIdentifiers: @[ @"j2" ]];
    [atomic appendSectionsWithIdentifiers: @[ @"S3" ]];
    EXPECT([inSection isEqual: @[ @"j1" ]] && [all isEqual: @[ @"j1" ]] && [sections isEqual: @[ @"S2" ]],
           "itemIdentifiersInSection, itemIdentifiers and sectionIdentifiers return copies, not live arrays");

    [pool drain];
    printf("PASS: NSDiffableDataSourceSnapshot\n");
    return 0;
}
