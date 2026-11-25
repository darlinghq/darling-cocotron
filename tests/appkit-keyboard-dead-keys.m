// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// Dead keys and compose sequences reach a text view as the text they make. Driven by
// appkit-keyboard-dead-keys.py on the Wayland backend and on X11 (a private KWin and its Xwayland), which type
// with the layout "us" variant "intl" (the apostrophe key is the dead acute accent) and the Compose key on the
// right Alt key. The program prints READY, then reads events until the text view has six lines or 25 seconds
// have passed, and checks what the harness typed, each ending with Return:
//   e                          plain key: e
//   dead acute, e              the dead key and the key after it make one character: e acute
//   dead acute, space          the Compose table's text for it: an apostrophe (the table of the C locale; macOS
//                              makes the spacing acute U+00B4 here)
//   dead acute, q              no accented q exists, an invalid sequence: macOS commits both the accent and q
//   Compose, s, s              a compose sequence: the sharp s
//   Compose, z, q              an invalid compose sequence
// The dead key and the Compose key are not delivered as key events of their own, nor are the keys that continue
// a sequence: the key that completes it has the text as its characters. A dead key is not shown as marked text.
// An invalid sequence is where the backends differ: Wayland commits the characters typed (the macOS result for a
// dead key), while Xlib's compose handling on X11 drops the whole sequence.
// Usage: appkit-keyboard-dead-keys (no arguments; DARLING_APPKIT_BACKEND names the backend, which the driver sets)
// Prints INFO lines (what the text view was asked, in order), then PASS or FAIL lines, then ALL PASSED or
// FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSMutableArray *callLog;
static int failures, markedCalls, emptyKeyDowns;

static void expect(BOOL condition, NSString *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", [what UTF8String]);
    if (!condition)
        failures++;
}

@interface LoggingTextView : NSTextView
@end

@implementation LoggingTextView
- (void) keyDown: (NSEvent *) event {
    if ([[event characters] length] == 0)
        emptyKeyDowns++;
    [callLog addObject: [NSString stringWithFormat: @"keyDown %@ (key %d)", [event characters], (int) [event keyCode]]];
    [super keyDown: event];
}
- (void) insertText: (id) string replacementRange: (NSRange) range {
    [callLog addObject: [NSString stringWithFormat: @"insertText %@", string]];
    [super insertText: string replacementRange: range];
}
- (void) setMarkedText: (id) string selectedRange: (NSRange) selected replacementRange: (NSRange) range {
    markedCalls++;
    NSString *plain = [string isKindOfClass: [NSAttributedString class]] ? [string string] : string;
    [callLog addObject: [NSString stringWithFormat: @"setMarkedText %@", plain]];
    [super setMarkedText: string selectedRange: selected replacementRange: range];
}
@end

int main(void) {
    @autoreleasepool {
        callLog = [[NSMutableArray alloc] init];
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"dead-keys"];
        LoggingTextView *view = [[LoggingTextView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        [view setEditable: YES];
        [window setContentView: view];
        [window makeKeyAndOrderFront: nil];
        [window makeFirstResponder: view];
        [app finishLaunching];
        [app activateIgnoringOtherApps: YES];
        printf("READY\n");
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 25];
        while ([deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
            if ([[[view string] componentsSeparatedByString: @"\n"] count] > 6)
                break;
        }

        for (NSString *line in callLog)
            printf("INFO %s\n", [line UTF8String]);
        printf("INFO marked text calls: %d\n", markedCalls);

        NSArray *lines = [[view string] componentsSeparatedByString: @"\n"];
        const char *backend = getenv("DARLING_APPKIT_BACKEND");
        BOOL x11 = backend != NULL && strcmp(backend, "x11") == 0;
        NSArray *expected = x11 ? @[@"e", @"é", @"'", @"", @"ß", @"", @""]
                                : @[@"e", @"é", @"'", @"'q", @"ß", @"zq", @""];
        NSArray *what = @[@"a plain key is its character",
                          @"dead acute and e make e acute",
                          @"dead acute and space make the Compose table's text",
                          @"dead acute and q, an invalid sequence, make what the backend does with it",
                          @"the Compose key and s, s make the sharp s",
                          @"an invalid Compose sequence makes what the backend does with it",
                          @"nothing follows the last line"];
        expect([lines count] == [expected count], [NSString stringWithFormat: @"%d lines typed", (int) [expected count] - 1]);
        for (NSUInteger i = 0; i < [expected count]; i++) {
            NSString *got = i < [lines count] ? [lines objectAtIndex: i] : nil;
            BOOL ok = [got isEqualToString: [expected objectAtIndex: i]];
            expect(ok, [NSString stringWithFormat: @"%@ (got %@)", [what objectAtIndex: i], got]);
        }
        expect(emptyKeyDowns == 0, @"a dead key or the Compose key is not delivered as a key event without characters");
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
