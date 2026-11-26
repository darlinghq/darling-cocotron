// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: NSKeyboardShortcut, AppKit's shortcut description class.
// Expected values were observed on macOS 26.7.3 (x86_64) with the same calls:
// modifiers are shown as Control, Option, Shift, Command, then "fn"; an
// upper-case key adds Shift; single characters are upper-cased and special
// keys have symbols or names (DEL is shown as forward delete); equality is on
// the key and the mask; a copy is the same object; a nil key raises.
#import <AppKit/AppKit.h>

@interface NSKeyboardShortcut : NSObject <NSCopying>
+ (instancetype)shortcutWithKeyEquivalent:(NSString *)keyEquivalent modifierMask:(NSUInteger)modifierMask;
@property (readonly) NSString *keyEquivalent;
@property (readonly) NSUInteger modifierMask;
@property (readonly, getter=isEmpty) BOOL empty;
@property (readonly) BOOL isFunctionKey;
@property (readonly) NSString *localizedDisplayName;
@property (readonly) NSString *localizedKeyEquivalentDisplayName;
@property (readonly) NSString *localizedModifierMaskDisplayName;
@end

static int failures;

static void report(NSString *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name.UTF8String);
    if (!ok)
        failures++;
}

static void display(NSString *key, NSUInteger mask, NSString *expected)
{
    NSString *shown = [NSKeyboardShortcut shortcutWithKeyEquivalent: key modifierMask: mask].localizedDisplayName;
    report([NSString stringWithFormat: @"display of U+%04X%@ mask %lx: %@", key.length ? [key characterAtIndex: 0] : 0,
            key.length > 1 ? @"..." : @"", (unsigned long) mask, expected], [shown isEqualToString: expected]);
}

int main(void)
{
    @autoreleasepool {
        const NSUInteger cmd = NSEventModifierFlagCommand, shift = NSEventModifierFlagShift, opt = NSEventModifierFlagOption,
                ctrl = NSEventModifierFlagControl, fn = NSEventModifierFlagFunction;
        display(@"k", cmd, @"⌘K");
        display(@"K", cmd, @"⇧⌘K");
        display(@"k", cmd | shift, @"⇧⌘K");
        display(@"k", cmd | opt | ctrl | shift, @"⌃⌥⇧⌘K");
        display(@"k", 0, @"K");
        display(@"k", fn, @"fn-K");
        display(@"k", fn | cmd | shift, @"⇧⌘-fn-K");
        display(@"k", NSEventModifierFlagCapsLock, @"K");
        display(@"", cmd, @"⌘↑");
        display(@"", cmd, @"⌘↓");
        display(@"", 0, @"←");
        display(@"", 0, @"→");
        display(@" ", ctrl, @"⌃Space");
        display(@"\r", 0, @"↩");
        display(@"\n", 0, @"↩");
        display(@"\x03", 0, @"⌤");
        display(@"\t", opt, @"⌥⇥");
        display(@"\x19", 0, @"⇥");
        display(@"\x1b", 0, @"⎋");
        display(@"\x08", 0, @"⌫");
        display(@"\x7f", cmd, @"⌘⌦");
        display(@"", 0, @"⌦");
        display(@"", 0, @"↖");
        display(@"", 0, @"↘");
        display(@"", 0, @"⇞");
        display(@"", 0, @"⇟");
        display(@"", 0, @"ClrLn");
        display(@"", 0, @"Help");
        display(@"", 0, @"F1");
        display(@"", 0, @"F12");
        display(@"", ctrl | opt, @"⌃⌥F1");
        display(@"1", cmd, @"⌘1");
        display(@",", cmd, @"⌘,");
        display(@"/", cmd | shift, @"⇧⌘/");
        display(@"é", cmd, @"⌘É");
        display(@"ab", cmd, @"⌘ab");
        display(@"", cmd, @"");

        NSKeyboardShortcut *shortcut = [NSKeyboardShortcut shortcutWithKeyEquivalent: @"K" modifierMask: cmd];
        report(@"key and mask kept as given", [shortcut.keyEquivalent isEqualToString: @"K"] && shortcut.modifierMask == cmd);
        report(@"parts", [shortcut.localizedKeyEquivalentDisplayName isEqualToString: @"K"]
               && [shortcut.localizedModifierMaskDisplayName isEqualToString: @"⇧⌘"]);
        report(@"empty", [NSKeyboardShortcut shortcutWithKeyEquivalent: @"" modifierMask: 0].isEmpty && !shortcut.isEmpty);
        report(@"function keys", [NSKeyboardShortcut shortcutWithKeyEquivalent: @"" modifierMask: 0].isFunctionKey
               && ![NSKeyboardShortcut shortcutWithKeyEquivalent: @"" modifierMask: 0].isFunctionKey && !shortcut.isFunctionKey);
        NSKeyboardShortcut *same = [NSKeyboardShortcut shortcutWithKeyEquivalent: @"K" modifierMask: cmd];
        report(@"equal", [shortcut isEqual: same] && shortcut.hash == same.hash);
        report(@"upper-case key is not lower-case key with Shift",
               ![[NSKeyboardShortcut shortcutWithKeyEquivalent: @"K" modifierMask: 0] isEqual: [NSKeyboardShortcut shortcutWithKeyEquivalent: @"k" modifierMask: shift]]);
        report(@"copy is the same object", [[shortcut copy] autorelease] == shortcut);
        report(@"description", [shortcut.description hasSuffix: @" (⇧⌘K)>"] && [shortcut.description hasPrefix: @"<NSKeyboardShortcut: "]);
        BOOL raised = NO;
        @try {
            [NSKeyboardShortcut shortcutWithKeyEquivalent: nil modifierMask: cmd];
        } @catch (NSException *exception) {
            raised = [exception.name isEqualToString: NSInternalInconsistencyException];
        }
        report(@"nil key raises", raised);
    }
    return failures != 0;
}
