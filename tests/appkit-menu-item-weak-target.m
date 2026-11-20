/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSMenuItem's target is a weak property (NSMenuItem.h): when the target
// object is deallocated, -target returns nil. A copy of the item holds the
// target weakly too. A menu whose item targeted a deallocated object, such as
// a submenu that was replaced, can still be updated and searched for key
// equivalents.
// Checked on macOS 26.7.3 and 10.14.4.
// Prints PASS/FAIL lines; exit status 1 on failure. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

@interface Target : NSObject
- (void) act: (id) sender;
@end

@implementation Target
- (void) act: (id) sender {
}
@end

int main(void) {
    // Unbuffered, so the lines before a crash are seen.
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"Item" action: @selector(act:) keyEquivalent: @""];
        NSMenuItem *copy;
        @autoreleasepool {
            Target *target = [[Target alloc] init];
            [item setTarget: target];
            expect([item target] == target, "the target is kept while it lives");
            copy = [item copy];
            expect([copy target] == target, "a copy has the same target");
            [target release];
        }
        expect([item target] == nil, "the target reads nil once it is deallocated");
        expect([copy target] == nil, "the copy's target reads nil once it is deallocated");

        @autoreleasepool {
            Target *again = [[Target alloc] init];
            [item setTarget: again];
            [item setTarget: nil];
            [again release];
        }
        expect([item target] == nil, "a target set to nil stays nil");
        [copy release];
        [item release];

        // A menu item whose target was a menu that went away, while the item
        // stays in a menu that is updated and asked for a key equivalent.
        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Main"];
        NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle: @"Sub" action: @selector(submenuAction:) keyEquivalent: @""];
        [menu addItem: parent];
        [menu addItemWithTitle: @"Other" action: @selector(act:) keyEquivalent: @"z"];
        @autoreleasepool {
            NSMenu *gone = [[NSMenu alloc] initWithTitle: @"Gone"];
            [parent setTarget: gone];
            [gone release];
        }
        expect([parent target] == nil, "a menu target reads nil once the menu is deallocated");
        [menu update];
        NSEvent *key = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint
                                   modifierFlags: NSEventModifierFlagCommand timestamp: 0 windowNumber: 0
                                         context: nil characters: @"z" charactersIgnoringModifiers: @"z"
                                       isARepeat: NO keyCode: 6];
        [menu performKeyEquivalent: key];
        expect(YES, "the menu is updated and searched for a key equivalent");
        [parent release];
        [menu release];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
