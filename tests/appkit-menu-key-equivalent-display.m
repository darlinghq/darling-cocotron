// Copyright (C) 2026 Lubos Dolezel
//
// The key equivalent a menu item shows is written the way it is typed on this system. Command arrives from the Super
// key, so it shows as the Command symbol; modifiers use the macOS symbols in the macOS order (Control, Option, Shift,
// Command); the keys that have no printable character (Tab, Return, Escape, Delete, arrows, Home, End, Page Up and
// Down, function keys) show with the symbols macOS uses. With ControlKeyActsAsCommand set (org.darlinghq.AppKit,
// X11 backend), Control+C, V and X are the Command shortcuts, so those show as Ctrl+C, Ctrl+V and Ctrl+X, and
// every other shortcut is unchanged. Run with the argument "ctrl" for the second mode.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;

@interface NSMenuItem (KeyEquivalentDisplay)
- (NSString *) _keyEquivalentDescription;
@end

static void checkShown(NSString *key, NSUInteger mask, NSString *expected) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"x" action: NULL keyEquivalent: key];
    [item setKeyEquivalentModifierMask: mask];
    NSString *shown = [item _keyEquivalentDescription];
    if (![shown isEqualToString: expected]) {
        fprintf(stderr, "FAIL key %s mask %lx: shown '%s', expected '%s'\n", [[key description] UTF8String],
                (unsigned long) mask, [shown UTF8String], [expected UTF8String]);
        failures++;
    }
}

#define CMD NSEventModifierFlagCommand
#define OPT NSEventModifierFlagOption
#define SHIFT NSEventModifierFlagShift
#define CTRL NSEventModifierFlagControl

static NSString *ch(unichar c) {
    return [NSString stringWithCharacters: &c length: 1];
}

@interface Target : NSObject {
@public
    NSMutableArray *fired;
}
- (void) hit: (id) sender;
@end

@implementation Target
- (void) hit: (id) sender { [fired addObject: [sender title]]; }
@end

// What is shown must work: a key press with the shown modifiers triggers the item.
static void checkShownShortcutsFire(void) {
    Target *target = [Target new];
    target->fired = [NSMutableArray array];
    NSMenu *bar = [NSMenu new], *file = [[NSMenu alloc] initWithTitle: @"File"];
    NSMenuItem *top = [NSMenuItem new];
    struct { NSString *title; NSString *key; NSUInteger mask; } items[] = {
        {@"cmd-o", @"o", CMD}, {@"ctrl-k", @"k", CTRL}, {@"cmd-opt-o", @"p", CMD | OPT},
        {@"cmd-tab", @"\t", CMD}, {@"ctrl-cmd-j", @"j", CTRL | CMD},
    };
    for (size_t i = 0; i < sizeof(items) / sizeof(items[0]); i++) {
        NSMenuItem *item = [file addItemWithTitle: items[i].title action: @selector(hit:) keyEquivalent: items[i].key];
        [item setKeyEquivalentModifierMask: items[i].mask];
        [item setTarget: target];
    }
    [bar addItem: top];
    [top setSubmenu: file];
    [NSApp setMainMenu: bar];

    struct { NSUInteger flags; NSString *chars, *plain, *expect; } presses[] = {
        {CMD, @"o", @"o", @"cmd-o"},
        {CTRL, @"\x0b", @"k", @"ctrl-k"},   // a control chord's characters are a control code
        {CMD | OPT, @"p", @"p", @"cmd-opt-o"},
        {CMD, @"\t", @"\t", @"cmd-tab"},
        {CTRL | CMD, @"j", @"j", @"ctrl-cmd-j"},
    };
    for (size_t i = 0; i < sizeof(presses) / sizeof(presses[0]); i++) {
        [target->fired removeAllObjects];
        NSEvent *event = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint
                                     modifierFlags: presses[i].flags timestamp: 0 windowNumber: 0 context: nil
                                        characters: presses[i].chars
                       charactersIgnoringModifiers: presses[i].plain isARepeat: NO keyCode: 0];
        [NSApp sendEvent: event];
        if (![target->fired isEqual: @[presses[i].expect]]) {
            fprintf(stderr, "FAIL: the shortcut of %s did not fire it\n", [presses[i].expect UTF8String]);
            failures++;
        }
    }
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        BOOL ctrlMode = argc > 1 && strcmp(argv[1], "ctrl") == 0;
        if (ctrlMode)
            CFPreferencesSetAppValue(CFSTR("ControlKeyActsAsCommand"), kCFBooleanTrue,
                                     CFSTR("org.darlinghq.AppKit"));
        [NSApplication sharedApplication];

        // Command is shown as the Command symbol.
        checkShown(@"o", CMD, @"⌘O");
        checkShown(@"w", CMD, @"⌘W");
        checkShown(@"o", CMD | OPT, @"⌥⌘O");
        checkShown(@"a", CTRL | OPT | SHIFT | CMD, @"⌃⌥⇧⌘A");
        checkShown(@"A", CMD, @"⇧⌘A");   // an upper-case key implies Shift
        checkShown(@"s", CMD | SHIFT, @"⇧⌘S");
        checkShown(@"a", CTRL, @"⌃A");
        checkShown(@"a", OPT, @"⌥A");
        checkShown(@"a", 0, @"A");
        checkShown(@"1", CMD, @"⌘1");

        // keys without a printable character
        checkShown(ch('\t'), CMD, @"⌘⇥");
        checkShown(ch('\r'), CMD, @"⌘↩");
        checkShown(ch(0x1b), CMD, @"⌘⎋");
        checkShown(ch(0x7f), CMD, @"⌘⌫");
        checkShown(ch(0x08), CMD, @"⌘⌫");
        checkShown(ch(NSDeleteFunctionKey), CMD, @"⌘⌦");
        checkShown(ch(NSUpArrowFunctionKey), CMD, @"⌘↑");
        checkShown(ch(NSDownArrowFunctionKey), CMD, @"⌘↓");
        checkShown(ch(NSLeftArrowFunctionKey), CMD | SHIFT, @"⇧⌘←");
        checkShown(ch(NSRightArrowFunctionKey), CMD, @"⌘→");
        checkShown(ch(NSHomeFunctionKey), 0, @"↖");
        checkShown(ch(NSEndFunctionKey), 0, @"↘");
        checkShown(ch(NSPageUpFunctionKey), 0, @"⇞");
        checkShown(ch(NSPageDownFunctionKey), 0, @"⇟");
        checkShown(ch(NSF5FunctionKey), 0, @"F5");
        checkShown(@" ", CMD, @"⌘Space");
        checkShown(@"", CMD, @"");

        checkShownShortcutsFire();

        id display = [NSClassFromString(@"NSDisplay") performSelector: NSSelectorFromString(@"currentDisplay")];
        BOOL x11 = [NSStringFromClass([display class]) hasPrefix: @"X11"];
        if (!ctrlMode || x11) {
            checkShown(@"c", CMD, ctrlMode ? @"Ctrl+C" : @"\u2318C");
            checkShown(@"v", CMD, ctrlMode ? @"Ctrl+V" : @"\u2318V");
            checkShown(@"x", CMD, ctrlMode ? @"Ctrl+X" : @"\u2318X");
            checkShown(@"C", CMD, ctrlMode ? @"Ctrl+Shift+C" : @"\u21E7\u2318C");
            checkShown(@"c", CMD | SHIFT, ctrlMode ? @"Ctrl+Shift+C" : @"\u21E7\u2318C");
            // others are unchanged: another key, Option, a real Control
            checkShown(@"o", CMD, @"\u2318O");
            checkShown(@"c", CMD | OPT, @"\u2325\u2318C");
            checkShown(@"c", CMD | CTRL, @"\u2303\u2318C");
            checkShown(@"c", CTRL, @"\u2303C");
        } else {
            printf("SKIP ctrl mode: the display is not X11\n");
        }
    }
    CFPreferencesSetAppValue(CFSTR("ControlKeyActsAsCommand"), NULL, CFSTR("org.darlinghq.AppKit"));
    if (failures)
        printf("FAIL menu-key-equivalent-display (%d)\n", failures);
    else
        printf("PASS menu-key-equivalent-display\n");
    return failures != 0;
}
