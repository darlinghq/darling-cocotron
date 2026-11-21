// Copyright (C) 2026 Lubos Dolezel
//
// NSMenu adopts NSAppearanceCustomization: -appearance and -effectiveAppearance. The contract is
// the NSAppearanceCustomization reference
// (https://developer.apple.com/documentation/appkit/nsappearancecustomization):
//  - appearance defaults to nil, which means the receiver uses the appearance it inherits;
//  - a non-nil appearance is the one the receiver uses (effectiveAppearance returns it);
//  - effectiveAppearance is never nil.
// Beyond the reference (marked GUESS in the implementation): a menu without an appearance
// inherits the application's effective appearance, and a copy of a menu keeps its appearance.
// Written from the documentation; not yet run in a guest.
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

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    RUN(test_default_and_set());
    RUN(test_effective_appearance_is_observable());
    RUN(test_copy());
    if (failures == 0)
        printf("PASS appkit-menu-appearance\n");
    [pool release];
    return failures != 0;
}
