// Copyright (C) 2026 Lubos Dolezel
//
// Contract: Apple AppKit documentation pages of NSMenuItem title (a non-optional String),
// NSPopUpButton and NSPopUpButtonCell itemTitles (the array holds an empty string for each
// separator item), NSMenu item(withTitle:) and indexOfItem(withTitle:) (the first item with a
// given title), and init(title:action:keyEquivalent:) (the title must not be nil; the caller
// passes an empty NSString for an item without a title). What is checked from that: -title never
// answers nil, for a titled item, an item created with an empty title, and a separator item; a titled item answers its title unchanged; a separator item
// stays a separator item; the first item whose title is @"" in a menu is found by the title
// lookups, a separator included (that last point is a reading of the pages together, not a
// sentence of any one of them); the pop-up quirks below (empty titles are not de-duplicated, a separator
// title selects nothing) are observations of macOS 26.7.3 and 10.14.4. A title set to nil is not
// tested: macOS raises an assertion for it.
// No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void report(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static BOOL isEmptyString(NSString *string) {
    return string != nil && [string isKindOfClass: [NSString class]] && [string length] == 0;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSMenuItem *titled = [[[NSMenuItem alloc] initWithTitle: @"Open" action: NULL keyEquivalent: @""] autorelease];
        report([[titled title] isEqualToString: @"Open"], "titled item answers its title");
        report(![titled isSeparatorItem], "titled item is not a separator");

        NSMenuItem *emptyTitled = [[[NSMenuItem alloc] initWithTitle: @"" action: NULL keyEquivalent: @""] autorelease];
        report(isEmptyString([emptyTitled title]), "item created with an empty title answers an empty string");
        report(![emptyTitled isSeparatorItem], "item created with an empty title is not a separator");

        NSMenuItem *separator = [NSMenuItem separatorItem];
        report(isEmptyString([separator title]), "separator item answers a non-nil empty string");
        report([separator isSeparatorItem], "separator item is still a separator");

        NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"Test"] autorelease];
        [menu addItem: titled];
        NSMenuItem *separatorInMenu = [NSMenuItem separatorItem];
        [menu addItem: separatorInMenu];
        [menu addItem: emptyTitled];
        NSArray *titles = [[menu itemArray] valueForKey: @"title"];
        report([titles count] == 3 && [[titles objectAtIndex: 1] isEqual: @""], "the titles of all items are strings, one per item");
        report([menu itemWithTitle: @""] == separatorInMenu, "itemWithTitle:@\"\" finds the first item with an empty title, the separator");
        report([menu indexOfItemWithTitle: @""] == 1, "indexOfItemWithTitle:@\"\" finds the first item with an empty title, the separator");
        report([menu indexOfItemWithTitle: @"Open"] == 0, "indexOfItemWithTitle: still finds a titled item");
        report([[separator description] length] > 0, "description of a separator item works");

        // QUIRK tests (see NSPopUpButtonCell.m): macOS 26.7.3 and 10.14.4 do not de-duplicate empty titles, so
        // adding @"" keeps a separator and an earlier empty-titled item, and itemTitles is all strings.
        NSPopUpButtonCell *cell = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
        [cell addItemWithTitle: @"First"];
        [[cell menu] addItem: [NSMenuItem separatorItem]];
        [cell addItemWithTitle: @""];
        NSArray *cellTitles = [cell itemTitles];
        report([cellTitles count] == 3 && [[cellTitles objectAtIndex: 1] isEqual: @""] && [[cellTitles objectAtIndex: 2] isEqual: @""] &&
               [[[cell menu] itemAtIndex: 1] isSeparatorItem],
               "quirk: adding an empty-titled item to a pop-up keeps its separator, and itemTitles is all strings");

        NSPopUpButtonCell *second = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
        [[second menu] addItem: [NSMenuItem separatorItem]];
        [second addItemWithTitle: @""];
        [second addItemWithTitle: @""];
        report([[second menu] numberOfItems] == 3 && [[[second menu] itemAtIndex: 0] isSeparatorItem] &&
               ![[[second menu] itemAtIndex: 1] isSeparatorItem] && ![[[second menu] itemAtIndex: 2] isSeparatorItem],
               "quirk: empty titles are not de-duplicated, [separator, empty] + empty has three items");

        // titled items are still de-duplicated, also behind a separator
        NSPopUpButtonCell *dedupe = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
        [dedupe addItemWithTitle: @"A"];
        [[dedupe menu] addItem: [NSMenuItem separatorItem]];
        [dedupe addItemWithTitle: @"B"];
        [dedupe addItemWithTitle: @"B"];
        [dedupe addItemWithTitle: @"A"];
        report([[dedupe menu] numberOfItems] == 3 && [[[dedupe menu] itemAtIndex: 0] isSeparatorItem] &&
               [[dedupe itemTitles] isEqual: @[@"", @"B", @"A"]],
               "an item with an existing title replaces the earlier one");

        // a title that only matches a separator selects nothing (quirk), removing it removes the separator
        NSPopUpButtonCell *select = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
        [select addItemWithTitle: @"A"];
        [[select menu] addItem: [NSMenuItem separatorItem]];
        [select selectItemWithTitle: @""];
        report([select indexOfSelectedItem] == -1, "quirk: selecting the title of a separator leaves no item selected");
        [select removeItemWithTitle: @""];
        report([[select menu] numberOfItems] == 1, "removeItemWithTitle:@\"\" removes the separator");
    }
    return failures != 0;
}
