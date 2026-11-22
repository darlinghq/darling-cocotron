// Copyright (C) 2026 Lubos Dolezel
//
// NSMenu adopts NSAppearanceCustomization: -appearance and -effectiveAppearance. The contract is
// the NSAppearanceCustomization reference
// (https://developer.apple.com/documentation/appkit/nsappearancecustomization):
//  - appearance defaults to nil, which means the receiver uses the appearance it inherits;
//  - a non-nil appearance is the one the receiver uses (effectiveAppearance returns it);
//  - effectiveAppearance is never nil.
// Observed on macOS 26.7.3 (case numbers of the probe in parentheses): a menu without an appearance has the
// application's effective appearance (642.*), a copy keeps the appearance, a copy of a hierarchy keeps the
// appearance of the top menu and of a submenu, a copy of a submenu alone keeps its own, and the copy has no
// supermenu (test_copy_of_a_hierarchy). Beyond that (marked GUESS in the implementation) the appearance a
// submenu inherits from its supermenu, or a menu attached to a view or window, was not observed.
// Build: clang -framework AppKit appkit-menu-appearance.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int notifications;

@interface Watcher : NSObject
@end
@implementation Watcher
- (void) observeValueForKeyPath: (NSString *) keyPath ofObject: (id) object change: (NSDictionary *) change context: (void *) context {
    notifications++;
}
@end

static void test_default_and_set(void) {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"m"] autorelease];
    NSAppearance *dark = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];
    NSAppearance *aqua = [NSAppearance appearanceNamed: NSAppearanceNameAqua];

    CHECK([menu conformsToProtocol: @protocol(NSAppearanceCustomization)]);
    CHECK([menu appearance] == nil);
    CHECK([menu effectiveAppearance] != nil);
    CHECK([menu effectiveAppearance] == [NSApp effectiveAppearance]);

    [menu setAppearance: dark];
    CHECK([menu appearance] == dark);
    CHECK([menu effectiveAppearance] == dark);

    [menu setAppearance: aqua];
    CHECK([menu effectiveAppearance] == aqua);

    [menu setAppearance: nil];
    CHECK([menu appearance] == nil);
    CHECK([menu effectiveAppearance] == [NSApp effectiveAppearance]);
}

static void test_effective_appearance_is_observable(void) {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"m"] autorelease];
    Watcher *watcher = [[Watcher new] autorelease];

    [menu addObserver: watcher forKeyPath: @"effectiveAppearance" options: 0 context: NULL];
    notifications = 0;
    [menu setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]];
    CHECK(notifications > 0);
    [menu removeObserver: watcher forKeyPath: @"effectiveAppearance"];
}

static void test_copy(void) {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"m"] autorelease];
    NSAppearance *dark = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];

    [menu setAppearance: dark];
    NSMenu *copy = [menu copy];
    CHECK([copy appearance] == dark);
    [copy release];
    CHECK([menu appearance] == dark);
}

static void test_copy_of_a_hierarchy(void) {
    NSAppearance *dark = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];
    NSAppearance *aqua = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    NSMenu *top = [[[NSMenu alloc] initWithTitle: @"top"] autorelease];
    NSMenu *sub = [[[NSMenu alloc] initWithTitle: @"sub"] autorelease];
    NSMenuItem *item = [top addItemWithTitle: @"Sub" action: NULL keyEquivalent: @""];

    [top setSubmenu: sub forItem: item];
    [top setAppearance: dark];
    [sub setAppearance: aqua];

    NSMenu *copy = [top copy];
    CHECK([copy supermenu] == nil);
    CHECK([copy appearance] == dark);
    CHECK([[[[copy itemAtIndex: 0] submenu] appearance] isEqual: aqua]);
    [copy release];

    NSMenu *subCopy = [sub copy];
    CHECK([subCopy appearance] == aqua);
    CHECK([subCopy supermenu] == nil);
    [subCopy release];
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_default_and_set());
    RUN(test_effective_appearance_is_observable());
    RUN(test_copy());
    RUN(test_copy_of_a_hierarchy());
    if (failures == 0)
        printf("PASS appkit-menu-appearance\n");
    [pool release];
    return failures != 0;
}
