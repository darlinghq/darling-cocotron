// Copyright (C) 2026 Lubos Dolezel
// NSMenuItem conforms to NSAccessibility and NSAccessibilityElement (documented in the
// "Conforms To" list of NSMenuItem). Checks that the property setters of the protocol
// are accepted and read back, and that the role is the menu item role. The pages give no
// accessibility defaults for menu items; the defaults checked below ("quirk") are observations of
// NSMenuItem on macOS 26.7.3 (see NSAccessibilityProtocols.m): element, menu item role, the item's
// title as title and label, owning menu as parent, no children (the submenu if there is one), zero frame.
// A copy keeps the label that was set on the original and none of the other values.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static BOOL same(id a, id b) {
    return a == b || [a isEqual: b];
}

static const char *str(id o) {
    return o ? [[o description] UTF8String] : "nil";
}

#define CHECK_EQ(a, b) do { id _a = (a), _b = (b); CHECK(same(_a, _b), "%s is %s, expected %s", #a, str(_a), str(_b)); } while (0)

// Runs one setter call and reports whether it raised.
#define CHECK_NO_RAISE(call) do { @try { call; } @catch (NSException *e) { CHECK(NO, "%s raised %s", #call, str([e reason])); } } while (0)

static void testSetters(NSMenuItem *item) {
    NSObject *other = [[[NSObject alloc] init] autorelease];
    NSRect frame = NSMakeRect(1, 2, 3, 4);

    CHECK_NO_RAISE([item setAccessibilityLabel: @"Label"]);
    CHECK_NO_RAISE([item setAccessibilityTitle: @"Title"]);
    CHECK_NO_RAISE([item setAccessibilityHelp: @"Help"]);
    CHECK_NO_RAISE([item setAccessibilityValue: @"Value"]);
    CHECK_NO_RAISE([item setAccessibilityValueDescription: @"Description"]);
    CHECK_NO_RAISE([item setAccessibilityRole: NSAccessibilityButtonRole]);
    CHECK_NO_RAISE([item setAccessibilitySubrole: NSAccessibilityUnknownSubrole]);
    CHECK_NO_RAISE([item setAccessibilityIdentifier: @"Identifier"]);
    CHECK_NO_RAISE([item setAccessibilityElement: NO]);
    CHECK_NO_RAISE([item setAccessibilityFrame: frame]);
    CHECK_NO_RAISE([item setAccessibilityParent: other]);
    CHECK_NO_RAISE([item setAccessibilityChildren: @[other]]);
    CHECK_NO_RAISE([item setAccessibilityEnabled: NO]);
    CHECK_NO_RAISE([item setAccessibilityFocused: YES]);
    CHECK_NO_RAISE([item setAccessibilitySelected: YES]);
    CHECK_NO_RAISE([item setAccessibilityExpanded: YES]);
    CHECK_NO_RAISE([item setAccessibilityRequired: YES]);
    CHECK_NO_RAISE([item setAccessibilityWindow: other]);
    CHECK_NO_RAISE([item setAccessibilityTopLevelUIElement: other]);
    CHECK_NO_RAISE([item setAccessibilityCustomActions: @[]]);

    CHECK_EQ([item accessibilityLabel], @"Label");
    CHECK_EQ([item accessibilityTitle], @"Title");
    CHECK_EQ([item accessibilityHelp], @"Help");
    CHECK_EQ([item accessibilityValue], @"Value");
    CHECK_EQ([item accessibilityValueDescription], @"Description");
    CHECK_EQ([item accessibilityRole], NSAccessibilityButtonRole);
    CHECK_EQ([item accessibilitySubrole], NSAccessibilityUnknownSubrole);
    CHECK_EQ([item accessibilityIdentifier], @"Identifier");
    CHECK(![item isAccessibilityElement], "the element flag was cleared");
    CHECK(NSEqualRects([item accessibilityFrame], frame), "the frame was set");
    CHECK_EQ([item accessibilityParent], other);
    CHECK_EQ([item accessibilityChildren], @[other]);
    CHECK(![item isAccessibilityEnabled], "the enabled flag was cleared");
    CHECK([item isAccessibilityFocused], "the focused flag was set");
    CHECK([item isAccessibilitySelected], "the selected flag was set");
    CHECK([item isAccessibilityExpanded], "the expanded flag was set");
    CHECK([item isAccessibilityRequired], "the required flag was set");
    CHECK_EQ([item accessibilityWindow], other);
    CHECK_EQ([item accessibilityTopLevelUIElement], other);
    CHECK_EQ([item accessibilityCustomActions], @[]);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: @"Open" action: NULL keyEquivalent: @""] autorelease];

        CHECK([item conformsToProtocol: @protocol(NSAccessibility)], "NSMenuItem conforms to NSAccessibility");
        CHECK([item conformsToProtocol: @protocol(NSAccessibilityElement)], "NSMenuItem conforms to NSAccessibilityElement");

        // quirk: defaults of a menu item
        CHECK_EQ([item accessibilityRole], NSAccessibilityMenuItemRole);
        CHECK_EQ([item accessibilityTitle], @"Open");
        CHECK_EQ([item accessibilityLabel], @"Open");
        CHECK_EQ([item accessibilityHelp], nil);
        CHECK_EQ([item accessibilityIdentifier], nil);
        CHECK_EQ([item accessibilityValue], nil);
        CHECK([item isAccessibilityElement], "an item is an element");
        CHECK_EQ([item accessibilityParent], nil);
        CHECK_EQ([item accessibilityChildren], @[]);
        CHECK_EQ([item accessibilityWindow], nil);
        CHECK_EQ([item accessibilityTopLevelUIElement], nil);
        CHECK(NSEqualRects([item accessibilityFrame], NSZeroRect), "no frame until set");
        CHECK([item isAccessibilityEnabled] == [item isEnabled], "enabled follows -isEnabled");

        // the owning menu is the parent; a submenu is the only child
        NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"Menu"] autorelease];
        [menu setAutoenablesItems: NO];
        [menu addItem: item];
        CHECK_EQ([item accessibilityParent], menu);
        NSMenu *submenu = [[[NSMenu alloc] initWithTitle: @"Sub"] autorelease];
        NSMenuItem *host = [[[NSMenuItem alloc] initWithTitle: @"Host" action: NULL keyEquivalent: @""] autorelease];
        [host setSubmenu: submenu];
        CHECK_EQ([host accessibilityChildren], @[submenu]);
        [item setEnabled: NO];
        CHECK(![item isAccessibilityEnabled], "a disabled item is not enabled");
        [item setEnabled: YES];

        // the default title and label follow the item's title
        [item setTitle: @"Close"];
        CHECK_EQ([item accessibilityTitle], @"Close");
        CHECK_EQ([item accessibilityLabel], @"Close");

        // A label round-trips; setting the title to nil replaces the default and does not change the item's title.
        [item setAccessibilityLabel: @"Open a document"];
        CHECK_EQ([item accessibilityLabel], @"Open a document");
        [item setAccessibilityTitle: nil];
        CHECK_EQ([item accessibilityTitle], nil);
        CHECK_EQ([item title], @"Close");

        // quirk: a copy keeps the label and none of the other values, and does not share them afterwards
        NSMenuItem *original = [[[NSMenuItem alloc] initWithTitle: @"Save" action: NULL keyEquivalent: @""] autorelease];
        [original setAccessibilityLabel: @"Original label"];
        [original setAccessibilityHelp: @"Original help"];
        NSMenuItem *copy = [[original copy] autorelease];
        CHECK(copy != original, "a copy is a new object");
        CHECK_EQ([copy accessibilityLabel], @"Original label");
        CHECK_EQ([copy accessibilityHelp], nil);
        CHECK_EQ([copy accessibilityRole], NSAccessibilityMenuItemRole);
        [copy setAccessibilityLabel: @"Copy label"];
        CHECK_EQ([original accessibilityLabel], @"Original label");
        CHECK_EQ([copy accessibilityLabel], @"Copy label");
        [original setAccessibilityHelp: @"Changed help"];
        CHECK_EQ([copy accessibilityHelp], nil);

        // All the documented setters are accepted on a regular item.
        testSetters([[[NSMenuItem alloc] initWithTitle: @"Edit" action: NULL keyEquivalent: @""] autorelease]);

        // A separator item takes the same properties; its title and label are empty strings.
        NSMenuItem *separator = [NSMenuItem separatorItem];
        CHECK([separator isSeparatorItem], "a separator item");
        CHECK_EQ([separator accessibilityRole], NSAccessibilityMenuItemRole);
        CHECK_EQ([separator accessibilityTitle], @"");
        CHECK_EQ([separator accessibilityLabel], @"");
        [separator setAccessibilityLabel: @"Divider"];
        CHECK_EQ([separator accessibilityLabel], @"Divider");
        testSetters([NSMenuItem separatorItem]);

        // A separator's copy is still a separator and keeps the label.
        NSMenuItem *separatorCopy = [[separator copy] autorelease];
        CHECK([separatorCopy isSeparatorItem], "the copy is a separator item");
        CHECK_EQ([separatorCopy accessibilityLabel], @"Divider");
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
