// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// The window system's input method (XIM on X11) composes text for the text input client of the key window's
// first responder through NSTextInputContext: setMarkedText:selectedRange:replacementRange: with the
// whole composition and the caret while it is composed, empty marked text when it is cancelled, and
// insertText:replacementRange: for the final text (on X11 the text arrives as the characters of a key
// event). The input method is also told where the client's caret is (the client's
// firstRectForCharacterRange:actualRange: in screen coordinates), so that it can place its candidate window
// there. Driven by appkit-x11-input-method.sh, which runs x11-test-xim-server.c as the input method
// (XMODIFIERS=@im=testxim for this program) and types with XTest:
//   a, b            the composition "a", then "ab", the caret at the end
//   BackSpace       "a"
//   b, Return       "ab", then the composition is replaced by the text "AB"
//   c, Escape       "c", then the composition is removed and nothing is inserted
//   2, Escape       the non-ASCII composition U+65E5 U+672C U+8A9E, caret after the first character, removed
//   3, Escape       a character outside the BMP and "a", caret at UTF-16 offset 2, removed
//   4               non-ASCII text committed
//   1               the end (the input method forwards digits)
// The program prints READY, then EXPECT SPOT <x> <y> (the input method's spot for the client's caret rectangle,
// in device pixels from the top left corner of the window, as the harness checks it in the input method's
// log), then runs until the key "1" comes up or 30 seconds have passed.
// Usage: appkit-x11-input-method (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static NSMutableArray *clientLog;
static BOOL quit;

@interface InputView : NSView <NSTextInputClient> {
@public
    NSString *marked;
    NSRect caretRect; // in window coordinates, y up
}
@end

@implementation InputView
- (BOOL) acceptsFirstResponder {
    return YES;
}
- (void) keyDown: (NSEvent *) event {
    [self interpretKeyEvents: @[ event ]];
}
- (void) insertText: (id) string replacementRange: (NSRange) range {
    NSString *plain = [string isKindOfClass: [NSAttributedString class]] ? [string string] : string;
    [clientLog addObject: [NSString stringWithFormat: @"insert:%@", plain]];
    marked = nil;
}
- (void) insertText: (id) string {
    [self insertText: string replacementRange: NSMakeRange(NSNotFound, 0)];
}
- (void) setMarkedText: (id) string selectedRange: (NSRange) selected replacementRange: (NSRange) range {
    NSString *plain = [string isKindOfClass: [NSAttributedString class]] ? [string string] : string;
    [clientLog addObject: [NSString stringWithFormat: @"mark:%@ sel=%lu,%lu", plain, (unsigned long) selected.location,
                           (unsigned long) selected.length]];
    marked = [plain length] > 0 ? [plain copy] : nil;
}
- (void) unmarkText {
    [clientLog addObject: @"unmark"];
    marked = nil;
}
- (BOOL) hasMarkedText {
    return marked != nil;
}
- (NSRange) markedRange {
    return marked != nil ? NSMakeRange(0, [marked length]) : NSMakeRange(NSNotFound, 0);
}
- (NSRange) selectedRange {
    return NSMakeRange(0, 0);
}
- (NSAttributedString *) attributedSubstringForProposedRange: (NSRange) range actualRange: (NSRangePointer) actual {
    return nil;
}
- (NSArray *) validAttributesForMarkedText {
    return @[];
}
- (NSRect) firstRectForCharacterRange: (NSRange) range actualRange: (NSRangePointer) actual {
    return [[self window] convertRectToScreen: caretRect];
}
- (NSUInteger) characterIndexForPoint: (NSPoint) point {
    return NSNotFound;
}
- (void) doCommandBySelector: (SEL) selector {
}
@end

@interface KeyApplication : NSApplication
@end

@implementation KeyApplication
- (void) sendEvent: (NSEvent *) event {
    if ([event type] == NSEventTypeKeyUp && [[event characters] isEqualToString: @"1"])
        quit = YES;
    [super sendEvent: event];
}
@end

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

int main(void) {
    @autoreleasepool {
        clientLog = [NSMutableArray new];
        KeyApplication *app = (KeyApplication *) [KeyApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        InputView *view = [[InputView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        view->caretRect = NSMakeRect(30, 150, 2, 16);
        [window setContentView: view];
        [window setTitle: @"xim-input-method"];
        [window makeKeyAndOrderFront: nil];
        [window makeFirstResponder: view];
        [app finishLaunching];
        printf("READY\n");
        // The bottom left corner of the caret rectangle, from the top left corner of the window (1 device pixel a point).
        printf("EXPECT SPOT %d %d\n", (int) NSMinX(view->caretRect), (int) ([window frame].size.height - NSMinY(view->caretRect)));
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 30];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
        }
        for (NSString *entry in clientLog)
            printf("  client: %s\n", [entry UTF8String]);

        NSString *joined = [clientLog componentsJoinedByString: @"|"];
        expect([joined hasPrefix: @"mark:a sel=1,0|mark:ab sel=2,0|mark:a sel=1,0|mark:ab sel=2,0|"],
               @"the client is sent the whole composition each time, with the caret at its end");
        expect([joined containsString: @"mark: sel=0,0|insert:AB|"],
               @"the committed text replaces the composition: the marked text is removed, then the text is inserted");
        expect([joined containsString: @"|mark:c sel=1,0|mark: sel=0,0|mark:\u65e5\u672c\u8a9e sel=1,0|mark: sel=0,0|"
                                       @"mark:\U0001F600" @"a sel=2,0|mark: sel=0,0|insert:\u65e5\u672c\u8a9e|insert:1"] && ![joined containsString: @"insert:c"] &&
               ![joined containsString: @"insert:C"],
               @"a cancelled composition removes the marked text and inserts nothing");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
