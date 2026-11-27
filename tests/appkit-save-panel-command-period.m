// Copyright (C) 2026 Lubos Dolezel
//
// Command-period cancels an NSSavePanel. The Human Interface Guidelines for macOS give Command-period as the
// keyboard equivalent of cancelling a dialog (Escape being the other), and the panel's
// -performKeyEquivalent: (https://developer.apple.com/documentation/appkit/nswindow/performkeyequivalent(with:))
// returns YES for a key it handled. A panel shown with -beginWithCompletionHandler: that is handed
// Command-period dismisses itself and reports NSModalResponseCancel. Other Command combinations with a period
// (Control or Option added) are not the cancel key. Not run on macOS, where the panel is a remote one (the
// behaviour is the platform's own there).
// Build: clang -framework AppKit appkit-save-panel-command-period.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSEvent *periodEvent(NSWindow *window, NSUInteger flags) {
    return [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: flags timestamp: 0
                        windowNumber: [window windowNumber] context: nil characters: @"."
         charactersIgnoringModifiers: @"." isARepeat: NO keyCode: 47];
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSSavePanel *panel = [NSSavePanel savePanel];
    __block NSInteger result = -1;
    [panel beginWithCompletionHandler: ^(NSInteger r) { result = r; }];
    spin(0.5);
    CHECK(result == -1);

    CHECK(![panel performKeyEquivalent: periodEvent(panel, NSCommandKeyMask | NSControlKeyMask)]);
    CHECK(![panel performKeyEquivalent: periodEvent(panel, NSCommandKeyMask | NSAlternateKeyMask)]);
    spin(0.2);
    CHECK(result == -1);

    CHECK([panel performKeyEquivalent: periodEvent(panel, NSCommandKeyMask)]);
    spin(0.5);
    CHECK(result == NSModalResponseCancel);

    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
