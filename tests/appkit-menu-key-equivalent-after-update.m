// Copyright (C) 2026 Lubos Dolezel
//
// A menu asked for a key equivalent first lets its delegate update it, and the delegate may add, remove or change
// items there; the items are looked at after that. An update for a key equivalent
// validates just the item whose key matches; an update for an opened menu validates them all
// (https://developer.apple.com/documentation/appkit/nsmenudelegate/menuneedsupdate(_:)). A submenu that fills
// itself in its delegate is searched too. Needs no window server. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

@interface Target : NSObject {
@public
    int hits;
    NSMutableArray *validated; // titles, in the order -validateMenuItem: was asked
}
- (void) act: (id) sender;
@end

@implementation Target
- (id) init {
    self = [super init];
    validated = [[NSMutableArray alloc] init];
    return self;
}
- (void) dealloc {
    [validated release];
    [super dealloc];
}
- (void) act: (id) sender { hits++; }
- (BOOL) validateMenuItem: (NSMenuItem *) item {
    [validated addObject: [item title]];
    return YES;
}
@end

// The delegate's -menuNeedsUpdate: runs a block on the menu and counts its calls.
@interface Updater : NSObject <NSMenuDelegate> {
@public
    int updates;
    void (^change)(NSMenu *);
}
- (void) setChange: (void (^)(NSMenu *)) block;
@end

@implementation Updater
- (void) setChange: (void (^)(NSMenu *)) block {
    [change release];
    change = [block copy];
}
- (void) dealloc {
    [change release];
    [super dealloc];
}
- (void) menuNeedsUpdate: (NSMenu *) menu {
    updates++;
    if (change != nil)
        change(menu);
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

static NSMenuItem *add(NSMenu *menu, Target *target, NSString *title, NSString *key) {
    NSMenuItem *item = [menu addItemWithTitle: title action: @selector(act:) keyEquivalent: key];
    [item setTarget: target];
    return item;
}

static NSMenu *threeItems(Target *target) {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"Test"] autorelease];
    add(menu, target, @"A", @"a");
    add(menu, target, @"B", @"b");
    add(menu, target, @"C", @"c");
    return menu;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Target *target = [[Target alloc] init];

        // A delegate that removes items: the count taken before the update is stale.
        NSMenu *menu = threeItems(target);
        Updater *remover = [[Updater alloc] init];
        [remover setChange: ^(NSMenu *m) {
            while ([m numberOfItems] > 1)
                [m removeItemAtIndex: 1];
        }];
        [menu setDelegate: remover];
        BOOL handled = NO;
        BOOL raised = NO;
        @try {
            handled = [menu performKeyEquivalent: keyEvent(@"c")];
        } @catch (NSException *e) {
            raised = YES;
        }
        expect(!raised, "a delegate that removes items does not make the search read past the end");
        expect(!handled && target->hits == 0, "a key equivalent of a removed item is not handled");
        expect([menu performKeyEquivalent: keyEvent(@"a")] && target->hits == 1,
               "the item that is left is still found");
        [remover setChange: nil];
        [menu setDelegate: nil];
        [remover release];

        // A delegate that adds items: the new item is found.
        menu = threeItems(target);
        Updater *adder = [[Updater alloc] init];
        [adder setChange: ^(NSMenu *m) {
            if ([m indexOfItemWithTitle: @"Z"] < 0)
                add(m, target, @"Z", @"z");
        }];
        [menu setDelegate: adder];
        target->hits = 0;
        expect([menu performKeyEquivalent: keyEvent(@"z")] && target->hits == 1,
               "an item the delegate adds in -menuNeedsUpdate: is found by its key equivalent");
        [adder setChange: nil];
        [menu setDelegate: nil];
        [adder release];

        // Only the matching item is validated for a key equivalent; opening the menu validates all of them.
        menu = threeItems(target);
        Updater *counter = [[Updater alloc] init];
        [menu setDelegate: counter];
        [target->validated removeAllObjects];
        target->hits = 0;
        expect([menu performKeyEquivalent: keyEvent(@"b")] && target->hits == 1, "the item B is performed");
        expect([target->validated containsObject: @"B"], "the matching item is validated");
        expect(![target->validated containsObject: @"A"] && ![target->validated containsObject: @"C"],
               "the other items are not validated for a key equivalent");
        expect(counter->updates == 1, "the delegate is asked to update once for a key equivalent");
        [target->validated removeAllObjects];
        [menu update];
        expect([target->validated count] >= 3 && [target->validated containsObject: @"A"] &&
               [target->validated containsObject: @"C"],
               "updating a menu for display still validates every item");
        [menu setDelegate: nil];
        [counter release];

        // A submenu that fills itself in its delegate is searched.
        menu = [[[NSMenu alloc] initWithTitle: @"Top"] autorelease];
        NSMenu *sub = [[[NSMenu alloc] initWithTitle: @"Sub"] autorelease];
        NSMenuItem *parent = [menu addItemWithTitle: @"Sub" action: NULL keyEquivalent: @""];
        [menu setSubmenu: sub forItem: parent];
        Updater *filler = [[Updater alloc] init];
        [filler setChange: ^(NSMenu *m) {
            if ([m numberOfItems] == 0)
                add(m, target, @"S", @"s");
        }];
        [sub setDelegate: filler];
        target->hits = 0;
        expect([menu performKeyEquivalent: keyEvent(@"s")] && target->hits == 1,
               "an item a submenu's delegate adds is found through the parent menu");
        [filler setChange: nil];
        [sub setDelegate: nil];
        [filler release];
        [target release];
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
