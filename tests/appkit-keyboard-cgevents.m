// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The keyboard of the window system reaches AppKit as CGEvents: the event taps of the process see
// the key, flags changed and key repeat events the window system's keyboard makes (with the characters,
// the key code, the modifier flags and the autorepeat field), the state functions of CGEventSource
// follow them, and the NSEvents AppKit makes are made from the CGEvents the taps passed on, so that a
// tap that changes a key changes what the application gets. Driven by appkit-keyboard-cgevents-wayland.sh
// (a virtual keyboard, wtype): the program prints READY, then reads events until it sees the key "q" come
// up or 25 seconds have passed, and checks what the harness typed, in this order:
//   a                          plain key
//   Shift + a                  a modifier key, then the key with the modifier in effect
//   Control + a                control character, characters ignoring the modifiers
//   s held for a second        key repeat
//   d                          the tap turns it into e
//   Shift + Tab                the NSEvent's characters are U+0019 (NSBackTabCharacter), see appkit-nsevent-backtab
//   q                          the end
// Usage: appkit-keyboard-cgevents (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int seq;
    CGEventType type;
    int keyCode;
    uint64_t flags;
    unichar chars[2];
    int length;
    int autorepeat;
    BOOL keyStateDown;
    uint64_t hidFlagsState;
} Seen;

static Seen tapSeen[256], nsSeen[256];
static int tapCount, nsCount, sequence;
static BOOL nsHasWindow = YES, nsCGEventMatches = YES, quit;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type != kCGEventKeyDown && type != kCGEventKeyUp && type != kCGEventFlagsChanged)
        return event;

    // The turned key: d becomes e
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        UniChar chars[4];
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 4, &length, chars);
        if (length == 1 && chars[0] == 'd') {
            UniChar e = 'e';
            CGEventKeyboardSetUnicodeString(event, 1, &e);
            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, kVK_ANSI_E);
        }
    }

    if (tapCount < 256) {
        Seen *seen = &tapSeen[tapCount++];
        seen->seq = ++sequence;
        seen->type = type;
        seen->keyCode = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        seen->flags = CGEventGetFlags(event);
        UniCharCount length = 0;
        if (type != kCGEventFlagsChanged) {
            CGEventKeyboardGetUnicodeString(event, 2, &length, seen->chars);
        }
        seen->length = (int) length;
        seen->autorepeat = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat);
        seen->keyStateDown = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, (CGKeyCode) seen->keyCode);
        seen->hidFlagsState = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);
    }
    return event;
}

@interface KeyApplication : NSApplication
@end

@implementation KeyApplication
- (void) sendEvent: (NSEvent *) event {
    NSEventType type = [event type];
    if ((type == NSEventTypeKeyDown || type == NSEventTypeKeyUp || type == NSEventTypeFlagsChanged) && nsCount < 256) {
        Seen *seen = &nsSeen[nsCount++];
        seen->seq = ++sequence;
        seen->type = (CGEventType) type;
        seen->keyCode = [event keyCode];
        seen->flags = [event modifierFlags];
        if (type != NSEventTypeFlagsChanged) {
            NSString *characters = [event characters];
            seen->length = (int) MIN([characters length], 2);
            [characters getCharacters: seen->chars range: NSMakeRange(0, seen->length)];
            NSString *unmodified = [event charactersIgnoringModifiers];
            seen->hidFlagsState = [unmodified length] > 0 ? [unmodified characterAtIndex: 0] : 0;
            seen->autorepeat = [event isARepeat];
            if (type == NSEventTypeKeyUp && seen->length > 0 && seen->chars[0] == 'q')
                quit = YES;
        }
        if ([event window] == nil)
            nsHasWindow = NO;
        CGEventRef cgEvent = [event CGEvent];
        if (cgEvent == NULL || (int) CGEventGetIntegerValueField(cgEvent, kCGKeyboardEventKeycode) != seen->keyCode)
            nsCGEventMatches = NO;
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

static BOOL hasChar(Seen *seen, unichar c) {
    return seen->length == 1 && seen->chars[0] == c;
}

// The index of the first key event of the type after `from` that has the character, or -1
static int findKey(Seen *list, int count, int from, CGEventType type, unichar c) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (list[i].type == type && hasChar(&list[i], c))
            return i;
    }
    return -1;
}

// The index of the first key event of the type after `from` that has the letter in either case, or -1
static int findLetter(Seen *list, int count, int from, CGEventType type, unichar lower) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (list[i].type == type && (hasChar(&list[i], lower) || hasChar(&list[i], lower - 'a' + 'A')))
            return i;
    }
    return -1;
}

// The first flags changed event after `from` with the flag set (or cleared)
static int findFlags(Seen *list, int count, int from, uint64_t flag, BOOL set) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (list[i].type == kCGEventFlagsChanged && (list[i].flags & flag ? YES : NO) == set)
            return i;
    }
    return -1;
}

int main(void) {
    @autoreleasepool {
        KeyApplication *app = (KeyApplication *) [KeyApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                             CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) |
                                                     CGEventMaskBit(kCGEventFlagsChanged),
                                             tapCallback, NULL);
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
        [window setTitle: @"kbd-cgevents"];
        [window makeKeyAndOrderFront: nil];
        [app finishLaunching];
        printf("READY\n");
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 25];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
        }
        // What the harness' wtype typed, in the taps' order
        printf("tap events %d, NSEvents %d\n", tapCount, nsCount);
        for (int i = 0; i < tapCount; i++)
            printf("  tap %2d: type %d key %3d flags %#llx chars %#x/%d repeat %d down %d state %#llx\n", tapSeen[i].seq,
                   (int) tapSeen[i].type, tapSeen[i].keyCode, (unsigned long long) tapSeen[i].flags, tapSeen[i].chars[0],
                   tapSeen[i].length, tapSeen[i].autorepeat, tapSeen[i].keyStateDown, (unsigned long long) tapSeen[i].hidFlagsState);
        for (int i = 0; i < nsCount; i++)
            printf("  ns  %2d: type %d key %3d flags %#llx chars %#x/%d repeat %d unmodified %#llx\n", nsSeen[i].seq,
                   (int) nsSeen[i].type, nsSeen[i].keyCode, (unsigned long long) nsSeen[i].flags, nsSeen[i].chars[0],
                   nsSeen[i].length, nsSeen[i].autorepeat, (unsigned long long) nsSeen[i].hidFlagsState);

        // The virtual keyboard of the harness has a keymap of its own: what identifies a key here is its
        // character, not its key code.
        // Plain key
        int down = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, 'a');
        expect(down >= 0 && !(tapSeen[down].flags & kCGEventFlagMaskShift) && tapSeen[down].autorepeat == 0,
               @"the tap sees the key a: character, no modifier, not a repeat");
        expect(down >= 0 && tapSeen[down].keyStateDown, @"the hardware key state follows the key (down inside the tap)");
        int up = down >= 0 ? findKey(tapSeen, tapCount, down + 1, kCGEventKeyUp, 'a') : -1;
        expect(up >= 0 && !tapSeen[up].keyStateDown, @"the tap sees the key a come up, and the key state is up");
        int nsDown = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, 'a');
        expect(nsDown >= 0 && nsSeen[nsDown].hidFlagsState == 'a',
               @"AppKit's key down: characters and charactersIgnoringModifiers a");
        expect(down >= 0 && nsDown >= 0 && tapSeen[down].seq < nsSeen[nsDown].seq,
               @"the tap saw the key before AppKit delivered it");

        // Shift + a: the modifier arrives as the compositor's modifier state
        int shiftChange = findFlags(tapSeen, tapCount, up + 1, kCGEventFlagMaskShift, YES);
        expect(shiftChange >= 0 && (tapSeen[shiftChange].hidFlagsState & kCGEventFlagMaskShift),
               @"the tap sees the flags change to Shift, and the flags state follows");
        // The character the key types with Shift is up to the compositor's keymap (A with a layout's
        // shift level, a with a keymap that has no level for it), so a and A are both right.
        int bigDown = shiftChange >= 0 ? findLetter(tapSeen, tapCount, shiftChange + 1, kCGEventKeyDown, 'a') : -1;
        expect(bigDown >= 0 && (tapSeen[bigDown].flags & kCGEventFlagMaskShift), @"the key typed with Shift has the Shift flag");
        int shiftUp = bigDown >= 0 ? findFlags(tapSeen, tapCount, bigDown + 1, kCGEventFlagMaskShift, NO) : -1;
        expect(shiftUp >= 0 && !(tapSeen[shiftUp].hidFlagsState & kCGEventFlagMaskShift),
               @"the flags change back when Shift is released, and the flags state follows");
        int nsShift = findFlags(nsSeen, nsCount, 0, NSEventModifierFlagShift, YES);
        expect(nsShift >= 0, @"AppKit gets a flags changed event with Shift");
        int nsBig = nsShift >= 0 ? findLetter(nsSeen, nsCount, nsShift + 1, kCGEventKeyDown, 'a') : -1;
        expect(nsBig >= 0 && (nsSeen[nsBig].flags & NSEventModifierFlagShift), @"AppKit's key down has the Shift flag");

        // Control + a
        int ctrlChange = shiftUp >= 0 ? findFlags(tapSeen, tapCount, shiftUp + 1, kCGEventFlagMaskControl, YES) : -1;
        int ctrlKey = ctrlChange >= 0 ? findKey(tapSeen, tapCount, ctrlChange + 1, kCGEventKeyDown, 1) : -1;
        expect(ctrlKey >= 0 && (tapSeen[ctrlKey].flags & kCGEventFlagMaskControl),
               @"Control + a: the control character and the Control flag");
        int nsCtrl = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, 1);
        expect(nsCtrl >= 0 && nsSeen[nsCtrl].hidFlagsState == 'a', @"AppKit: the characters ignoring the modifiers are a");

        // Key repeat
        int sDown = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, 's');
        expect(sDown >= 0 && tapSeen[sDown].autorepeat == 0, @"the first press of s is not a repeat");
        int repeats = 0, tapRepeats = 0, sUps = 0;
        for (int i = 0; i < tapCount; i++) {
            if (tapSeen[i].type == kCGEventKeyDown && hasChar(&tapSeen[i], 's') && tapSeen[i].autorepeat)
                tapRepeats++;
            if (tapSeen[i].type == kCGEventKeyUp && hasChar(&tapSeen[i], 's'))
                sUps++;
        }
        for (int i = 0; i < nsCount; i++) {
            if (nsSeen[i].type == kCGEventKeyDown && hasChar(&nsSeen[i], 's') && nsSeen[i].autorepeat)
                repeats++;
        }
        expect(tapRepeats >= 3, [NSString stringWithFormat: @"the tap sees autorepeat key downs while s is held (%d)", tapRepeats]);
        expect(repeats == tapRepeats, [NSString stringWithFormat: @"AppKit delivers each as a repeat (%d)", repeats]);
        expect(sUps == 1, @"one key up for the held key");

        // A tap that changes the key
        int nsE = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, 'e');
        expect(nsE >= 0 && nsSeen[nsE].keyCode == kVK_ANSI_E, @"the tap turned d into e: AppKit's key is e with its key code");
        expect(findKey(nsSeen, nsCount, 0, kCGEventKeyDown, 'd') < 0, @"AppKit got no d");
        expect(nsE >= 0 && nsSeen[nsE].hidFlagsState == 'e',
               @"and its characters ignoring the modifiers follow the changed key code");
        // Shift + Tab: the NSEvent's characters are the back tab character (the virtual keyboard's key code is not
        // the Tab key's, so the key is found by its characters: the layout's tab character reaches the tap)
        int tapTab = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, '\t');
        expect(tapTab >= 0 && (tapSeen[tapTab].flags & kCGEventFlagMaskShift), @"Shift + Tab: the tap sees the layout's tab character U+0009 with the Shift flag");
        int nsTab = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, NSBackTabCharacter);
        expect(nsTab >= 0 && (nsSeen[nsTab].flags & NSEventModifierFlagShift) && nsSeen[nsTab].hidFlagsState == NSBackTabCharacter,
               @"Shift + Tab: AppKit's characters and charactersIgnoringModifiers are U+0019 (NSBackTabCharacter)");
        expect(findKey(nsSeen, nsCount, 0, kCGEventKeyDown, '\t') < 0, @"Shift + Tab: AppKit gets no U+0009");
        expect(nsCGEventMatches, @"every NSEvent's CGEvent is the one the tap passed on (key code)");
        expect(nsHasWindow, @"the key events are for a window");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
