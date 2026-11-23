/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Undo and Redo share a letter and differ in Shift, as in the Edit menu of an application: Undo is "z" with the
// Command mask, Redo is either "Z" with the Command mask or "z" with Command and Shift. A key event with Shift held
// must reach Redo and one without it Undo, whatever the order of the two items and when the items live in different
// submenus. The X11 and Wayland backends deliver "Z" both as the characters and as the characters ignoring modifiers
// for Shift+z (the Shift level is kept); the other spellings are robustness cases. An item that agrees on Shift is preferred over one that
// matches only because Shift is not compared for a lowercase equivalent (the quirk of NSKeyEquivalentMatchesEvent,
// pinned by appkit-menu-key-equivalents.m, which this test leaves in force: Command+Shift+Z still performs a
// lone "z" item). A matching Redo that is disabled consumes the key: it must not turn into an Undo. A submenu is still
// asked through its own -performKeyEquivalent:, so a subclass that overrides it takes part in the search. A symbol
// key that needs Shift ("{") already agrees with an event that has it, so the order of such items is as it was.
// Needs no window server. Build without ARC.
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
    int undos;
    int redos;
    BOOL canUndo;
    BOOL canRedo;
}
- (void) undo: (id) sender;
- (void) redo: (id) sender;
@end

@implementation Target
- (void) undo: (id) sender { undos++; }
- (void) redo: (id) sender { redos++; }
- (BOOL) validateMenuItem: (NSMenuItem *) item {
    if ([item action] == @selector(undo:))
        return canUndo;
    if ([item action] == @selector(redo:))
        return canRedo;
    return YES;
}
@end

// An event as a backend delivers it: the characters and the characters ignoring modifiers as given.
static NSEvent *keyEvent(NSString *characters, NSString *ignoring, NSUInteger flags) {
    return [NSEvent keyEventWithType: NSKeyDown
                            location: NSZeroPoint
                       modifierFlags: flags
                           timestamp: 0
                        windowNumber: 0
                             context: nil
                          characters: characters
         charactersIgnoringModifiers: ignoring
                           isARepeat: NO
                             keyCode: 6];
}

static NSEvent *superZ(void) {
    return keyEvent(@"z", @"z", NSCommandKeyMask);
}

// Super+Shift+Z: the first is what both backends deliver, the others are robustness cases.
static NSArray *superShiftZ(void) {
    return @[
        keyEvent(@"Z", @"Z", NSCommandKeyMask | NSShiftKeyMask),
        keyEvent(@"Z", @"z", NSCommandKeyMask | NSShiftKeyMask),
        keyEvent(@"z", @"z", NSCommandKeyMask | NSShiftKeyMask),
    ];
}

static NSMenuItem *addItem(NSMenu *menu, Target *target, NSString *title, SEL action, NSString *key,
                           NSUInteger mask) {
    NSMenuItem *item = [menu addItemWithTitle: title action: action keyEquivalent: key];
    [item setTarget: target];
    [item setKeyEquivalentModifierMask: mask];
    return item;
}

static BOOL fires(NSMenu *menu, Target *target, NSEvent *event, int undos, int redos) {
    target->undos = target->redos = 0;
    BOOL handled = [menu performKeyEquivalent: event];
    return handled && target->undos == undos && target->redos == redos;
}

// Checks Super+Z and the three spellings of Super+Shift+Z against a menu laid out with Undo and Redo.
static void checkLayout(NSMenu *menu, Target *target, const char *layout) {
    char what[160];

    snprintf(what, sizeof what, "%s: Super+Z performs Undo", layout);
    expect(fires(menu, target, superZ(), 1, 0), what);

    NSUInteger i = 0;
    for (NSEvent *event in superShiftZ()) {
        snprintf(what, sizeof what, "%s: Super+Shift+Z performs Redo (spelling %lu)", layout, (unsigned long) i++);
        expect(fires(menu, target, event, 0, 1), what);
    }
}

// A submenu that overrides -performKeyEquivalent:.
@interface SpyMenu : NSMenu {
@public
    int calls;
    BOOL callsSuper;
    BOOL consumes;
}
@end

@implementation SpyMenu
- (BOOL) performKeyEquivalent: (NSEvent *) event {
    calls++;
    if (consumes)
        return YES;
    return callsSuper ? [super performKeyEquivalent: event] : NO;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Target *target = [[Target alloc] init];
        target->canUndo = target->canRedo = YES;

        // Redo as "Z" with the Command mask (Shift implied), after Undo.
        NSMenu *edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        addItem(edit, target, @"Redo", @selector(redo:), @"Z", NSCommandKeyMask);
        checkLayout(edit, target, "uppercase Redo after Undo");
        [edit release];

        // Redo as "z" with Command and Shift, after Undo.
        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        addItem(edit, target, @"Redo", @selector(redo:), @"z", NSCommandKeyMask | NSShiftKeyMask);
        checkLayout(edit, target, "Shift-mask Redo after Undo");
        [edit release];

        // Redo ahead of Undo: Command+Z must still reach Undo, which agrees on Shift, not the Redo that matches
        // without regard to it.
        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"Redo", @selector(redo:), @"z", NSCommandKeyMask | NSShiftKeyMask);
        addItem(edit, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        checkLayout(edit, target, "Shift-mask Redo before Undo");
        [edit release];

        // Redo and Undo in different submenus of a main menu, the one that does not agree first.
        NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
        NSMenu *file = [[NSMenu alloc] initWithTitle: @"File"];
        NSMenu *other = [[NSMenu alloc] initWithTitle: @"Other"];
        addItem(file, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        addItem(other, target, @"Redo", @selector(redo:), @"Z", NSCommandKeyMask);
        [[main addItemWithTitle: @"File" action: NULL keyEquivalent: @""] setSubmenu: file];
        [[main addItemWithTitle: @"Other" action: NULL keyEquivalent: @""] setSubmenu: other];
        checkLayout(main, target, "Undo and Redo in separate submenus");
        [main release];
        [file release];
        [other release];

        // Without a Redo item the Shift quirk stands: Command+Shift+Z performs the lone "z" item.
        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        for (NSEvent *event in superShiftZ())
            expect(fires(edit, target, event, 1, 0), "a lone Undo still matches Super+Shift+Z (Shift not compared)");
        [edit release];

        // A disabled Redo that agrees on Shift consumes Super+Shift+Z: nothing is performed, Undo least of all.
        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        addItem(edit, target, @"Redo", @selector(redo:), @"Z", NSCommandKeyMask);
        target->canRedo = NO;
        for (NSEvent *event in superShiftZ())
            expect(fires(edit, target, event, 0, 0), "disabled Redo consumes Super+Shift+Z without performing Undo");
        target->canRedo = YES;
        target->canUndo = NO;
        // A regression guard: this held before the search preferred items that agree on Shift.
        expect(fires(edit, target, superZ(), 0, 0), "disabled Undo consumes Super+Z without performing Redo");
        target->canUndo = YES;
        [edit release];

        // The same Redo with automatic enabling off: only isEnabled counts.
        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        [edit setAutoenablesItems: NO];
        addItem(edit, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        NSMenuItem *redo = addItem(edit, target, @"Redo", @selector(redo:), @"Z", NSCommandKeyMask);
        [redo setEnabled: NO];
        expect(fires(edit, target, [superShiftZ() objectAtIndex: 0], 0, 0),
               "automatic enabling off: a disabled Redo still consumes Super+Shift+Z");
        [redo setEnabled: YES];
        expect(fires(edit, target, [superShiftZ() objectAtIndex: 0], 0, 1),
               "automatic enabling off: an enabled Redo is performed");
        [edit release];

        // A submenu subclass that overrides -performKeyEquivalent: is consulted by the search of the menu above it.
        main = [[NSMenu alloc] initWithTitle: @"Main"];
        file = [[NSMenu alloc] initWithTitle: @"File"];
        SpyMenu *spy = [[SpyMenu alloc] initWithTitle: @"Spy"];
        addItem(file, target, @"Undo", @selector(undo:), @"z", NSCommandKeyMask);
        addItem(spy, target, @"Redo", @selector(redo:), @"Z", NSCommandKeyMask);
        [[main addItemWithTitle: @"File" action: NULL keyEquivalent: @""] setSubmenu: file];
        [[main addItemWithTitle: @"Spy" action: NULL keyEquivalent: @""] setSubmenu: spy];
        NSEvent *redoKey = [superShiftZ() objectAtIndex: 0];

        spy->callsSuper = YES;
        spy->calls = 0;
        expect(fires(main, target, redoKey, 0, 1) && spy->calls == 1,
               "an overriding submenu that calls super takes part: its Redo wins over the Undo before it");
        spy->callsSuper = NO;
        spy->calls = 0;
        expect(fires(main, target, redoKey, 1, 0) && spy->calls == 1,
               "an overriding submenu that finds nothing leaves the lenient Undo to be performed");
        spy->consumes = YES;
        spy->calls = 0;
        expect(fires(main, target, redoKey, 0, 0) && spy->calls == 1,
               "an overriding submenu that consumes the key ends the search without performing Undo");
        [main release];
        [file release];
        [spy release];

        // A symbol that needs Shift agrees with an event that has it: the first of two such items keeps the key, as
        // it did before items were told apart by Shift. A digit does not: the item that asks for Shift is preferred.
        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"First", @selector(undo:), @"{", NSCommandKeyMask);
        addItem(edit, target, @"Second", @selector(redo:), @"{", NSCommandKeyMask | NSShiftKeyMask);
        expect(fires(edit, target, keyEvent(@"{", @"{", NSCommandKeyMask | NSShiftKeyMask), 1, 0),
               "symbol: Command+Shift+{ still performs the first of two items for it");
        expect(fires(edit, target, keyEvent(@"{", @"{", NSCommandKeyMask), 1, 0),
               "symbol: Command+{ performs the first item");
        [edit release];

        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"Only", @selector(undo:), @"{", NSCommandKeyMask);
        expect(fires(edit, target, keyEvent(@"{", @"{", NSCommandKeyMask | NSShiftKeyMask), 1, 0),
               "symbol: a lone { item matches Command+Shift+{");
        [edit release];

        edit = [[NSMenu alloc] initWithTitle: @"Edit"];
        addItem(edit, target, @"First", @selector(undo:), @"1", NSCommandKeyMask);
        addItem(edit, target, @"Second", @selector(redo:), @"1", NSCommandKeyMask | NSShiftKeyMask);
        expect(fires(edit, target, keyEvent(@"1", @"1", NSCommandKeyMask | NSShiftKeyMask), 0, 1),
               "digit: Command+Shift+1 performs the item that asks for Shift");
        expect(fires(edit, target, keyEvent(@"1", @"1", NSCommandKeyMask), 1, 0),
               "digit: Command+1 performs the item that does not");
        [edit release];

        [target release];
    }
    printf("menu key equivalent shift preference: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
