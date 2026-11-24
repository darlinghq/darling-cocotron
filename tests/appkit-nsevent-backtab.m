// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The characters of an NSEvent made from a key CGEvent whose Unicode string is the tab character U+0009 (the
// layout's result for the Tab key): with Shift in the flags they are U+0019 (NSBackTabCharacter), as characters
// and as charactersIgnoringModifiers, whichever key it is; without Shift they are U+0009. This pins the observed
// behaviour of macOS 26.7.3 and 10.14.4 (a QUIRK, see NSEventQueue.m); the program passes there too.
// Usage: appkit-nsevent-backtab (no arguments, needs a window system)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

// The characters of the NSEvent made from a key event for the key, whose CGEvent carries the string `set`
static NSString *charactersOf(CGKeyCode key, CGEventFlags flags, int set, BOOL down, NSString **ignoring) {
    CGEventRef cgEvent = CGEventCreateKeyboardEvent(NULL, key, down);
    CGEventSetFlags(cgEvent, flags);
    UniChar c = (UniChar) set;
    CGEventKeyboardSetUnicodeString(cgEvent, 1, &c);
    NSEvent *event = [NSEvent eventWithCGEvent: cgEvent];
    CFRelease(cgEvent);
    if (ignoring)
        *ignoring = [event charactersIgnoringModifiers];
    return [event characters];
}

static BOOL is(NSString *s, unichar c) {
    return [s length] == 1 && [s characterAtIndex: 0] == c;
}

static void checkTab(const char *name, CGKeyCode key, CGEventFlags flags, int set, BOOL down, unichar want) {
    NSString *ignoring = nil;
    NSString *characters = charactersOf(key, flags, set, down, &ignoring);
    expect(is(characters, want) && is(ignoring, want),
           [NSString stringWithFormat: @"%s: characters and charactersIgnoringModifiers are U+%04X (got %@ / %@)", name, want, characters, ignoring]);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window makeKeyAndOrderFront: nil];
        [NSApp finishLaunching];
        CGEventFlags S = kCGEventFlagMaskShift;

        checkTab("Tab", kVK_Tab, 0, 0x09, YES, 0x09);
        checkTab("Shift+Tab", kVK_Tab, S, 0x09, YES, NSBackTabCharacter);
        checkTab("Shift+Command+Tab", kVK_Tab, S | kCGEventFlagMaskCommand, 0x09, YES, NSBackTabCharacter);
        checkTab("Shift+Control+Tab", kVK_Tab, S | kCGEventFlagMaskControl, 0x09, YES, NSBackTabCharacter);
        checkTab("Shift+Option+Tab", kVK_Tab, S | kCGEventFlagMaskAlternate, 0x09, YES, NSBackTabCharacter);
        checkTab("Shift+Tab key up", kVK_Tab, S, 0x09, NO, NSBackTabCharacter);
        checkTab("Control+Tab", kVK_Tab, kCGEventFlagMaskControl, 0x09, YES, 0x09);
        checkTab("Option+Tab", kVK_Tab, kCGEventFlagMaskAlternate, 0x09, YES, 0x09);
        checkTab("Command+Tab", kVK_Tab, kCGEventFlagMaskCommand, 0x09, YES, 0x09);
        checkTab("Caps Lock+Tab", kVK_Tab, kCGEventFlagMaskAlphaShift, 0x09, YES, 0x09);
        checkTab("Tab key up", kVK_Tab, 0, 0x09, NO, 0x09);
        checkTab("Tab with the string set to U+0019, no Shift", kVK_Tab, 0, 0x19, YES, NSBackTabCharacter);
        checkTab("Shift + the A key with the string U+0009", kVK_ANSI_A, S, 0x09, YES, NSBackTabCharacter);
        checkTab("Shift + the Escape key with the string U+0009", kVK_Escape, S, 0x09, YES, NSBackTabCharacter);
        checkTab("the A key with the string U+0009, no Shift", kVK_ANSI_A, 0, 0x09, YES, 0x09);
        checkTab("Shift+Return is not affected", kVK_Return, S, 0x0d, YES, 0x0d);
        checkTab("Shift+Escape is not affected", kVK_Escape, S, 0x1b, YES, 0x1b);
        [window close];
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
