// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The keyboard of the X server reaches AppKit as CGEvents: the event taps of the process see the key, flags
// changed and key repeat events CoreGraphics decodes from the server's key events (with the key code, the
// characters, the modifier flags with the device bits of the left and right keys and the autorepeat field),
// the state functions of CGEventSource follow them, and the NSEvents AppKit makes are made from the CGEvents
// the taps passed on, so that a tap that changes a key changes what the application gets. Driven by
// appkit-keyboard-cgevents-x11.sh (XTest, xdotool): the program prints READY, then reads events until it sees
// the key "q" come up or 40 seconds have passed, and checks what the harness typed, in this order:
//   a                          plain key
//   Shift_L + a                the left Shift key, then a key with the modifier in effect
//   Shift_R                    the right Shift key
//   Control_L + a              control character, characters ignoring the modifiers
//   Alt_L                      the left Option key
//   s held for a second        key repeat
//   d                          the tap turns it into e
//   Tab, Shift_L + Tab         the characters of the NSEvents are U+0009, and U+0019 (NSBackTabCharacter) with Shift
//                              (the server's ISO_Left_Tab; the tap sees the layout's U+0009)
//   Shift_L pressed while another client has the keyboard focus, the focus comes back, Shift_L released
//                              (the flags are read from the server, with no key responsible)
//   q                          the end
// Usage: appkit-keyboard-cgevents-x11 (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

// The device-dependent bits of the modifier flags (IOKit's IOLLEvent.h)
enum {
    DeviceLeftControl = 0x1,
    DeviceLeftShift = 0x2,
    DeviceRightShift = 0x4,
    DeviceLeftOption = 0x20,
};

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
    unichar unmodified;
} Seen;

static Seen tapSeen[512], nsSeen[512];
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

    if (tapCount < 512) {
        Seen *seen = &tapSeen[tapCount++];
        seen->seq = ++sequence;
        seen->type = type;
        seen->keyCode = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        seen->flags = CGEventGetFlags(event);
        UniCharCount length = 0;
        if (type != kCGEventFlagsChanged)
            CGEventKeyboardGetUnicodeString(event, 2, &length, seen->chars);
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
    if ((type == NSEventTypeKeyDown || type == NSEventTypeKeyUp || type == NSEventTypeFlagsChanged) && nsCount < 512) {
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
            seen->unmodified = [unmodified length] > 0 ? [unmodified characterAtIndex: 0] : 0;
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

// The index of the first key event of the type after `from` with the key code (and the character, when not 0)
static int findKey(Seen *list, int count, int from, CGEventType type, int keyCode, unichar c) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (list[i].type == type && list[i].keyCode == keyCode && (c == 0 || hasChar(&list[i], c)))
            return i;
    }
    return -1;
}

// The first flags changed event after `from` for the key code (or any key, with -1)
static int findFlags(Seen *list, int count, int from, int keyCode, uint64_t flag, BOOL set) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (list[i].type == kCGEventFlagsChanged && (keyCode < 0 || list[i].keyCode == keyCode) &&
            (list[i].flags & flag ? YES : NO) == set)
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
        [window setTitle: @"kbd-cgevents-x11"];
        [window makeKeyAndOrderFront: nil];
        [app finishLaunching];
        printf("READY\n");
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 40];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
        }
        printf("tap events %d, NSEvents %d\n", tapCount, nsCount);
        for (int i = 0; i < tapCount; i++)
            printf("  tap %3d: type %d key %3d flags %#llx chars %#x/%d repeat %d down %d state %#llx\n", tapSeen[i].seq,
                   (int) tapSeen[i].type, tapSeen[i].keyCode, (unsigned long long) tapSeen[i].flags, tapSeen[i].chars[0],
                   tapSeen[i].length, tapSeen[i].autorepeat, tapSeen[i].keyStateDown, (unsigned long long) tapSeen[i].hidFlagsState);
        for (int i = 0; i < nsCount; i++)
            printf("  ns  %3d: type %d key %3d flags %#llx chars %#x/%d repeat %d unmodified %#x\n", nsSeen[i].seq,
                   (int) nsSeen[i].type, nsSeen[i].keyCode, (unsigned long long) nsSeen[i].flags, nsSeen[i].chars[0],
                   nsSeen[i].length, nsSeen[i].autorepeat, nsSeen[i].unmodified);

        // Plain key: the key code is that of the physical key
        int down = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, kVK_ANSI_A, 'a');
        expect(down >= 0 && !(tapSeen[down].flags & kCGEventFlagMaskShift) && tapSeen[down].autorepeat == 0,
               @"the tap sees the key a: key code, character, no modifier, not a repeat");
        expect(down >= 0 && tapSeen[down].keyStateDown, @"the hardware key state follows the key (down inside the tap)");
        int up = down >= 0 ? findKey(tapSeen, tapCount, down + 1, kCGEventKeyUp, kVK_ANSI_A, 'a') : -1;
        expect(up >= 0 && !tapSeen[up].keyStateDown, @"the tap sees the key a come up, and the key state is up");
        int nsDown = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, kVK_ANSI_A, 'a');
        expect(nsDown >= 0 && nsSeen[nsDown].unmodified == 'a', @"AppKit's key down: characters and charactersIgnoringModifiers a");
        expect(down >= 0 && nsDown >= 0 && tapSeen[down].seq < nsSeen[nsDown].seq, @"the tap saw the key before AppKit delivered it");

        // Left Shift + a
        int shiftChange = findFlags(tapSeen, tapCount, up + 1, kVK_Shift, kCGEventFlagMaskShift, YES);
        expect(shiftChange >= 0 && (tapSeen[shiftChange].flags & DeviceLeftShift) && !(tapSeen[shiftChange].flags & DeviceRightShift),
               @"the left Shift key: a flags changed event with the Shift flag and the left device bit only");
        expect(shiftChange >= 0 && (tapSeen[shiftChange].hidFlagsState & kCGEventFlagMaskShift) && tapSeen[shiftChange].keyStateDown,
               @"the flags state and the key state follow the Shift key");
        int bigDown = shiftChange >= 0 ? findKey(tapSeen, tapCount, shiftChange + 1, kCGEventKeyDown, kVK_ANSI_A, 'A') : -1;
        expect(bigDown >= 0 && (tapSeen[bigDown].flags & kCGEventFlagMaskShift) && (tapSeen[bigDown].flags & DeviceLeftShift),
               @"the key typed with Shift: the character A, the Shift flag and the device bit");
        int shiftUp = bigDown >= 0 ? findFlags(tapSeen, tapCount, bigDown + 1, kVK_Shift, kCGEventFlagMaskShift, NO) : -1;
        expect(shiftUp >= 0 && !(tapSeen[shiftUp].flags & DeviceLeftShift) && !(tapSeen[shiftUp].hidFlagsState & kCGEventFlagMaskShift),
               @"the flags change back when Shift is released: no flag, no device bit, and the flags state follows");
        int nsShift = findFlags(nsSeen, nsCount, 0, kVK_Shift, NSEventModifierFlagShift, YES);
        expect(nsShift >= 0, @"AppKit gets a flags changed event with Shift");
        int nsBig = nsShift >= 0 ? findKey(nsSeen, nsCount, nsShift + 1, kCGEventKeyDown, kVK_ANSI_A, 'A') : -1;
        expect(nsBig >= 0 && (nsSeen[nsBig].flags & NSEventModifierFlagShift), @"AppKit's key down has the Shift flag");

        // Right Shift
        int rshift = findFlags(tapSeen, tapCount, shiftUp + 1, kVK_RightShift, kCGEventFlagMaskShift, YES);
        expect(rshift >= 0 && (tapSeen[rshift].flags & DeviceRightShift) && !(tapSeen[rshift].flags & DeviceLeftShift),
               @"the right Shift key: its key code and the right device bit only");
        int rshiftUp = rshift >= 0 ? findFlags(tapSeen, tapCount, rshift + 1, kVK_RightShift, kCGEventFlagMaskShift, NO) : -1;
        expect(rshiftUp >= 0, @"and its release");

        // Control + a
        int ctrlChange = findFlags(tapSeen, tapCount, rshiftUp + 1, kVK_Control, kCGEventFlagMaskControl, YES);
        int ctrlKey = ctrlChange >= 0 ? findKey(tapSeen, tapCount, ctrlChange + 1, kCGEventKeyDown, kVK_ANSI_A, 1) : -1;
        expect(ctrlKey >= 0 && (tapSeen[ctrlKey].flags & kCGEventFlagMaskControl) && (tapSeen[ctrlKey].flags & DeviceLeftControl),
               @"Control + a: the control character, the Control flag and the left device bit");
        int nsCtrl = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, kVK_ANSI_A, 1);
        expect(nsCtrl >= 0 && nsSeen[nsCtrl].unmodified == 'a', @"AppKit: the characters ignoring the modifiers are a");

        // Option
        int alt = findFlags(tapSeen, tapCount, ctrlKey + 1, kVK_Option, kCGEventFlagMaskAlternate, YES);
        expect(alt >= 0 && (tapSeen[alt].flags & DeviceLeftOption), @"the left Option key: the flag and the left device bit");

        // Key repeat
        int sDown = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, kVK_ANSI_S, 's');
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
        int nsE = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, kVK_ANSI_E, 'e');
        expect(nsE >= 0, @"the tap turned d into e: AppKit's key is e with its key code");
        expect(findKey(nsSeen, nsCount, 0, kCGEventKeyDown, kVK_ANSI_D, 'd') < 0, @"AppKit got no d");
        expect(nsE >= 0 && nsSeen[nsE].unmodified == 'e', @"and its characters ignoring the modifiers follow the changed key code");
        expect(nsCGEventMatches, @"every NSEvent's CGEvent is the one the tap passed on (key code)");
        expect(nsHasWindow, @"the key events are for a window");

        // Tab and Shift + Tab: the layout's tab character reaches the tap in both, AppKit's characters are the back tab
        // character with Shift
        int tab = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, kVK_Tab, 0x09);
        expect(tab >= 0 && !(tapSeen[tab].flags & kCGEventFlagMaskShift), @"Tab: the tap sees U+0009 and no Shift");
        int backTab = tab >= 0 ? findKey(tapSeen, tapCount, tab + 1, kCGEventKeyDown, kVK_Tab, 0x09) : -1;
        expect(backTab >= 0 && (tapSeen[backTab].flags & kCGEventFlagMaskShift),
               @"Shift + Tab (the server's ISO_Left_Tab): the tap sees the layout's U+0009 and the Shift flag");
        int nsTab = findKey(nsSeen, nsCount, 0, kCGEventKeyDown, kVK_Tab, 0);
        expect(nsTab >= 0 && hasChar(&nsSeen[nsTab], 0x09) && nsSeen[nsTab].unmodified == 0x09 &&
                       !(nsSeen[nsTab].flags & NSEventModifierFlagShift),
               @"Tab: AppKit's characters and charactersIgnoringModifiers are U+0009");
        int nsBackTab = nsTab >= 0 ? findKey(nsSeen, nsCount, nsTab + 1, kCGEventKeyDown, kVK_Tab, 0) : -1;
        expect(nsBackTab >= 0 && (nsSeen[nsBackTab].flags & NSEventModifierFlagShift) && hasChar(&nsSeen[nsBackTab], NSBackTabCharacter) &&
                       nsSeen[nsBackTab].unmodified == NSBackTabCharacter,
               @"Shift + Tab: AppKit's characters and charactersIgnoringModifiers are U+0019 (NSBackTabCharacter)");
        int nsBackTabUp = nsBackTab >= 0 ? findKey(nsSeen, nsCount, nsBackTab + 1, kCGEventKeyUp, kVK_Tab, 0) : -1;
        expect(nsBackTabUp >= 0 && hasChar(&nsSeen[nsBackTabUp], NSBackTabCharacter), @"and the key up of Shift + Tab");

        // Shift held while another client had the focus
        int tapE = findKey(tapSeen, tapCount, 0, kCGEventKeyDown, kVK_ANSI_E, 'e');
        int resync = tapE >= 0 ? findFlags(tapSeen, tapCount, tapE + 1, 0xFFFF, kCGEventFlagMaskShift, YES) : -1;
        expect(resync >= 0 && (tapSeen[resync].hidFlagsState & kCGEventFlagMaskShift),
               @"Shift pressed while another client had the focus: the focus change reports it, with no key responsible");
        int lateUp = resync >= 0 ? findFlags(tapSeen, tapCount, resync + 1, kVK_Shift, kCGEventFlagMaskShift, NO) : -1;
        expect(lateUp >= 0 && !(tapSeen[lateUp].flags & DeviceLeftShift),
               @"and the release of that Shift key is reported for the Shift key, with the device bit gone");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
