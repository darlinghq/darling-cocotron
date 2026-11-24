// Copyright (C) 2026 Lubos Dolezel
//
// A menu that is inside its delegate's -menuNeedsUpdate: and is asked to update again. The reference says
// -menuNeedsUpdate: is sent just before a menu is shown, when tracking begins, that the delegate may
// change the menu there, and that the items are validated after it; it says nothing about the
// delegate updating the menu it was asked to update. The behaviour pinned here is a GUESS built on those
// statements: while a menu is waiting for its delegate, a nested update of the SAME menu does not send the
// delegate -menuNeedsUpdate: again (it would never end), and a different menu is not held back by it.
//
// Every delegate keeps a depth counter and gives up when it is called more than MAX_DEPTH deep, so that a
// framework that does recurse fails the checks instead of overflowing the stack.
// Needs no window server and no NSApplication (every item has no action). Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

#define MAX_DEPTH 6

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

typedef enum {
    ModePlain,          // log only
    ModeUpdateSelf,     // [menu update]
    ModeMutateAndUpdate, // remove the first item, add one, then [menu update]
    ModeMutateOnly,     // remove the first item, add one
    ModeRaise,          // [menu update], then raise (first call only)
    ModeUpdateOther,    // [other update] (another menu, or a submenu)
    ModeCopy,           // copy the menu and update the copy
} Mode;

static NSMutableArray *events;
static int depth, maxDepth;
static BOOL overflowed;

@interface Delegate : NSObject <NSMenuDelegate> {
@public
    NSString *name;
    Mode mode;
    NSMenu *other;
    BOOL raised;
    NSMenu *original;
}
@end

@implementation Delegate
- (void) menuNeedsUpdate: (NSMenu *) menu {
    if (depth >= MAX_DEPTH) {
        overflowed = YES;
        return;
    }
    depth++;
    if (depth > maxDepth)
        maxDepth = depth;
    @try {
        [events addObject: (menu == original || original == nil) ? name : [name stringByAppendingString: @"-copy"]];
        switch (mode) {
        case ModePlain:
            break;
        case ModeUpdateSelf:
            [menu update];
            break;
        case ModeMutateAndUpdate:
            [menu removeItemAtIndex: 0];
            [menu addItemWithTitle: @"Added" action: NULL keyEquivalent: @""];
            [menu update];
            break;
        case ModeMutateOnly:
            [menu removeItemAtIndex: 0];
            [menu addItemWithTitle: @"Added" action: NULL keyEquivalent: @""];
            break;
        case ModeRaise:
            [menu update];
            if (!raised) {
                raised = YES;
                [NSException raise: @"UpdateTestException" format: @"raised by the delegate"];
            }
            break;
        case ModeUpdateOther:
            [other update];
            break;
        case ModeCopy:
            if (menu == original) {
                NSMenu *copy = [menu copy];
                [copy update];
                [copy release];
            }
            break;
        }
    } @finally {
        depth--;
    }
}
@end

static NSMenu *makeMenu(NSString *title, Delegate **delegateOut, NSString *name, Mode mode) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle: title];
    Delegate *delegate = [[Delegate alloc] init];

    delegate->name = name;
    delegate->mode = mode;
    delegate->original = menu;
    [menu setDelegate: delegate];
    [menu addItemWithTitle: @"One" action: NULL keyEquivalent: @""];
    [menu addItemWithTitle: @"Two" action: NULL keyEquivalent: @""];
    if (delegateOut != NULL)
        *delegateOut = delegate;
    return menu;
}

static void reset(void) {
    [events removeAllObjects];
    depth = 0;
    maxDepth = 0;
    overflowed = NO;
}

static NSString *log_(void) {
    return [events componentsJoinedByString: @","];
}

static void expectEvents(NSString *want, const char *what) {
    NSString *got = log_();
    char message[200];

    snprintf(message, sizeof message, "%s: delegate calls [%s]", what, [want UTF8String]);
    expect([got isEqualToString: want], message);
    if (![got isEqualToString: want])
        printf("     got [%s], deepest %d, overflowed %d\n", [got UTF8String], maxDepth, overflowed);
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    events = [[NSMutableArray alloc] init];

    // A plain update asks the delegate once.
    {
        reset();
        NSMenu *menu = makeMenu(@"M", NULL, @"M", ModePlain);
        [menu update];
        expectEvents(@"M", "a normal update");
        expect(maxDepth == 1, "a normal update: not nested");
    }

    // The delegate updates the menu it was asked to update: asked once, no nesting.
    {
        reset();
        NSMenu *menu = makeMenu(@"M", NULL, @"M", ModeUpdateSelf);
        [menu update];
        expectEvents(@"M", "update of the menu inside its own -menuNeedsUpdate:");
        expect(maxDepth == 1 && !overflowed, "update of the menu inside its own -menuNeedsUpdate: does not recurse");
        // The guard is gone afterwards: a later update asks the delegate again, once.
        [events removeAllObjects];
        [menu update];
        expectEvents(@"M", "a later update after a nested one");
    }

    // The delegate changes the menu and then updates it.
    {
        reset();
        NSMenu *menu = makeMenu(@"M", NULL, @"M", ModeMutateAndUpdate);
        [menu update];
        expectEvents(@"M", "remove, add and update inside -menuNeedsUpdate:");
        expect([menu numberOfItems] == 2 && [[[menu itemAtIndex: 0] title] isEqualToString: @"Two"] &&
                       [[[menu itemAtIndex: 1] title] isEqualToString: @"Added"],
               "remove, add and update inside -menuNeedsUpdate: leaves the delegate's changes");
    }

    // Changing the items alone, without an update, asks once (adding and removing never update the menu).
    {
        reset();
        NSMenu *menu = makeMenu(@"M", NULL, @"M", ModeMutateOnly);
        [menu update];
        expectEvents(@"M", "remove and add inside -menuNeedsUpdate:");
    }

    // The delegate raises after updating: the guard is cleared, a later update asks the delegate again.
    {
        reset();
        NSMenu *menu = makeMenu(@"M", NULL, @"M", ModeRaise);
        BOOL caught = NO;
        @try {
            [menu update];
        } @catch (NSException *e) {
            caught = [[e name] isEqualToString: @"UpdateTestException"];
        }
        expect(caught, "the delegate's exception reaches the caller of -update");
        expectEvents(@"M", "update whose delegate raises");
        [events removeAllObjects];
        [menu update];
        expectEvents(@"M", "update after the delegate raised (the guard was cleared)");
    }

    // Two menus whose delegates update each other: each asked once, none held back by the other's update.
    {
        reset();
        Delegate *da, *db;
        NSMenu *a = makeMenu(@"A", &da, @"A", ModeUpdateOther);
        NSMenu *b = makeMenu(@"B", &db, @"B", ModeUpdateOther);
        da->other = b;
        db->other = a;
        [a update];
        expectEvents(@"A,B", "two menus updating each other");
        expect(maxDepth == 2 && !overflowed, "two menus updating each other: depth 2");
        [events removeAllObjects];
        [b update];
        expectEvents(@"B,A", "two menus updating each other, started from the other");
    }

    // A delegate that updates another menu: that menu's delegate is asked, once.
    {
        reset();
        Delegate *da;
        NSMenu *a = makeMenu(@"A", &da, @"A", ModeUpdateOther);
        NSMenu *b = makeMenu(@"B", NULL, @"B", ModePlain);
        da->other = b;
        [a update];
        expectEvents(@"A,B", "a delegate updating another menu");
    }

    // Submenus: an update goes through the submenus, each asked once; the parent being inside its delegate
    // does not stop a submenu from updating, and a submenu that updates itself is asked once.
    {
        reset();
        Delegate *dm, *ds;
        NSMenu *main = makeMenu(@"Main", &dm, @"Main", ModePlain);
        NSMenu *sub = makeMenu(@"Sub", &ds, @"Sub", ModeUpdateSelf);
        [[main itemAtIndex: 0] setSubmenu: sub];
        [main update];
        expectEvents(@"Main,Sub", "an update goes through the submenu");
        expect(maxDepth == 1, "a submenu that updates itself does not recurse");

        reset();
        dm->mode = ModeUpdateOther;
        dm->other = sub;
        ds->mode = ModePlain;
        [main update];
        expectEvents(@"Main,Sub,Sub", "the parent's delegate updating the submenu, then the update of the submenus");
    }

    // A copy made while the menu is inside its delegate is not inside one itself: it is asked once.
    {
        reset();
        NSMenu *menu = makeMenu(@"M", NULL, @"M", ModeCopy);
        [menu update];
        expectEvents(@"M,M-copy", "update of a copy made inside -menuNeedsUpdate:");
    }

    printf("%s\n", failures == 0 ? "PASS" : "FAIL");
    [pool release];
    return failures == 0 ? 0 : 1;
}
