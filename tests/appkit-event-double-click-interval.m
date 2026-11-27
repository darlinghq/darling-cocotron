// Copyright (C) 2026 Lubos Dolezel
//
// +[NSEvent doubleClickInterval] is the user's double-click interval in seconds (a public NSEvent class
// property since macOS 10.6). Observed through the public API on macOS 26.7.3: 0.5 with the default
// settings. With the argument "preference" the test sets the double-click threshold of the global domain
// (com.apple.mouse.doubleClickThreshold, the setting the system's mouse pane writes) to 0.35 and checks
// that the property follows it, then removes the setting again; run that only in a Darling prefix.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTimeInterval interval = [NSEvent doubleClickInterval];
        printf("doubleClickInterval=%g\n", interval);
        expect(interval > 0 && interval <= 5, @"the interval is a positive, sensible number of seconds");
        if (argc > 1 && strcmp(argv[1], "preference") == 0) {
            double value = 0.35;
            CFNumberRef number = CFNumberCreate(NULL, kCFNumberDoubleType, &value);
            CFPreferencesSetValue(CFSTR("com.apple.mouse.doubleClickThreshold"), number, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFRelease(number);
            double now = [NSEvent doubleClickInterval];
            CFPreferencesSetValue(CFSTR("com.apple.mouse.doubleClickThreshold"), NULL, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            expect(now > 0.349 && now < 0.351, [NSString stringWithFormat: @"the interval follows the preference (%g)", now]);
        }
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
