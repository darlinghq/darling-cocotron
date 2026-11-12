/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Key equivalent matching of NSMenu and NSButton: the default Command
// modifier, Control and Shift in the comparison, letter case with Shift,
// disabled items, validation, and the itemArray snapshot. No window is shown.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Target : NSObject {
@public
    int hits;
    BOOL validates;
}
- (void) act: (id) sender;
- (BOOL) validateMenuItem: (NSMenuItem *) item;
@end

@implementation Target
- (void) act: (id) sender { hits++; }
- (BOOL) validateMenuItem: (NSMenuItem *) item { return validates; }
@end

static NSEvent *keyEvent(NSString *characters, NSUInteger flags) {
    return [NSEvent keyEventWithType: NSKeyDown
                            location: NSZeroPoint
                       modifierFlags: flags
                           timestamp: 0
                        windowNumber: 0
                             context: nil
                          characters: characters
         charactersIgnoringModifiers: characters
                           isARepeat: NO
                             keyCode: 0];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Target *target = [[Target alloc] init];
        target->validates = YES;

        // A code-built item defaults to the Command modifier.
        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle: @"Quit" action: @selector(act:)
                                               keyEquivalent: @"q"];
        expect([quit keyEquivalentModifierMask] == NSCommandKeyMask,
               "initWithTitle:action:keyEquivalent: defaults to the Command modifier");
        [quit release];

        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Test"];
        [menu setAutoenablesItems: NO];
        NSMenuItem *item = [menu addItemWithTitle: @"Act" action: @selector(act:) keyEquivalent: @"a"];
        [item setTarget: target];

        expect([menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask)] && target->hits == 1,
               "Command+A performs the item");
        target->hits = 0;
        expect(![menu performKeyEquivalent: keyEvent(@"a", 0)] && target->hits == 0,
               "the plain key does not match a Command item");
        expect(![menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask | NSControlKeyMask)] &&
               target->hits == 0, "an extra Control modifier does not match");
        expect(![menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask | NSShiftKeyMask)] &&
               target->hits == 0, "an extra Shift modifier does not match a lowercase item");

        // Control as an explicit modifier.
        [item setKeyEquivalentModifierMask: NSControlKeyMask];
        expect([menu performKeyEquivalent: keyEvent(@"a", NSControlKeyMask)] && target->hits == 1,
               "an item with the Control modifier matches Control+A");
        target->hits = 0;
        expect(![menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask)] && target->hits == 0,
               "Command does not stand in for Control");

        // Explicit Shift accepts both spellings of the letter.
        [item setKeyEquivalentModifierMask: NSCommandKeyMask | NSShiftKeyMask];
        expect([menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask | NSShiftKeyMask)] &&
               target->hits == 1, "Command+Shift+a matches");
        expect([menu performKeyEquivalent: keyEvent(@"A", NSCommandKeyMask | NSShiftKeyMask)] &&
               target->hits == 2, "Command+Shift+A matches the same item");
        target->hits = 0;

        // An uppercase key equivalent implies Shift.
        [item setKeyEquivalent: @"A"];
        [item setKeyEquivalentModifierMask: NSCommandKeyMask];
        expect([menu performKeyEquivalent: keyEvent(@"A", NSCommandKeyMask | NSShiftKeyMask)] &&
               target->hits == 1, "an uppercase equivalent implies Shift");
        target->hits = 0;
        [item setKeyEquivalent: @"a"];
        [item setKeyEquivalentModifierMask: NSCommandKeyMask];

        // disabled_matching_item_consumes_the_key (QUIRK in -performKeyEquivalent:)
        [item setEnabled: NO];
        expect([menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask)] && target->hits == 0,
               "a matching disabled item consumes the key and is not performed");

        // Without automatic enabling only isEnabled counts, not validation.
        [item setEnabled: YES];
        target->validates = NO;
        expect([menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask)] && target->hits == 1,
               "validation is ignored when automatic enabling is off");
        target->hits = 0;

        // With automatic enabling, validation decides.
        [menu setAutoenablesItems: YES];
        expect([menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask)] && target->hits == 0,
               "automatic enabling: a failed validation stops the action");
        target->validates = YES;
        expect([menu performKeyEquivalent: keyEvent(@"a", NSCommandKeyMask)] && target->hits == 1,
               "automatic enabling: a passed validation performs the action");

        // itemArray is a snapshot.
        NSArray *before = [menu itemArray];
        NSUInteger count = [before count];
        [menu addItemWithTitle: @"Other" action: NULL keyEquivalent: @""];
        expect([before count] == count, "an earlier itemArray does not change when an item is added");
        expect(![before isKindOfClass: [NSMutableArray class]], "itemArray is not the internal mutable array");

        // Buttons compare Control and Shift as well.
        NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 24)];
        [button setTarget: target];
        [button setAction: @selector(act:)];
        [button setKeyEquivalent: @"b"];
        [button setKeyEquivalentModifierMask: NSCommandKeyMask];
        target->hits = 0;
        [button performKeyEquivalent: keyEvent(@"b", NSCommandKeyMask | NSShiftKeyMask)];
        expect(target->hits == 0, "a button ignores the key with an extra Shift modifier");
        [button performKeyEquivalent: keyEvent(@"b", NSCommandKeyMask | NSControlKeyMask)];
        expect(target->hits == 0, "a button ignores the key with an extra Control modifier");
        [button performKeyEquivalent: keyEvent(@"b", NSCommandKeyMask)];
        expect(target->hits == 1, "a button performs its exact key equivalent");
        [button release];

        [menu release];
        [target release];
    }
    printf("menu key equivalents: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
