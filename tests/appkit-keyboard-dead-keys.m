// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// Dead keys and compose sequences reach a text view as the text they make, the same on both backends. Driven by
// appkit-keyboard-dead-keys.py on the Wayland backend and on X11 (a private KWin and its Xwayland), which type
// with the layout "us" variant "intl" (the apostrophe, grave and shifted 6 keys are dead keys) and the Compose
// key on the right Alt key. The program prints READY, then reads events until the text view has every line or 25
// seconds have passed, and checks what the harness typed, each ending with Return:
//   e                          plain key: e
//   dead acute, e              the dead key and the key after it make one character: e acute
//   dead acute, space          the Compose table's text for it: an apostrophe
//   dead acute, q              no accented q exists, an invalid sequence: the accent and q are both committed
//   Compose, s, s              a compose sequence: the sharp s
//   Compose, z, q              an invalid compose sequence: the keys as typed
//   dead diaeresis, space      the Compose table's text: a quotation mark
//   dead diaeresis, e          e diaeresis
//   dead grave, space          a grave accent character
//   dead tilde, space          a tilde character
//   dead circumflex, space     a circumflex character
// The dead key and the Compose key are not delivered as key events of their own, nor are the keys that continue
// a sequence: the key that completes it has the text as its characters and its own key code. A dead key is not
// shown as marked text.
// What macOS does (black-box observation with UCKeyTranslate on the US International-PC layout, whose dead keys
// are the ones typed here; macOS 26.7.3 and 10.14.4, vd-upstream/mac-probes/dead-keys): a dead key followed by
// Space gives the layout's own character for the key (apostrophe, quotation mark, grave accent, tilde,
// circumflex), by an unrelated letter the same character and the letter, by a vowel it combines with the
// accented vowel. The Compose table gives the same texts. (Layouts whose dead keys are Option keys, such as
// the ABC layout, give the spacing accents U+00B4 and U+00A8; which of the two a layout gives is the layout's
// own data and there is no such data in a Linux keymap.)
// Usage: appkit-keyboard-dead-keys (no arguments; DARLING_APPKIT_BACKEND names the backend, which the driver sets)
// Prints INFO lines (what the text view was asked, in order), then PASS or FAIL lines, then ALL PASSED or
// FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSMutableArray *callLog;
static int failures, markedCalls, emptyKeyDowns, sharpSKeyCode = -1;

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
    if ([[event characters] isEqualToString: @"\u00df"])
        sharpSKeyCode = (int) [event keyCode];
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

        NSArray *expected = @[@"e", @"\u00e9", @"'", @"'q", @"\u00df", @"zq",
                              @"\"", @"\u00eb", @"`", @"~", @"^", @""];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 25];
        while ([deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
            if ([[[view string] componentsSeparatedByString: @"\n"] count] >= [expected count])
                break;
        }

        for (NSString *line in callLog)
            printf("INFO %s\n", [line UTF8String]);
        printf("INFO marked text calls: %d\n", markedCalls);

        NSArray *lines = [[view string] componentsSeparatedByString: @"\n"];
        NSArray *what = @[@"a plain key is its character",
                          @"dead acute and e make e acute",
                          @"dead acute and space make an apostrophe",
                          @"dead acute and q, an invalid sequence, make the accent and q",
                          @"the Compose key and s, s make the sharp s",
                          @"the keys of an invalid Compose sequence are typed as they are",
                          @"dead diaeresis and space make a quotation mark",
                          @"dead diaeresis and e make e diaeresis",
                          @"dead grave and space make a grave accent character",
                          @"dead tilde and space make a tilde character",
                          @"dead circumflex and space make a circumflex character",
                          @"nothing follows the last line"];
        expect([lines count] == [expected count], [NSString stringWithFormat: @"%d lines typed", (int) [expected count] - 1]);
        for (NSUInteger i = 0; i < [expected count]; i++) {
            NSString *got = i < [lines count] ? [lines objectAtIndex: i] : nil;
            BOOL ok = [got isEqualToString: [expected objectAtIndex: i]];
            expect(ok, [NSString stringWithFormat: @"%@ (got %@)", [what objectAtIndex: i], got]);
        }
        expect(sharpSKeyCode == 1, [NSString stringWithFormat: @"the sharp s is the key down of the S key, kVK_ANSI_S (got %d)", sharpSKeyCode]);
        expect(emptyKeyDowns == 0, @"a dead key or the Compose key is not delivered as a key event without characters");
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
