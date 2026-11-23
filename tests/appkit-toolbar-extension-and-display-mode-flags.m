// Copyright (C) 2026 Lubos Dolezel
//
// NSToolbar allowsDisplayModeCustomization and allowsExtensionItems, NSToolbarItem and
// NSMenuToolbarItem bordered. The documentation says: allowsDisplayModeCustomization (macOS
// 15) tells whether the user may change the display mode at run time, and defaults to YES
// for apps linked on macOS 15 and later; allowsExtensionItems (macOS 10.10) tells whether the
// toolbar can add items for Action extensions in its configuration panel, and defaults to
// NO; bordered (macOS 10.15) tells whether a toolbar item has a bordered style, defaults to
// NO, and, for an item with a custom view, is also applied to the view's bordered property
// if it has one; NSMenuToolbarItem is a toolbar item. The rest is black-box behaviour of macOS 26.7.3
// (probes toolbar.m and toolbar2.m): a program built against an older SDK sees NO as the display mode
// default, a view set after the flag is not given the flag, an item with a view that answers -isBordered
// answers that view's value, and a menu toolbar item is bordered until told otherwise. The program passes
// on 26.7.3; Mojave has none of these selectors.
// Build: clang -fobjc-arc -framework AppKit appkit-toolbar-extension-and-display-mode-flags.m
// Not covered: any effect on the toolbar or its drawing (the values are only stored; the
// display mode cannot be changed by the user and no extension items are offered). On master
// none of the four selectors exists: with ARC the test does not compile against master's
// headers, without ARC the calls raise unrecognized-selector exceptions.
#import <AppKit/AppKit.h>
#include <stdio.h>

// allowsDisplayModeCustomization is declared for macOS 15; the test runs on the guest, which
// has it whatever the deployment target of the build is.
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// The SDK the program was built against, packed as 0x000a0b00 for 10.11; the default of
// allowsDisplayModeCustomization depends on it.
extern uint32_t dyld_get_program_sdk_version(void);

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The legacy Objective-C runtime (i386) does not synthesize properties, so the helper
// classes declare plain instance variables.

// An application subclass that wraps the setters the way an override does.
@interface FlagToolbar : NSToolbar
- (void)setAllowsDisplayModeCustomization:(BOOL)flag;
- (void)setAllowsExtensionItems:(BOOL)flag;
@end
@implementation FlagToolbar
- (void)setAllowsDisplayModeCustomization:(BOOL)flag {
    (void)[self allowsDisplayModeCustomization];
    [super setAllowsDisplayModeCustomization:flag];
}
- (void)setAllowsExtensionItems:(BOOL)flag {
    (void)[self allowsExtensionItems];
    [super setAllowsExtensionItems:flag];
}
@end

@interface BorderedItem : NSMenuToolbarItem
- (void)setBordered:(BOOL)flag;
@end
@implementation BorderedItem
- (void)setBordered:(BOOL)flag {
    (void)[self isBordered];
    [super setBordered:flag];
}
@end

// A view that records what it is told.
@interface BorderView : NSView {
@public
    BOOL bordered;
    int calls;
}
- (void)setBordered:(BOOL)flag;
- (BOOL)isBordered;
@end
@implementation BorderView
- (void)setBordered:(BOOL)flag { bordered = flag; calls++; }
- (BOOL)isBordered { return bordered; }
@end

// Stands in for a class in a keyed archive, with no keys: the unarchiver maps it to the
// class under test.
@interface ArchivedStandIn : NSObject <NSCoding>
@end
@implementation ArchivedStandIn
- (void)encodeWithCoder:(NSCoder *)coder {}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static id decoded(Class cls) {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:[ArchivedStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:cls forClassName:@"ArchivedStandIn"];
    return [unarchiver decodeObjectForKey:@"root"];
}

static void checkToolbarDefaults(NSToolbar *toolbar) {
    // documented: YES for a program built against macOS 15 or later; QUIRK (macOS 26.7.3): for an older SDK it
    // follows allowsUserCustomization
    CHECK([toolbar allowsDisplayModeCustomization]
          == (dyld_get_program_sdk_version() >= 0x000f0000 || [toolbar allowsUserCustomization]));
    CHECK(![toolbar allowsExtensionItems]);
}

static void checkToolbarRoundTrip(NSToolbar *toolbar) {
    BOOL users = [toolbar allowsUserCustomization];
    NSToolbarDisplayMode mode = [toolbar displayMode];
    BOOL autosaves = [toolbar autosavesConfiguration];

    [toolbar setAllowsDisplayModeCustomization:NO];
    CHECK(![toolbar allowsDisplayModeCustomization]);
    CHECK(![toolbar allowsExtensionItems]);
    [toolbar setAllowsExtensionItems:YES];
    CHECK(![toolbar allowsDisplayModeCustomization]);
    CHECK([toolbar allowsExtensionItems]);
    [toolbar setAllowsDisplayModeCustomization:YES];
    CHECK([toolbar allowsDisplayModeCustomization]);
    CHECK([toolbar allowsExtensionItems]);
    [toolbar setAllowsExtensionItems:NO];
    CHECK([toolbar allowsDisplayModeCustomization]);
    CHECK(![toolbar allowsExtensionItems]);

    // the values do not overwrite the toolbar's other flags
    [toolbar setAllowsDisplayModeCustomization:NO];
    [toolbar setAllowsExtensionItems:YES];
    CHECK([toolbar allowsUserCustomization] == users);
    CHECK([toolbar displayMode] == mode);
    CHECK([toolbar autosavesConfiguration] == autosaves);
    [toolbar setAllowsUserCustomization:!users];
    [toolbar setAllowsDisplayModeCustomization:NO];
    [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [toolbar setAutosavesConfiguration:!autosaves];
    CHECK(![toolbar allowsDisplayModeCustomization]);
    CHECK([toolbar allowsExtensionItems]);

    // QUIRK (macOS 26.7.3, probe toolbar4.m): in a program built against an older SDK a change of
    // allowsUserCustomization replaces the value set before with its own
    if (dyld_get_program_sdk_version() < 0x000f0000) {
        BOOL user = [toolbar allowsUserCustomization];
        [toolbar setAllowsDisplayModeCustomization:!user];
        [toolbar setAllowsUserCustomization:user];   // no change: the value stays
        CHECK([toolbar allowsDisplayModeCustomization] == !user);
        [toolbar setAllowsUserCustomization:!user];
        CHECK([toolbar allowsDisplayModeCustomization] == !user);
        [toolbar setAllowsUserCustomization:user];
        CHECK([toolbar allowsDisplayModeCustomization] == user);
    }
}

// An item decoded from the stand-in archive has no keys, so its enabled state decodes as NO;
// only the items made in code start enabled.
static void checkItemDefaults(NSToolbarItem *item, BOOL madeInCode, BOOL bordered) {
    CHECK([item isBordered] == bordered);
    if (madeInCode)
        CHECK([item isEnabled]);
}

static void checkItemRoundTrip(NSToolbarItem *item) {
    NSInteger tag = [item tag];
    BOOL enabled = [item isEnabled];
    BOOL autovalidates = [item autovalidates];

    [item setBordered:YES];
    CHECK([item isBordered]);
    [item setBordered:NO];
    CHECK(![item isBordered]);
    [item setBordered:YES];
    CHECK([item isBordered]);
    // the value does not overwrite the item's other state, and the other state does not
    // overwrite it
    CHECK([item tag] == tag);
    CHECK([item isEnabled] == enabled);
    CHECK([item autovalidates] == autovalidates);
    [item setTag:7];
    [item setEnabled:!enabled];
    [item setAutovalidates:!autovalidates];
    [item setLabel:@"label"];
    CHECK([item isBordered]);
    [item setBordered:NO];
    CHECK([item tag] == 7);
    CHECK([item isEnabled] == !enabled);
    CHECK([item autovalidates] == !autovalidates);
}

int main(void) {
    @autoreleasepool {
        CHECK([NSToolbar instancesRespondToSelector:@selector(allowsDisplayModeCustomization)]);
        CHECK([NSToolbar instancesRespondToSelector:@selector(setAllowsDisplayModeCustomization:)]);
        CHECK([NSToolbar instancesRespondToSelector:@selector(allowsExtensionItems)]);
        CHECK([NSToolbar instancesRespondToSelector:@selector(setAllowsExtensionItems:)]);
        CHECK([NSToolbarItem instancesRespondToSelector:@selector(isBordered)]);
        CHECK([NSToolbarItem instancesRespondToSelector:@selector(setBordered:)]);
        CHECK([NSMenuToolbarItem instancesRespondToSelector:@selector(isBordered)]);
        CHECK([NSMenuToolbarItem instancesRespondToSelector:@selector(setBordered:)]);

        // toolbars: made in code, on a subclass whose setters wrap the superclass ones (the
        // failing receiver in a real application was a subclass), and decoded
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"t"];
        checkToolbarDefaults(toolbar);
        checkToolbarRoundTrip(toolbar);
        FlagToolbar *flagToolbar = [[FlagToolbar alloc] initWithIdentifier:@"f"];
        checkToolbarDefaults(flagToolbar);
        checkToolbarRoundTrip(flagToolbar);
        NSToolbar *fromArchive = decoded([NSToolbar class]);
        CHECK(fromArchive != nil);
        checkToolbarDefaults(fromArchive);
        checkToolbarRoundTrip(fromArchive);
        // two toolbars do not share the values
        NSToolbar *first = [[NSToolbar alloc] initWithIdentifier:@"a"];
        NSToolbar *second = [[NSToolbar alloc] initWithIdentifier:@"b"];
        [first setAllowsDisplayModeCustomization:NO];
        [first setAllowsExtensionItems:YES];
        checkToolbarDefaults(second);

        // toolbar items and menu toolbar items
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:@"i"];
        checkItemDefaults(item, YES, NO);
        checkItemRoundTrip(item);
        NSMenuToolbarItem *menuItem = [[NSMenuToolbarItem alloc] initWithItemIdentifier:@"m"];
        checkItemDefaults(menuItem, YES, YES);   // QUIRK: bordered until told otherwise
        checkItemRoundTrip(menuItem);
        CHECK([menuItem showsIndicator]);
        [menuItem setBordered:YES];
        [menuItem setShowsIndicator:NO];
        CHECK([menuItem isBordered]);
        [menuItem setShowsIndicator:YES];
        CHECK([menuItem isBordered]);
        BorderedItem *subclassed = [[BorderedItem alloc] initWithItemIdentifier:@"s"];
        checkItemDefaults(subclassed, YES, YES);
        checkItemRoundTrip(subclassed);
        NSToolbarItem *itemFromArchive = decoded([NSToolbarItem class]);
        CHECK(itemFromArchive != nil);
        checkItemDefaults(itemFromArchive, NO, NO);
        checkItemRoundTrip(itemFromArchive);
        NSMenuToolbarItem *menuFromArchive = decoded([NSMenuToolbarItem class]);
        CHECK(menuFromArchive != nil);
        checkItemDefaults(menuFromArchive, NO, YES);
        checkItemRoundTrip(menuFromArchive);

        // a copy keeps the value, and the two are independent afterwards
        NSToolbarItem *bordered = [[NSToolbarItem alloc] initWithItemIdentifier:@"c"];
        [bordered setBordered:YES];
        NSToolbarItem *copy = [bordered copy];
        CHECK([copy isBordered]);
        [copy setBordered:NO];
        CHECK([bordered isBordered]);
        NSToolbarItem *plain = [[NSToolbarItem alloc] initWithItemIdentifier:@"p"];
        CHECK(![[plain copy] isBordered]);

        // a custom view that has a bordered property gets the value
        BorderView *view = [[BorderView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
        NSToolbarItem *withView = [[NSToolbarItem alloc] initWithItemIdentifier:@"v"];
        [withView setView:view];
        CHECK(view->calls == 0);   // setting a view does not push the value (macOS 26.7.3)
        [withView setBordered:YES];
        CHECK(view->bordered);
        CHECK(view->calls == 1);
        [withView setBordered:NO];
        CHECK(!view->bordered);
        CHECK(view->calls == 2);
        // QUIRK (macOS 26.7.3): while the item has a view that answers -isBordered, so does the item
        view->bordered = YES;
        CHECK([withView isBordered]);
        view->bordered = NO;
        CHECK(![withView isBordered]);
        // a real control follows too
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
        NSToolbarItem *withButton = [[NSToolbarItem alloc] initWithItemIdentifier:@"b"];
        [button setBordered:NO];
        [withButton setView:button];
        CHECK(![withButton isBordered]);
        [withButton setBordered:YES];
        CHECK([button isBordered]);
        [withButton setBordered:NO];
        CHECK(![button isBordered]);
        // QUIRK (macOS 26.7.3): the view is told only when the item's value changes, so setting the
        // value it already has leaves a bordered button as it is
        NSButton *kept = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
        NSToolbarItem *withKept = [[NSToolbarItem alloc] initWithItemIdentifier:@"k"];
        [withKept setView:kept];
        [withKept setBordered:NO];
        CHECK([kept isBordered]);
        // a view without such a property is left alone
        NSView *plainView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
        NSToolbarItem *withPlainView = [[NSToolbarItem alloc] initWithItemIdentifier:@"w"];
        [withPlainView setView:plainView];
        [withPlainView setBordered:YES];
        CHECK([withPlainView isBordered]);
        CHECK([withPlainView view] == plainView);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
