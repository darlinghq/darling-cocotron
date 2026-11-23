// Copyright (C) 2026 Lubos Dolezel
// NSMenuItem conforms to NSAccessibility and NSAccessibilityElement (documented in the
// "Conforms To" list of NSMenuItem). Checks that the property setters of the protocol
// are accepted and read back, that the role is the menu item role, that a copy does not
// share what was set on the original, and that a separator item behaves the same.
// The pages give no accessibility defaults for menu items; checks marked GUESS pin this
// implementation's choice, not a documented value, and were not measured on macOS. Only
// the existence of the protocols, of the NSAccessibilityMenuItemRole constant and of the
// setters is documented; the label to AXDescription mapping is this repo's legacy mapping.
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

        // GUESS: the pages give no defaults. The role is the menu item role, the title is
        // the item's, and the label, help and identifier are nil.
        CHECK_EQ([item accessibilityRole], NSAccessibilityMenuItemRole);
        CHECK_EQ([item accessibilityTitle], @"Open");
        CHECK_EQ([item accessibilityLabel], nil);
        CHECK_EQ([item accessibilityHelp], nil);
        CHECK_EQ([item accessibilityIdentifier], nil);
        CHECK([item isAccessibilityElement], "GUESS: an item is an element");
        CHECK_EQ([item accessibilityParent], nil);
        CHECK_EQ([item accessibilityChildren], nil);
        CHECK(NSEqualRects([item accessibilityFrame], NSZeroRect), "GUESS: no frame until set");
        CHECK([item isAccessibilityEnabled] == [item isEnabled], "GUESS: enabled follows -isEnabled");

        // GUESS: the default title follows the item's title.
        [item setTitle: @"Close"];
        CHECK_EQ([item accessibilityTitle], @"Close");

        // A label round-trips. That the legacy description attribute reads it is this
        // repo's mapping, not a documented contract.
        [item setAccessibilityLabel: @"Open a document"];
        CHECK_EQ([item accessibilityLabel], @"Open a document");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CHECK_EQ([item accessibilityAttributeValue: NSAccessibilityDescriptionAttribute], @"Open a document");
#pragma clang diagnostic pop

        // Setting nil replaces the default; the title is not changed by the label.
        [item setAccessibilityTitle: nil];
        CHECK_EQ([item accessibilityTitle], nil);
        CHECK_EQ([item title], @"Close");

        // A copy does not share what was set on the original, in either direction.
        NSMenuItem *original = [[[NSMenuItem alloc] initWithTitle: @"Save" action: NULL keyEquivalent: @""] autorelease];
        [original setAccessibilityLabel: @"Original label"];
        [original setAccessibilityHelp: @"Original help"];
        NSMenuItem *copy = [[original copy] autorelease];
        CHECK(copy != original, "a copy is a new object");
        CHECK_EQ([copy accessibilityLabel], nil);
        CHECK_EQ([copy accessibilityHelp], nil);
        CHECK_EQ([copy accessibilityRole], NSAccessibilityMenuItemRole);  // GUESS: default role
        [copy setAccessibilityLabel: @"Copy label"];
        CHECK_EQ([original accessibilityLabel], @"Original label");
        CHECK_EQ([copy accessibilityLabel], @"Copy label");
        [original setAccessibilityHelp: @"Changed help"];
        CHECK_EQ([copy accessibilityHelp], nil);

        // All the documented setters are accepted on a regular item.
        testSetters([[[NSMenuItem alloc] initWithTitle: @"Edit" action: NULL keyEquivalent: @""] autorelease]);

        // A separator item takes the same properties.
        NSMenuItem *separator = [NSMenuItem separatorItem];
        CHECK([separator isSeparatorItem], "a separator item");
        CHECK_EQ([separator accessibilityRole], NSAccessibilityMenuItemRole);  // GUESS: not documented for separators
        // GUESS: the title follows -title, whether or not that is nil for a separator.
        CHECK_EQ([separator accessibilityTitle], [separator title]);
        CHECK_EQ([separator accessibilityLabel], nil);
        [separator setAccessibilityLabel: @"Divider"];
        CHECK_EQ([separator accessibilityLabel], @"Divider");
        testSetters([NSMenuItem separatorItem]);

        // A separator's copy is still a separator and starts without the label.
        NSMenuItem *separatorCopy = [[separator copy] autorelease];
        CHECK([separatorCopy isSeparatorItem], "the copy is a separator item");
        CHECK_EQ([separatorCopy accessibilityLabel], nil);
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
