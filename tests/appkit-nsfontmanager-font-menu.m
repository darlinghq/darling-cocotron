// Copyright (C) 2026 Lubos Dolezel
//
// Contract: Apple AppKit documentation pages of NSFontManager setFontMenu(_:) and
// fontMenu(_:) (external identifiers setFontMenu: and fontMenu:): setFontMenu: records the
// given menu as the application's Font menu; fontMenu: returns the menu connected to the font
// conversion system, creating it if necessary when the argument is true and not when it is
// false. What is checked from that: both selectors exist; after setFontMenu: the same menu
// object comes back from fontMenu:NO and fontMenu:YES; a fresh font manager has no menu to
// return for fontMenu:NO; replacing the menu lets the old one go (the manager does not leak
// it); a font manager that is deallocated lets its menu go.
// Placeholder pins, not documented behaviour (the pages state none of them, GUESS in the
// commit of the implementation): fontMenu:YES with no stored menu answers nil, as Darling
// builds no default Font menu; passing nil to setFontMenu: clears the stored menu (the Swift
// parameter is non-optional); the menu is retained, not just referenced. The first would
// change if a default Font menu were built.
// Exit codes: 5 a selector is missing, 1 a check failed (named on stderr), 0 pass.
#import <AppKit/AppKit.h>
#include <stdio.h>

#if __has_feature(objc_arc)
#define TEST_AUTORELEASE(x) (x)
#define TEST_SUPER_DEALLOC()
#else
#define TEST_AUTORELEASE(x) [(x) autorelease]
#define TEST_SUPER_DEALLOC() [super dealloc]
#endif

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int deallocatedMenus;

// A menu that counts its own deallocations, to see whether the font manager lets go of it.
@interface TrackedMenu : NSMenu
@end

@implementation TrackedMenu
- (void) dealloc {
    deallocatedMenus++;
    TEST_SUPER_DEALLOC();
}
@end

static NSMenu *trackedMenu(NSString *title) {
    return TEST_AUTORELEASE([[TrackedMenu alloc] initWithTitle: title]);
}

static void clearFontMenu(NSFontManager *fm) {
    NSMenu *none = nil;
    [fm setFontMenu: none];
}

static void test_set_and_get(NSFontManager *fm) {
    NSMenu *menu = trackedMenu(@"Font");
    [fm setFontMenu: menu];
    CHECK([fm fontMenu: NO] == menu);
    CHECK([fm fontMenu: YES] == menu);
    // Recording the menu already stored is harmless: it must not be released by the replacement.
    [fm setFontMenu: menu];
    CHECK([fm fontMenu: NO] == menu);
    clearFontMenu(fm);
}

static void test_clear(NSFontManager *fm) {
    NSMenu *menu = trackedMenu(@"Font");
    [fm setFontMenu: menu];
    CHECK([fm fontMenu: NO] == menu);
    clearFontMenu(fm);  // placeholder pin: nil clears
    CHECK([fm fontMenu: NO] == nil);
    CHECK([fm fontMenu: YES] == nil);  // placeholder pin: no default menu is built
}

static void test_replace_releases_old(NSFontManager *fm) {
    int before = deallocatedMenus;
    @autoreleasepool {
        [fm setFontMenu: trackedMenu(@"first")];
    }
    CHECK(deallocatedMenus == before);  // the manager still holds the first menu
    @autoreleasepool {
        NSMenu *second = trackedMenu(@"second");
        [fm setFontMenu: second];
        CHECK(deallocatedMenus == before + 1);  // the first menu was released by the replacement
        CHECK([fm fontMenu: NO] == second);
        clearFontMenu(fm);
    }
    CHECK(deallocatedMenus == before + 2);
}

static void test_clear_releases(NSFontManager *fm) {
    int before = deallocatedMenus;
    @autoreleasepool {
        [fm setFontMenu: trackedMenu(@"only")];
    }
    CHECK(deallocatedMenus == before);
    clearFontMenu(fm);
    CHECK(deallocatedMenus == before + 1);
}

static void test_manager_dealloc_releases(void) {
    int before = deallocatedMenus;
    @autoreleasepool {
        NSFontManager *own = [[NSFontManager alloc] init];
        CHECK([own fontMenu: NO] == nil);
        [own setFontMenu: trackedMenu(@"owned")];
        CHECK([own fontMenu: NO] != nil);
#if !__has_feature(objc_arc)
        [own release];
#endif
        own = nil;
    }
    CHECK(deallocatedMenus == before + 1);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSFontManager *fm = [NSFontManager sharedFontManager];
        if (![fm respondsToSelector: @selector(setFontMenu:)] ||
            ![fm respondsToSelector: @selector(fontMenu:)]) {
            fputs("-[NSFontManager setFontMenu:] or -fontMenu: is missing\n", stderr);
            return 5;
        }
        clearFontMenu(fm);

        test_set_and_get(fm);
        test_clear(fm);
        test_replace_releases_old(fm);
        test_clear_releases(fm);
        test_manager_dealloc_releases();

        if (failures == 0)
            puts("PASS appkit-nsfontmanager-font-menu");
    }
    return failures != 0;
}
