// Copyright (C) 2026 Lubos Dolezel
//
// -[NSApplication isFullKeyboardAccessEnabled] (documented as whether the user turned on full keyboard access) follows
// the AppleKeyboardUIMode global default that the Keyboard pane of System Preferences writes: off for 0 and when
// the key is not set, on for 2 and 3, also when `defaults write` stored it as a string.
// test_quirk_keyboard_ui_mode: the meaning of the values is not documented (see the QUIRK comment in NSApplication.m).
// Build: clang -framework AppKit appkit-full-keyboard-access.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void set_mode(id value) {
    CFPreferencesSetValue(CFSTR("AppleKeyboardUIMode"), (__bridge CFPropertyListRef) value, kCFPreferencesAnyApplication,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        set_mode(nil);
        CHECK(![NSApp isFullKeyboardAccessEnabled]);
        // test_quirk_keyboard_ui_mode
        set_mode(@3);
        CHECK([NSApp isFullKeyboardAccessEnabled]);
        set_mode(@2);
        CHECK([NSApp isFullKeyboardAccessEnabled]);
        set_mode(@0);
        CHECK(![NSApp isFullKeyboardAccessEnabled]);
        set_mode(@"3");
        CHECK([NSApp isFullKeyboardAccessEnabled]);
        set_mode(@"0");
        CHECK(![NSApp isFullKeyboardAccessEnabled]);
        set_mode(nil);
    }
    puts(failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
