/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSInputManager, the input method API AppKit replaced with
 * NSTextInputContext in macOS 10.6, as observed on macOS 26.7.3: there is no
 * current input manager, so messages for it go to nil. The class still
 * declares the methods text views send it.
 * No window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        expect([NSInputManager currentInputManager] == nil, "there is no current input manager");
        expect([NSInputManager instancesRespondToSelector: @selector(markedTextAbandoned:)], "markedTextAbandoned:");
        expect([NSInputManager instancesRespondToSelector: @selector(markedTextSelectionChanged:client:)],
               "markedTextSelectionChanged:client:");
        expect([NSInputManager instancesRespondToSelector: @selector(wantsToHandleMouseEvents)], "wantsToHandleMouseEvents");
        expect([NSInputManager instancesRespondToSelector: @selector(handleMouseEvent:)], "handleMouseEvent:");
    }

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
