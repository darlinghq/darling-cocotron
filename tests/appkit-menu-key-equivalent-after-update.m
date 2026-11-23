// Copyright (C) 2026 Lubos Dolezel
//
// What a menu does when it is asked for a key equivalent, as observed on macOS 26.7.3 and recorded in the
// scenarios below (the contract is NSMenu performKeyEquivalent:; the order of the calls is not documented, so each
// scenario is a QUIRK-level observation, tier 2, test_quirk_key_equivalent_search_*):
//  - the delegates of the menu and of every submenu below it are asked -menuHasKeyEquivalent:forEvent:target:action:
//    first (preorder); one that answers YES has its target and action performed and ends the search;
//  - -menuNeedsUpdate: is never sent during the search, so a delegate that rewrites an item's key equivalent there
//    has not done so yet: the new key finds nothing and the old key still works;
//  - then the items of the menu are validated (only when it enables its items itself), and walked in order: the
//    first whose key matches is performed, a submenu is searched through its own performKeyEquivalent: (which asks
//    its delegates and validates its items again) before the walk goes on.
// Needs no window server. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static NSMutableArray *events;

@interface Target : NSObject
- (void) act: (id) sender;
@end

@implementation Target
- (void) act: (id) sender {
    [events addObject: [NSString stringWithFormat: @"ACTION(%@)", [sender title]]];
}
- (BOOL) validateMenuItem: (NSMenuItem *) item {
    [events addObject: [NSString stringWithFormat: @"validate(%@)", [item title]]];
    return YES;
}
@end

@interface Delegate : NSObject <NSMenuDelegate> {
@public
    NSString *name;
    BOOL rewritesOnUpdate;
    BOOL answersKeyEquivalent;
    Target *target;
}
@end

@implementation Delegate
- (void) menuNeedsUpdate: (NSMenu *) menu {
    [events addObject: [NSString stringWithFormat: @"needsUpdate(%@)", name]];
    if (rewritesOnUpdate && [menu numberOfItems] > 0)
        [[menu itemAtIndex: 0] setKeyEquivalent: @"x"];
}
- (BOOL) menuHasKeyEquivalent: (NSMenu *) menu forEvent: (NSEvent *) event target: (id *) t action: (SEL *) a {
    [events addObject: [NSString stringWithFormat: @"hasKeyEquivalent(%@)", name]];
    if (!answersKeyEquivalent)
        return NO;
    *t = target;
    *a = @selector(act:);
    return YES;
}
@end

static NSEvent *keyEvent(NSString *characters) {
    return [NSEvent keyEventWithType: NSKeyDown
                            location: NSZeroPoint
                       modifierFlags: NSCommandKeyMask
                           timestamp: 0
                        windowNumber: 0
                             context: nil
                          characters: characters
         charactersIgnoringModifiers: characters
                           isARepeat: NO
                             keyCode: 0];
}

// main: File (S1: Open cmd-o, Save cmd-s, More (S1b: Deep cmd-d)), Edit (S2: Copy cmd-c), Top cmd-t.
// S1 and S1b enable their items automatically as S1 says; every menu has a delegate that logs its calls.
static void scenario(const char *what, BOOL autoMain, BOOL autoS1, BOOL autoS2, NSString *key, BOOL rewrite,
                     BOOL answer, BOOL wantResult, NSString *wantEvents)
{
    Target *target = [[Target alloc] init];
    NSMenu *main = [[NSMenu alloc] initWithTitle: @"main"];
    NSMenu *s1 = [[NSMenu alloc] initWithTitle: @"S1"];
    NSMenu *s2 = [[NSMenu alloc] initWithTitle: @"S2"];
    NSMenu *s1b = [[NSMenu alloc] initWithTitle: @"S1b"];
    NSArray *menus = @[ main, s1, s2, s1b ];
    NSArray *names = @[ @"main", @"S1", @"S2", @"S1b" ];
    for (int i = 0; i < 4; i++) {
        Delegate *delegate = [[Delegate alloc] init];
        delegate->name = names[i];
        delegate->target = target;
        delegate->rewritesOnUpdate = rewrite && i == 1;
        delegate->answersKeyEquivalent = answer && i == 1;
        [menus[i] setDelegate: delegate];
    }
    [main setAutoenablesItems: autoMain];
    [s1 setAutoenablesItems: autoS1];
    [s1b setAutoenablesItems: autoS1];
    [s2 setAutoenablesItems: autoS2];
    [[main addItemWithTitle: @"File" action: NULL keyEquivalent: @""] setSubmenu: s1];
    [[main addItemWithTitle: @"Edit" action: NULL keyEquivalent: @""] setSubmenu: s2];
    [main addItemWithTitle: @"Top" action: @selector(act:) keyEquivalent: @"t"];
    [s1 addItemWithTitle: @"Open" action: @selector(act:) keyEquivalent: @"o"];
    [s1 addItemWithTitle: @"Save" action: @selector(act:) keyEquivalent: @"s"];
    [[s1 addItemWithTitle: @"More" action: NULL keyEquivalent: @""] setSubmenu: s1b];
    [s1b addItemWithTitle: @"Deep" action: @selector(act:) keyEquivalent: @"d"];
    [s2 addItemWithTitle: @"Copy" action: @selector(act:) keyEquivalent: @"c"];
    for (NSMenu *menu in menus)
        for (NSMenuItem *item in [menu itemArray])
            if ([item action] != NULL)
                [item setTarget: target];

    [events removeAllObjects];
    BOOL result = [main performKeyEquivalent: keyEvent(key)];
    NSString *got = [events componentsJoinedByString: @" ; "];
    char message[200];
    snprintf(message, sizeof message, "%s: result %d", what, wantResult);
    expect(result == wantResult, message);
    snprintf(message, sizeof message, "%s: calls", what);
    expect([got isEqualToString: wantEvents], message);
    if (![got isEqualToString: wantEvents])
        fprintf(stderr, "  got  %s\n  want %s\n", [got UTF8String], [wantEvents UTF8String]);

    for (NSMenu *menu in menus)
        [menu setDelegate: nil];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        events = [[NSMutableArray alloc] init];

        scenario("found in the first submenu", YES, YES, YES, @"o", NO, NO, YES,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; hasKeyEquivalent(S2) ; "
                  "validate(Top) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; validate(Open) ; validate(Save) ; "
                  "ACTION(Open)");
        scenario("top-level item, found after both submenus were searched", YES, YES, YES, @"t", NO, NO, YES,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; hasKeyEquivalent(S2) ; "
                  "validate(Top) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; validate(Open) ; validate(Save) ; "
                  "hasKeyEquivalent(S1b) ; validate(Deep) ; hasKeyEquivalent(S2) ; validate(Copy) ; ACTION(Top)");
        scenario("not found", YES, YES, YES, @"z", NO, NO, NO,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; hasKeyEquivalent(S2) ; "
                  "validate(Top) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; validate(Open) ; validate(Save) ; "
                  "hasKeyEquivalent(S1b) ; validate(Deep) ; hasKeyEquivalent(S2) ; validate(Copy)");
        scenario("a submenu that does not enable its items itself is not validated", YES, NO, YES, @"o", NO, NO, YES,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; hasKeyEquivalent(S2) ; "
                  "validate(Top) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; ACTION(Open)");
        scenario("nothing validated when no menu enables its items itself", NO, NO, NO, @"o", NO, NO, YES,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; hasKeyEquivalent(S2) ; "
                  "hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; ACTION(Open)");

        // test_quirk_key_equivalent_search_does_not_update: the delegate that would turn cmd-o into cmd-x when asked
        // to update is never asked to, so cmd-x finds nothing and cmd-o still works.
        scenario("a key a delegate would set on update finds nothing", YES, YES, YES, @"x", YES, NO, NO,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; hasKeyEquivalent(S2) ; "
                  "validate(Top) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; validate(Open) ; validate(Save) ; "
                  "hasKeyEquivalent(S1b) ; validate(Deep) ; hasKeyEquivalent(S2) ; validate(Copy)");
        scenario("the key the delegate would replace still works", YES, YES, YES, @"o", YES, NO, YES,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; hasKeyEquivalent(S2) ; "
                  "validate(Top) ; hasKeyEquivalent(S1) ; hasKeyEquivalent(S1b) ; validate(Open) ; validate(Save) ; "
                  "ACTION(Open)");

        // test_quirk_key_equivalent_search_delegate_answers: a delegate that answers YES ends the search with its
        // own target and action (sent from the menu whose delegate answered), for any key.
        scenario("a delegate answering YES takes the key", YES, YES, YES, @"z", NO, YES, YES,
                 @"hasKeyEquivalent(main) ; hasKeyEquivalent(S1) ; ACTION(S1)");
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
