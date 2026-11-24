/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Which menu item (or button) a key event performs: the key equivalent is compared with the event's
// charactersIgnoringModifiers as a whole string, so Shift counts only through the character it produces ("Z" for
// Shift+z, "{" for Shift+[), and the Shift flag of the event and the Shift bit of the item's mask play no part;
// Command, Option and Control must match exactly. Redo ("Z" with Command) therefore takes Shift+Command+Z, and
// Undo ("z" with Command) takes Command+Z, whatever the order of the items and the submenus they are in; an
// item "z" with Command and Shift in its mask does not take Shift+Command+Z (whose characters ignoring
// modifiers are "Z") but does take Command+Z. With Caps Lock in the event's flags the case of a letter follows
// the Shift flag instead of the characters.
//
// Every row is a layout (items "title:key:mask", mask letters c Command, s Shift, 0 none, a leading "-" on the
// title makes the item disabled, "|" starts the next submenu of a main menu) and the item each event of a list
// performs (a title, "." for no match, "!" for a match that consumed the key without performing anything: a disabled
// item). The tables are the observations of macOS 26.7.3 (mac-probes/cristim/batch12a/p766.m, p766b.m; the
// synthetic events also on 10.14.4, x86_64 and i386): "real" events are the ones AppKit makes from a CGEvent
// of the key code 6 (z), 33 ([), 18 (1) and 24 (=) with the given flags; the others are built by hand. The
// events X11 and Wayland deliver for Shift+Command+Z carry "Z" and "Z" as characters and characters ignoring
// modifiers, the same as the second event of the synthetic list.
// Test: this program (test_quirk_key_equivalent_compares_characters_ignoring_modifiers)
// Needs no window server.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

#define CM NSEventModifierFlagCommand
#define SH NSEventModifierFlagShift
#define CL NSEventModifierFlagCapsLock
#define OP NSEventModifierFlagOption
#define CT NSEventModifierFlagControl

static int failures;

typedef struct { const char *chars, *ign; NSUInteger flags; } Ev;
typedef struct { const char *layout, *expected; } Row;

@interface Target : NSObject {
@public
    NSString *last;
    int count;
}
- (void) fire: (id) sender;
@end

@implementation Target
- (void) fire: (id) sender {
    last = [(NSMenuItem *) sender title];
    count++;
}
@end

static Target *target;

static NSEvent *makeEvent(Ev e) {
    return [NSEvent keyEventWithType: NSEventTypeKeyDown
                            location: NSZeroPoint
                       modifierFlags: e.flags
                           timestamp: 0
                        windowNumber: 0
                             context: nil
                          characters: [NSString stringWithUTF8String: e.chars]
         charactersIgnoringModifiers: [NSString stringWithUTF8String: e.ign]
                           isARepeat: NO
                             keyCode: 6];
}

static NSUInteger maskOf(NSString *letters) {
    NSUInteger mask = 0;
    if ([letters containsString: @"c"]) mask |= CM;
    if ([letters containsString: @"s"]) mask |= SH;
    return mask;
}

// The menu of a layout, or with main set a main menu with one submenu per "|" part.
static NSMenu *build(NSString *layout, BOOL main) {
    NSMenu *top = [[NSMenu alloc] initWithTitle: @"Top"];
    NSMenu *current = main ? nil : top;

    [top setAutoenablesItems: NO];
    for (NSString *part in [layout componentsSeparatedByString: @"|"]) {
        if (main) {
            NSMenuItem *header = [top addItemWithTitle: @"H" action: NULL keyEquivalent: @""];
            current = [[NSMenu alloc] initWithTitle: @"S"];
            [current setAutoenablesItems: NO];
            [header setSubmenu: current];
        }
        for (NSString *spec in [part componentsSeparatedByString: @" "]) {
            if ([spec length] == 0)
                continue;
            NSArray *fields = [spec componentsSeparatedByString: @":"];
            NSString *title = [fields objectAtIndex: 0];
            BOOL disabled = [title hasPrefix: @"-"];
            if (disabled)
                title = [title substringFromIndex: 1];
            NSMenuItem *item = [current addItemWithTitle: title action: @selector(fire:)
                                           keyEquivalent: [fields objectAtIndex: 1]];
            [item setTarget: target];
            [item setKeyEquivalentModifierMask: maskOf([fields objectAtIndex: 2])];
            [item setEnabled: !disabled];
        }
    }
    return top;
}

static NSString *outcome(NSMenu *menu, Ev event) {
    target->last = nil;
    target->count = 0;
    BOOL handled = [menu performKeyEquivalent: makeEvent(event)];
    if (target->last != nil)
        return target->last;
    return handled ? @"!" : @".";
}

static void checkTable(const Row *rows, const Ev *events, int eventCount, const char *what, BOOL alsoMain) {
    for (const Row *row = rows; row->layout != NULL; row++) {
        NSArray *expected = [[NSString stringWithUTF8String: row->expected] componentsSeparatedByString: @","];
        for (int mode = 0; mode < (alsoMain ? 2 : 1); mode++) {
            NSMenu *menu = build([NSString stringWithUTF8String: row->layout], mode == 1);
            for (int i = 0; i < eventCount; i++) {
                NSString *got = outcome(menu, events[i]);
                BOOL ok = [got isEqualToString: [expected objectAtIndex: i]];
                if (!ok) {
                    printf("FAIL %s [%s]%s event %d (chars '%s' ign '%s' flags 0x%lx): got %s expected %s\n", what,
                           row->layout, mode ? " in a main menu" : "", i, events[i].chars, events[i].ign,
                           (unsigned long) events[i].flags, [got UTF8String],
                           [[expected objectAtIndex: i] UTF8String]);
                    failures++;
                }
            }
        }
    }
}

static const Row ZSYN[] = {
    { "U:z:c R:Z:c", "U,R,U,U,U,U,U,R,R,R" },
    { "R:Z:c U:z:c", "U,R,U,U,U,U,U,R,R,R" },
    { "U:z:c R:z:cs", "U,.,U,U,U,U,U,.,.,." },
    { "R:z:cs U:z:c", "R,.,R,R,R,R,R,.,.,." },
    { "U:z:c", "U,.,U,U,U,U,U,.,.,." },
    { "R:Z:c", ".,R,.,.,.,.,.,R,R,R" },
    { "R:z:cs", "R,.,R,R,R,R,R,.,.,." },
    { "U:z:0", ".,.,.,.,.,.,.,.,.,." },
    { "R:Z:0", ".,.,.,.,.,.,.,.,.,." },
    { "U:Z:cs", ".,U,.,.,.,.,.,U,U,U" },
    { "U:z:cs R:Z:c", "U,R,U,U,U,U,U,R,R,R" },
    { "U:z:c -R:Z:c", "U,!,U,U,U,U,U,!,!,!" },
    { "-U:z:c R:Z:c", "!,R,!,!,!,!,!,R,R,R" },
    { "U:z:c -R:z:cs", "U,.,U,U,U,U,U,.,.,." },
    { "-R:Z:c U:z:c", "U,!,U,U,U,U,U,!,!,!" },
    { "A:z:c B:z:cs C:Z:c", "A,C,A,A,A,A,A,C,C,C" },
    { "C:Z:c B:z:cs A:z:c", "B,C,B,B,B,B,B,C,C,C" },
    { "A:z:c B:Z:cs", "A,B,A,A,A,A,A,B,B,B" },
    { "U:z:c|R:Z:c", "U,R,U,U,U,U,U,R,R,R" },
    { "R:Z:c|U:z:c", "U,R,U,U,U,U,U,R,R,R" },
    { "U:z:c|R:z:cs", "U,.,U,U,U,U,U,.,.,." },
    { "R:z:cs|U:z:c", "R,.,R,R,R,R,R,.,.,." },
    { "U:z:c|-R:Z:c", "U,!,U,U,U,U,U,!,!,!" },
    { "U:z:c|U2:z:c", "U,.,U,U,U,U,U,.,.,." },
    { "R:Z:c R2:Z:c U:z:c", "U,R,U,U,U,U,U,R,R,R" },
    { "U:z:c U2:z:c R:Z:c", "U,R,U,U,U,U,U,R,R,R" },
    { NULL, NULL }
};
static const Row SSYN[] = {
    { "P:[:c Q:{:c", "P,P,Q,P,.,.,.,.,.,.,." },
    { "Q:{:c P:[:c", "P,P,Q,P,.,.,.,.,.,.,." },
    { "P:[:c Q:[:cs", "P,P,.,P,.,.,.,.,.,.,." },
    { "Q:[:cs P:[:c", "Q,Q,.,Q,.,.,.,.,.,.,." },
    { "P:[:c", "P,P,.,P,.,.,.,.,.,.,." },
    { "Q:{:c", ".,.,Q,.,.,.,.,.,.,.,." },
    { "Q:[:cs", "Q,Q,.,Q,.,.,.,.,.,.,." },
    { "P:1:c Q:!:c", ".,.,.,.,P,P,Q,P,.,.,." },
    { "Q:!:c P:1:c", ".,.,.,.,P,P,Q,P,.,.,." },
    { "P:1:c Q:1:cs", ".,.,.,.,P,P,.,P,.,.,." },
    { "Q:!:c", ".,.,.,.,.,.,Q,.,.,.,." },
    { "P:=:c Q:+:c", ".,.,.,.,.,.,.,.,P,P,Q" },
    { "Q:+:c P:=:c", ".,.,.,.,.,.,.,.,P,P,Q" },
    { "P:=:c Q:=:cs", ".,.,.,.,.,.,.,.,P,P,." },
    { "Q:+:c", ".,.,.,.,.,.,.,.,.,.,Q" },
    { "Q:+:cs", ".,.,.,.,.,.,.,.,.,.,Q" },
    { NULL, NULL }
};
static const Row ZREAL[] = {
    { "U:z:c R:Z:c", "U,R,U,R,.,.,.,.,.,." },
    { "R:Z:c U:z:c", "U,R,U,R,.,.,.,.,.,." },
    { "U:z:c R:z:cs", "U,.,U,.,.,.,.,.,.,." },
    { "R:z:cs U:z:c", "R,.,R,.,.,.,.,.,.,." },
    { "U:z:c", "U,.,U,.,.,.,.,.,.,." },
    { "R:Z:c", ".,R,.,R,.,.,.,.,.,." },
    { "R:z:cs", "R,.,R,.,.,.,.,.,.,." },
    { "U:Z:cs", ".,U,.,U,.,.,.,.,.,." },
    { "U:z:0", ".,.,.,.,U,.,U,.,.,." },
    { "U:z:s", ".,.,.,.,U,.,U,.,.,." },
    { "U:Z:0", ".,.,.,.,.,U,.,U,.,." },
    { "U:z:c|R:z:cs", "U,.,U,.,.,.,.,.,.,." },
    { "R:z:cs|U:z:c", "R,.,R,.,.,.,.,.,.,." },
    { NULL, NULL }
};
static const Row XSYN[] = {
    { "U:z:c R:Z:c", "R,R,R,R,U,U,U,." },
    { "R:Z:c U:z:c", "R,R,R,R,U,U,U,." },
    { "U:z:c R:z:cs", ".,.,.,.,U,U,U,." },
    { "R:z:cs U:z:c", ".,.,.,.,R,R,R,." },
    { "U:z:c", ".,.,.,.,U,U,U,." },
    { "R:Z:c", "R,R,R,R,.,.,.,." },
    { "R:z:cs", ".,.,.,.,R,R,R,." },
    { "U:Z:cs", "U,U,U,U,.,.,.,." },
    { "U:z:0", ".,.,.,.,.,.,.,." },
    { "U:z:s", ".,.,.,.,.,.,.,." },
    { "U:Z:0", ".,.,.,.,.,.,.,." },
    { "U:z:c|R:z:cs", ".,.,.,.,U,U,U,." },
    { "R:z:cs|U:z:c", ".,.,.,.,R,R,R,." },
    { NULL, NULL }
};
static const Row SREAL[] = {
    { "P:[:c Q:{:c", "P,Q,.,.,.,." },
    { "Q:{:c P:[:c", "P,Q,.,.,.,." },
    { "P:[:c Q:[:cs", "P,.,.,.,.,." },
    { "Q:[:cs P:[:c", "Q,.,.,.,.,." },
    { "P:[:c", "P,.,.,.,.,." },
    { "Q:{:c", ".,Q,.,.,.,." },
    { "Q:[:cs", "Q,.,.,.,.,." },
    { "P:1:c Q:!:c", ".,.,P,Q,.,." },
    { "P:1:c Q:1:cs", ".,.,P,.,.,." },
    { "Q:!:c", ".,.,.,Q,.,." },
    { "P:=:c Q:+:c", ".,.,.,.,P,Q" },
    { "Q:+:c", ".,.,.,.,.,Q" },
    { "Q:+:cs", ".,.,.,.,.,Q" },
    { "P:=:c", ".,.,.,.,P,." },
    { NULL, NULL }
};

// letters, as typed by hand (the event of a Shift key press has the flag but may carry either case)
static const Ev zSynthetic[] = {
    { "z", "z", CM }, { "Z", "Z", CM | SH }, { "Z", "z", CM | SH }, { "z", "z", CM | SH },
    { "z", "z", CM | CL }, { "Z", "z", CM | CL }, { "Z", "Z", CM | CL },
    { "Z", "z", CM | SH | CL }, { "z", "z", CM | SH | CL }, { "Z", "Z", CM | SH | CL },
};
// what AppKit makes of the key code 6 with these flags
static const Ev zReal[] = {
    { "z", "z", CM }, { "z", "Z", CM | SH }, { "z", "z", CM | CL }, { "z", "Z", CM | SH | CL },
    { "z", "z", 0 }, { "Z", "Z", SH }, { "Z", "z", CL }, { "Z", "Z", SH | CL },
    { "\316\251", "z", CM | OP }, { "\032", "z", CM | CT },
};
static const Ev zOther[] = {
    { "Z", "Z", CM }, { "z", "Z", CM }, { "z", "Z", CM | SH }, { "Z", "Z", CM | SH },
    { "z", "z", CM | SH }, { "Z", "z", CM | SH }, { "z", "z", CM }, { "z", "", CM },
};
static const Ev symbolsSynthetic[] = {
    { "[", "[", CM }, { "{", "[", CM | SH }, { "{", "{", CM | SH }, { "[", "[", CM | SH },
    { "1", "1", CM }, { "!", "1", CM | SH }, { "!", "!", CM | SH }, { "1", "1", CM | SH },
    { "=", "=", CM }, { "+", "=", CM | SH }, { "+", "+", CM | SH },
};
static const Ev symbolsReal[] = {
    { "[", "[", CM }, { "[", "{", CM | SH }, { "1", "1", CM }, { "1", "!", CM | SH },
    { "=", "=", CM }, { "=", "+", CM | SH },
};

// A button takes the same events: key "b" or "B" with Command, performed for these events (1) or not (0).
static void checkButton(NSString *key, const int *expected) {
    static const Ev events[] = {
        { "b", "b", CM }, { "b", "B", CM | SH }, { "b", "b", CM | CL }, { "b", "b", 0 }, { "B", "B", SH },
    };
    for (int i = 0; i < 5; i++) {
        NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 24)];
        [button setTarget: target];
        [button setAction: @selector(fire:)];
        [button setKeyEquivalent: key];
        [button setKeyEquivalentModifierMask: CM];
        target->count = 0;
        BOOL handled = [button performKeyEquivalent: makeEvent(events[i])];
        if (handled != expected[i] || target->count != expected[i]) {
            printf("FAIL button key %s event %d: handled %d count %d expected %d\n", [key UTF8String], i,
                   handled, target->count, expected[i]);
            failures++;
        }
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        target = [[Target alloc] init];

        checkTable(ZSYN, zSynthetic, 10, "letters, hand-made events", YES);
        checkTable(ZREAL, zReal, 10, "letters, events made from key codes", NO);
        checkTable(XSYN, zOther, 8, "letters, other shapes", NO);
        checkTable(SSYN, symbolsSynthetic, 11, "symbols and digits, hand-made events", NO);
        checkTable(SREAL, symbolsReal, 6, "symbols and digits, events made from key codes", NO);
        {
            const int lower[] = { 1, 0, 1, 0, 0 };
            const int upper[] = { 0, 1, 0, 0, 0 };
            checkButton(@"b", lower);
            checkButton(@"B", upper);
        }
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
