// Copyright (C) 2026 Lubos Dolezel
//
// Contract: Apple AppKit documentation pages of NSMenuItem title (a non-optional String),
// NSPopUpButton and NSPopUpButtonCell itemTitles (the array holds an empty string for each
// separator item), NSMenu item(withTitle:) and indexOfItem(withTitle:) (the first item with a
// given title), and init(title:action:keyEquivalent:) (the title must not be nil; the caller
// passes an empty NSString for an item without a title). What is checked from that: -title never
// answers nil, for a titled item, an item created with an empty title, a separator item and an
// item whose title was set to nil; a titled item answers its title unchanged; a separator item
// stays a separator item; the first item whose title is @"" in a menu is found by the title
// lookups, a separator included (that last point is a reading of the pages together, not a
// sentence of any one of them); adding an empty-titled item to a pop-up does not remove a
// separator.
// nil is passed through a variable, since the parameter is nonnull in the header.
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

        id nilTitle = nil;
        NSMenuItem *cleared = [[[NSMenuItem alloc] initWithTitle: @"Gone" action: NULL keyEquivalent: @""] autorelease];
        [cleared setTitle: nilTitle];
        report(isEmptyString([cleared title]), "item whose title was set to nil answers a non-nil empty string");

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

        NSPopUpButtonCell *cell = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
        [cell addItemWithTitle: @"First"];
        [[cell menu] addItem: [NSMenuItem separatorItem]];
        [cell addItemWithTitle: @""];
        NSArray *cellTitles = [cell itemTitles];
        report([cellTitles count] == 3 && [[cellTitles objectAtIndex: 1] isEqual: @""] && [[cellTitles objectAtIndex: 2] isEqual: @""] &&
               [[[cell menu] itemAtIndex: 1] isSeparatorItem],
               "adding an empty-titled item to a pop-up keeps its separator, and itemTitles is all strings");

        NSPopUpButtonCell *second = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
        [[second menu] addItem: [NSMenuItem separatorItem]];
        [second addItemWithTitle: @""];
        // Retained so a new item cannot reuse its address and defeat the identity check below.
        NSMenuItem *oldEmpty = [[[second menu] itemAtIndex: 1] retain];
        [second addItemWithTitle: @""];
        report([[second menu] numberOfItems] == 2 && [[[second menu] itemAtIndex: 0] isSeparatorItem] &&
               ![[[second menu] itemAtIndex: 1] isSeparatorItem] && [[second menu] itemAtIndex: 1] != oldEmpty &&
               [[second menu] indexOfItem: oldEmpty] == -1,
               "adding an empty-titled item to [separator, empty-titled] replaces the old empty-titled item and keeps the separator");
        [oldEmpty release];
    }
    return failures != 0;
}
