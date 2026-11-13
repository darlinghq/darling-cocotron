/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Cooperative activation calls (macOS 14): yielding activation accepts any
// argument and returns at once, and -[NSRunningApplication
// activateFromApplication:options:] refuses a missing source application, as
// observed on macOS, and does not block.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRunningApplication *me = [NSRunningApplication currentApplication];

        expect([NSApp respondsToSelector: @selector(yieldActivationToApplication:)],
               "NSApplication responds to yieldActivationToApplication:");
        expect([NSApp respondsToSelector:
                              @selector(yieldActivationToApplicationWithBundleIdentifier:)],
               "NSApplication responds to yieldActivationToApplicationWithBundleIdentifier:");
        expect([me respondsToSelector: @selector(activateFromApplication:options:)],
               "NSRunningApplication responds to activateFromApplication:options:");

        // None of these raises or blocks.
        BOOL raised = NO;
        @try {
            [NSApp yieldActivationToApplication: me];
            [NSApp yieldActivationToApplication: nil];
            [NSApp yieldActivationToApplicationWithBundleIdentifier: @"org.example.no-such-app"];
            [NSApp yieldActivationToApplicationWithBundleIdentifier: nil];
        } @catch (NSException *e) {
            raised = YES;
        }
        expect(!raised, "yielding activation does not raise");

        expect(![me activateFromApplication: nil options: 0],
               "activateFromApplication: with no source application returns NO");

        raised = NO;
        @try {
            (void) [me activateFromApplication: me options: 0];
            (void) [me activateFromApplication: me options: NSApplicationActivateAllWindows];
        } @catch (NSException *e) {
            raised = YES;
        }
        expect(!raised, "activateFromApplication: returns without raising");

        // The call after yielding behaves the same as without.
        [NSApp yieldActivationToApplication: me];
        [NSApp activate];
    }

    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
