// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process without AppKit that has an X11 window of its own (a CGS window) receives the keys typed into it
// as CGEvents: an event tap sees the key down, key up and flags changed events CoreGraphics decodes from
// the server's key events, with the key code, the characters, the modifier flags with the device bits and
// the autorepeat field, and the state functions of CGEventSource follow them. Driven by
// coregraphics-x11-keyboard-no-appkit.sh (XTest): the program prints "READY <window>" with the X window id,
// then runs its run loop until the key "q" comes up or 30 seconds have passed. The harness types:
//   a                  plain key
//   Shift_L + a        the left Shift key, then a key with the modifier in effect
//   Shift_R            the right Shift key
//   s held             key repeat
//   q                  the end
// Usage: coregraphics-x11-keyboard-no-appkit (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdio.h>

typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);
extern void *_CGSNativeDisplay(CGSConnectionID cid);

// X11 key codes of the virtual keys the harness types (HIToolbox/Events.h)
enum { kA = 0, kS = 1, kShift = 56, kRightShift = 60 };
enum { DeviceLeftShift = 0x2, DeviceRightShift = 0x4 };

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

static Seen seen[512];
static int count;
static BOOL quit;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type != kCGEventKeyDown && type != kCGEventKeyUp && type != kCGEventFlagsChanged)
        return event;
    if (count < 512) {
        Seen *s = &seen[count++];
        s->seq = count;
        s->type = type;
        s->keyCode = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        s->flags = CGEventGetFlags(event);
        UniCharCount length = 0;
        if (type != kCGEventFlagsChanged)
            CGEventKeyboardGetUnicodeString(event, 2, &length, s->chars);
        s->length = (int) length;
        s->autorepeat = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat);
        s->keyStateDown = CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, (CGKeyCode) s->keyCode);
        s->hidFlagsState = CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState);
        if (type == kCGEventKeyUp && length == 1 && s->chars[0] == 'q')
            quit = YES;
    }
    return event;
}

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static int findKey(int from, CGEventType type, int keyCode, unichar c) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (seen[i].type == type && seen[i].keyCode == keyCode && seen[i].length == 1 && seen[i].chars[0] == c)
            return i;
    }
    return -1;
}

static int findFlags(int from, int keyCode, uint64_t flag, BOOL set) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (seen[i].type == kCGEventFlagsChanged && seen[i].keyCode == keyCode && (seen[i].flags & flag ? YES : NO) == set)
            return i;
    }
    return -1;
}

int main(void) {
    @autoreleasepool {
        CGSConnectionID cid = CGSMainConnectionID();
        if (cid == 0 || _CGSNativeDisplay(cid) == NULL) {
            printf("FAIL no connection to the window system\n");
            return 1;
        }
        CGRect frame = CGRectMake(100, 100, 300, 200);
        RegionRef region = NULL;
        CGSWindowID wid = 0;
        if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        if (CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess) {
            printf("FAIL cannot order the window in\n");
            return 1;
        }

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
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

        printf("READY %lu\n", (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, wid));
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 30];
        while (!quit && [deadline timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);

        printf("tap events %d\n", count);
        for (int i = 0; i < count; i++)
            printf("  tap %3d: type %d key %3d flags %#llx chars %#x/%d repeat %d down %d state %#llx\n", seen[i].seq, (int) seen[i].type,
                   seen[i].keyCode, (unsigned long long) seen[i].flags, seen[i].chars[0], seen[i].length, seen[i].autorepeat,
                   seen[i].keyStateDown, (unsigned long long) seen[i].hidFlagsState);

        int down = findKey(0, kCGEventKeyDown, kA, 'a');
        expect(down >= 0 && !(seen[down].flags & kCGEventFlagMaskShift) && seen[down].autorepeat == 0,
               "the tap sees the key a: key code, character, no modifier, not a repeat");
        expect(down >= 0 && seen[down].keyStateDown, "the hardware key state follows the key (down inside the tap)");
        int up = down >= 0 ? findKey(down + 1, kCGEventKeyUp, kA, 'a') : -1;
        expect(up >= 0 && !seen[up].keyStateDown, "the tap sees the key a come up, and the key state is up");

        int shift = findFlags(up + 1, kShift, kCGEventFlagMaskShift, YES);
        expect(shift >= 0 && (seen[shift].flags & DeviceLeftShift) && !(seen[shift].flags & DeviceRightShift) &&
                       (seen[shift].hidFlagsState & kCGEventFlagMaskShift),
               "the left Shift key: the Shift flag and the left device bit, and the flags state follows");
        int big = shift >= 0 ? findKey(shift + 1, kCGEventKeyDown, kA, 'A') : -1;
        expect(big >= 0 && (seen[big].flags & kCGEventFlagMaskShift), "the key typed with Shift: the character A and the Shift flag");
        int shiftUp = big >= 0 ? findFlags(big + 1, kShift, kCGEventFlagMaskShift, NO) : -1;
        expect(shiftUp >= 0 && !(seen[shiftUp].hidFlagsState & kCGEventFlagMaskShift), "the flags change back, and the flags state follows");

        int rshift = findFlags(shiftUp + 1, kRightShift, kCGEventFlagMaskShift, YES);
        expect(rshift >= 0 && (seen[rshift].flags & DeviceRightShift) && !(seen[rshift].flags & DeviceLeftShift),
               "the right Shift key: its key code and the right device bit only");

        int sDown = findKey(0, kCGEventKeyDown, kS, 's');
        int repeats = 0;
        for (int i = 0; i < count; i++) {
            if (seen[i].type == kCGEventKeyDown && seen[i].keyCode == kS && seen[i].autorepeat)
                repeats++;
        }
        expect(sDown >= 0 && seen[sDown].autorepeat == 0 && repeats >= 3, "a held key: a first press and autorepeat key downs");
        expect(CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState) == 0 && !CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, kS),
               "after the keys went up, the flags state is empty and no key is down");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
