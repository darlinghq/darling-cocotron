// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// The window system's input method, used through CoreGraphics' private interface (CGSInputMethod.h) by a
// process without AppKit that has a window of its own: the window is enabled for the input method,
// told where the text is being entered, and hears the composition as toplevel events; the text the input
// method commits is the characters of the key events an event tap sees (on X11 the input method returns it
// when it is asked for the text of a key). Driven by coregraphics-x11-input-method-no-appkit.sh, which runs
// x11-test-xim-server.c as the input method (XMODIFIERS=@im=testxim for this program) and types with XTest:
//   a, b          the input method composes: preedit "a", then "ab" with the caret at the end
//   BackSpace     preedit "a"
//   b, Return     preedit "ab", then no preedit, and the text "AB" committed as the characters of a key
//   c, Escape     preedit "c", then no preedit (cancelled), nothing committed
//   2, Escape     non-ASCII preedit U+65E5 U+672C U+8A9E with the caret after the first character, then none
//   3, Escape     a character outside the BMP and "a": the caret is after the pair, UTF-16 offset 2
//   4             non-ASCII text committed: the characters of a key
//   Tab           a key the input method forwards: the characters of the keymap (a tab); the program moves
//                 the cursor rectangle now, and the server logs the spot it is told of
//   F2            the program disables the window's input method
//   d             a plain key: the keymap's text, and no preedit
//   1             the end (the input method forwards digits)
// The program prints READY <X window>, then runs until the key "1" comes up or 30 seconds have passed.
// Usage: coregraphics-x11-input-method-no-appkit (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSWindow.h>
#import <CoreGraphics/CGSServerSPI.h>
#import <CoreGraphics/CGSInputMethod.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);

// X11 key codes of the keys the harness types on a PC keyboard (evdev): Tab, F2
enum { kTab = 23, kF2 = 68 };

typedef enum { kKey, kPreedit, kCommit } Kind;

typedef struct {
    Kind kind;
    int keyCode;
    BOOL down;
    char text[32]; // UTF-8: the characters of a key, or the preedit's text
    long caret;
} Seen;

static Seen seen[128];
static int count;
static BOOL quit;
static CGSWindowID windowID;
static BOOL movedRect, disabled;

static void toplevelEvent(CGSWindow *window, const CGSToplevelEvent *event, void *info) {
    if ((event->kind != kCGSToplevelEventInputMethodPreedit && event->kind != kCGSToplevelEventInputMethodCommit) || count >= 128)
        return;
    Seen *s = &seen[count++];
    s->kind = event->kind == kCGSToplevelEventInputMethodPreedit ? kPreedit : kCommit;
    s->down = YES;
    s->keyCode = -1;
    strlcpy(s->text, [(NSString *) event->text UTF8String], sizeof(s->text));
    s->caret = event->textRange.location;
}

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if ((type != kCGEventKeyDown && type != kCGEventKeyUp) || count >= 128)
        return event;
    Seen *s = &seen[count++];
    s->kind = kKey;
    s->down = type == kCGEventKeyDown;
    s->keyCode = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    UniChar chars[8];
    UniCharCount length = 0;
    CGEventKeyboardGetUnicodeString(event, 8, &length, chars);
    NSString *string = [NSString stringWithCharacters: chars length: length];
    strlcpy(s->text, [string UTF8String], sizeof(s->text));
    s->caret = 0;
    if (!s->down && length == 1 && chars[0] == '1')
        quit = YES;
    // The keys the program acts on, as the harness types them.
    if (s->down && s->keyCode == 48 /* kVK_Tab */ && !movedRect) {
        movedRect = YES;
        _CGSInputMethodSetCursorRect(windowID, CGRectMake(50, 60, 2, 16));
    }
    if (s->down && s->keyCode == 120 /* kVK_F2 */ && !disabled) {
        disabled = YES;
        _CGSInputMethodSetEnabled(windowID, NO);
    }
    return event;
}

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

// The index of the next event of this kind with this text at or after `from`, -1 when there is none.
static int find(int from, Kind kind, const char *text) {
    for (int i = from < 0 ? 0 : from; i < count; i++) {
        if (seen[i].kind == kind && seen[i].down && strcmp(seen[i].text, text) == 0)
            return i;
    }
    return -1;
}

int main(void) {
    @autoreleasepool {
        if (!_CGSInputMethodAvailable()) {
            printf("FAIL the window system has no input method\n");
            return 1;
        }
        CGSConnectionID cid = CGSMainConnectionID();
        CGRect frame = CGRectMake(100, 100, 300, 200);
        RegionRef region = NULL;
        if (cid == 0 || CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess ||
            CGSNewWindow(cid, 0, 0, 0, region, &windowID) != kCGErrorSuccess || CGSOrderWindow(cid, windowID, 1, 0) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        // What the window system tells about the window comes to its event handler.
        [[_CGSConnectionForID(cid) windowForId: windowID] setToplevelEventProc: toplevelEvent info: NULL];

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp), tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        _CGSInputMethodSetCursorRect(windowID, CGRectMake(10, 20, 2, 16));
        _CGSInputMethodSetEnabled(windowID, YES);

        printf("READY %lu\n", (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, windowID));
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 30];
        while (!quit && [deadline timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);

        for (int i = 0; i < count; i++)
            printf("  %s %s key %3d \"%s\" caret %ld\n", seen[i].kind == kKey ? "key" : (seen[i].kind == kPreedit ? "preedit" : "commit"),
                   seen[i].down ? "down" : "up", seen[i].keyCode, seen[i].text, seen[i].caret);

        int a = find(0, kPreedit, "a");
        int ab = find(a + 1, kPreedit, "ab");
        expect(a >= 0 && seen[a].caret == 1, "the first composed letter is the preedit \"a\" with the caret after it");
        expect(ab > a && seen[ab].caret == 2, "then the preedit \"ab\" (the whole composition each time)");
        int back = find(ab + 1, kPreedit, "a");
        expect(back > ab && seen[back].caret == 1, "a deleted letter is a shorter preedit");
        int ab2 = find(back + 1, kPreedit, "ab");
        int cleared = find(ab2 + 1, kPreedit, "");
        expect(ab2 > back && cleared > ab2, "the composition committed with Return ends: empty preedit");
        int commit = find(cleared + 1, kKey, "AB");
        expect(commit > cleared, "and its text arrives as the characters of a key down, after the preedit has ended");
        int c = find(commit + 1, kPreedit, "c");
        int escaped = find(c + 1, kPreedit, "");
        expect(c > commit && escaped > c, "a cancelled composition ends with an empty preedit");
        expect(find(escaped, kKey, "C") < 0 && find(escaped, kKey, "c") < 0, "and commits nothing");
        int jp = find(escaped + 1, kPreedit, "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e");
        expect(jp > escaped && seen[jp].caret == 1, "non-ASCII preedit arrives exactly, the caret after the first character");
        int jpEnd = find(jp + 1, kPreedit, "");
        int emoji = find(jpEnd + 1, kPreedit, "\xf0\x9f\x98\x80" "a");
        expect(jpEnd > jp && emoji > jpEnd && seen[emoji].caret == 2,
               "a character outside the BMP: the caret offset counts UTF-16 units (2 after the first character)");
        int emojiEnd = find(emoji + 1, kPreedit, "");
        int jpCommit = find(emojiEnd + 1, kKey, "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e");
        expect(emojiEnd > emoji && jpCommit > emojiEnd, "non-ASCII committed text arrives exactly as the characters of a key");
        int tab = find((jpCommit > 0 ? jpCommit : escaped) + 1, kKey, "\t");
        expect(tab > escaped, "a key the input method forwards has the characters of the keymap");
        int d = find(tab + 1, kKey, "d");
        expect(d > tab, "after the window's input method is disabled, a letter is the keymap's text");
        int preeditAfter = -1;
        for (int i = d; i < count; i++) {
            if (seen[i].kind == kPreedit)
                preeditAfter = i;
        }
        expect(preeditAfter < 0, "and there is no composition any more");
        int commits = 0;
        for (int i = 0; i < count; i++)
            commits += seen[i].kind == kCommit;
        expect(commits == 0, "no commit event is posted on X11: the committed text is the key's");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
