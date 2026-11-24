// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// What an X input method (XIM) does to the keys reaches the application as before the keyboard moved to
// CoreGraphics: the input method sees every key first, takes the ones it composes (the keys of a compose
// sequence do not reach the application as keys), and the text of the keys it forwards is what the input
// context of the window composes (CoreGraphics asks AppKit's input context for it): the characters of the key
// CGEvent the event taps see, and the NSEvent's characters, which end in insertText: on the first
// responder's NSTextInputClient. Driven by appkit-x11-xim-composed-text.sh, which runs a private fcitx5 as the
// input method (XMODIFIERS=@im=fcitx for this program) and types with XTest:
//   dead_acute, space  a compose sequence: the input method consumes both keys
//   b                  an ordinary key, which the input method forwards
//   q                  the end
// The text the input method commits for the sequence (the apostrophe) is only reported: the X libraries of
// a Darling process run in the C locale, in which Xlib drops committed text, so it is not delivered (that
// is not a change of this test's subject, and it is the same as it was when AppKit decoded the keys).
// The program prints READY, then runs until the key "q" comes up or 30 seconds have passed.
// Usage: appkit-x11-xim-composed-text (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

typedef struct {
    int seq;
    CGEventType type;
    int keyCode;
    unichar chars[4];
    int length;
    int autorepeat;
} Seen;

static Seen tapSeen[256], nsSeen[256];
static int tapCount, nsCount, sequence;
static NSMutableArray *inserted;
static int markedUpdates;
static BOOL quit;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if ((type != kCGEventKeyDown && type != kCGEventKeyUp) || tapCount >= 256)
        return event;
    Seen *seen = &tapSeen[tapCount++];
    seen->seq = ++sequence;
    seen->type = type;
    seen->keyCode = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    UniCharCount length = 0;
    CGEventKeyboardGetUnicodeString(event, 4, &length, seen->chars);
    seen->length = (int) length;
    seen->autorepeat = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat);
    return event;
}

@interface InputView : NSView <NSTextInputClient>
@end

@implementation InputView
- (BOOL) acceptsFirstResponder {
    return YES;
}
- (void) keyDown: (NSEvent *) event {
    [self interpretKeyEvents: @[ event ]];
}
- (void) insertText: (id) string replacementRange: (NSRange) range {
    [inserted addObject: [string isKindOfClass: [NSAttributedString class]] ? [string string] : string];
}
- (void) insertText: (id) string {
    [self insertText: string replacementRange: NSMakeRange(NSNotFound, 0)];
}
- (void) setMarkedText: (id) string selectedRange: (NSRange) selected replacementRange: (NSRange) range {
    markedUpdates++;
}
- (void) unmarkText {
}
- (BOOL) hasMarkedText {
    return NO;
}
- (NSRange) markedRange {
    return NSMakeRange(NSNotFound, 0);
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
    return NSMakeRect(100, 100, 10, 10);
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
    NSEventType type = [event type];
    if ((type == NSEventTypeKeyDown || type == NSEventTypeKeyUp) && nsCount < 256) {
        Seen *seen = &nsSeen[nsCount++];
        seen->seq = ++sequence;
        seen->type = (CGEventType) type;
        seen->keyCode = [event keyCode];
        NSString *characters = [event characters];
        seen->length = (int) MIN([characters length], 4);
        [characters getCharacters: seen->chars range: NSMakeRange(0, seen->length)];
        seen->autorepeat = [event isARepeat];
        if (type == NSEventTypeKeyUp && seen->length == 1 && seen->chars[0] == 'q')
            quit = YES;
    }
    [super sendEvent: event];
}
@end

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

static int findKey(Seen *list, int count, int from, CGEventType type, unichar c) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (list[i].type == type && list[i].length == 1 && list[i].chars[0] == c)
            return i;
    }
    return -1;
}

static BOOL anyKeyDown(int keyCode) {
    for (int i = 0; i < tapCount; i++) {
        if (tapSeen[i].type == kCGEventKeyDown && tapSeen[i].keyCode == keyCode)
            return YES;
    }
    return NO;
}

int main(void) {
    @autoreleasepool {
        inserted = [NSMutableArray new];
        KeyApplication *app = (KeyApplication *) [KeyApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp), tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        InputView *view = [[InputView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        [window setContentView: view];
        [window setTitle: @"xim-composed"];
        [window makeKeyAndOrderFront: nil];
        [window makeFirstResponder: view];
        [app finishLaunching];
        printf("READY\n");
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
        printf("tap events %d, NSEvents %d, inserted %lu, marked text updates %d\n", tapCount, nsCount, (unsigned long) [inserted count],
               markedUpdates);
        for (int i = 0; i < tapCount; i++)
            printf("  tap %3d: type %d key %3d chars %#x/%d repeat %d\n", tapSeen[i].seq, (int) tapSeen[i].type, tapSeen[i].keyCode,
                   tapSeen[i].chars[0], tapSeen[i].length, tapSeen[i].autorepeat);
        for (int i = 0; i < nsCount; i++)
            printf("  ns  %3d: type %d key %3d chars %#x/%d repeat %d\n", nsSeen[i].seq, (int) nsSeen[i].type, nsSeen[i].keyCode,
                   nsSeen[i].chars[0], nsSeen[i].length, nsSeen[i].autorepeat);
        for (NSString *string in inserted)
            printf("  insertText: %s\n", [string UTF8String]);

        expect(!anyKeyDown(kVK_Space), @"the input method consumed the dead key and the space: no key down for the space");
        int composed = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, '\'');
        printf("INFO the committed text of the compose sequence %s\n", composed >= 0 ? "arrived" : "did not arrive (C locale)");
        int b = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, 'b');
        expect(b >= 0 && tapSeen[b].keyCode == kVK_ANSI_B && tapSeen[b].autorepeat == 0,
               @"the key b, forwarded by the input method: the tap sees it with its key code and characters");
        int nsB = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, 'b');
        expect(nsB >= 0 && b >= 0 && tapSeen[b].seq < nsSeen[nsB].seq, @"AppKit's key down has the same characters, and the tap saw it first");
        expect([inserted count] >= 1 && [inserted containsObject: @"b"],
               @"the text reaches the first responder's NSTextInputClient as insertText:");
        int up = findKey(tapSeen, tapCount, b + 1, kCGEventKeyUp, 'b');
        expect(b >= 0 && up >= 0, @"and the key b comes up once");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
