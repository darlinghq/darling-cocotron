// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// The input method stays in the framework that owns the windows: for the text of a key press, CoreGraphics'
// X11 keyboard asks the observer of the connection (AppKit's X11 display registers itself as one) for the
// text its input context composes, and looks the key up in the keymap itself when the observer has none. This
// program registers a stub observer, a stand-in for the input context, in a process without AppKit, with a
// CGS window of its own, and checks what an event tap sees. Driven by coregraphics-x11-composed-text-hook.sh,
// which types j, k and q with XTest:
//   j   the observer has no input context for it (nil): the text is the keymap's
//   k   the observer composes two characters and a keysym
//   q   the end
// Usage: coregraphics-x11-composed-text-hook (no arguments)
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
extern void _CGSSetNativeConnectionObserver(id observer);

// X keysyms of the keys: XK_k
enum { kKeysymK = 0x6b };

static int asked, askedForRelease;
static unsigned long askedWindow;

@interface StubInputContext : NSObject
@end

@implementation StubInputContext
- (NSString *) nativeConnectionComposedTextForKeyEvent: (void *) event keySym: (unsigned long *) keySym {
    // An XKeyEvent: type, serial, send_event, display, window, ..., keycode at a fixed place; the keysym of the
    // key is what the lookup in the keymap gives, which this stub also answers for the key it handles.
    struct {
        int type;
        unsigned long serial;
        int send_event;
        void *display;
        unsigned long window;
        unsigned long root, subwindow, time;
        int x, y, x_root, y_root;
        unsigned int state;
        unsigned int keycode;
    } *key = event;
    asked++;
    askedWindow = key->window;
    if (key->type != 2)
        askedForRelease++;
    // The key k has keycode 45 on a PC keyboard with the evdev keymap
    if (key->keycode != 45)
        return nil;
    *keySym = kKeysymK;
    return @"ḱx";
}
@end

typedef struct {
    CGEventType type;
    int keyCode;
    unichar chars[4];
    int length;
} Seen;

static Seen seen[64];
static int count;
static BOOL quit;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if ((type != kCGEventKeyDown && type != kCGEventKeyUp) || count >= 64)
        return event;
    Seen *s = &seen[count++];
    s->type = type;
    s->keyCode = (int) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    UniCharCount length = 0;
    CGEventKeyboardGetUnicodeString(event, 4, &length, s->chars);
    s->length = (int) length;
    if (type == kCGEventKeyUp && length == 1 && s->chars[0] == 'q')
        quit = YES;
    return event;
}

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
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
        if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess ||
            CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        StubInputContext *stub = [StubInputContext new];
        _CGSSetNativeConnectionObserver(stub);

        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp), tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        printf("READY %lu\n", (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, wid));
        fflush(stdout);
        unsigned long window = (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, wid);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 30];
        while (!quit && [deadline timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);

        for (int i = 0; i < count; i++)
            printf("  tap: type %d key %3d chars %#x %#x %#x/%d\n", (int) seen[i].type, seen[i].keyCode, seen[i].chars[0], seen[i].chars[1],
                   seen[i].chars[2], seen[i].length);
        printf("the observer was asked %d times (%d for key releases)\n", asked, askedForRelease);

        int jDown = -1, kDown = -1, kUp = -1;
        for (int i = 0; i < count; i++) {
            if (seen[i].type == kCGEventKeyDown && seen[i].length == 1 && seen[i].chars[0] == 'j')
                jDown = i;
            if (seen[i].type == kCGEventKeyDown && seen[i].length == 3 && seen[i].chars[0] == 'k')
                kDown = i;
            if (seen[i].type == kCGEventKeyUp && seen[i].length == 1 && seen[i].chars[0] == 'k')
                kUp = i;
        }
        expect(jDown >= 0, "a key the observer has no text for (nil): the character from the keymap");
        expect(kDown >= 0 && seen[kDown].chars[1] == 0x301 && seen[kDown].chars[2] == 'x',
               "a key the observer composes text for: that text, as the characters of the key down");
        expect(kUp >= 0, "the key up of that key has the characters of the keymap (the input method is asked for presses only)");
        expect(askedForRelease == 0 && asked >= 2, "the observer is asked for key presses, and for nothing else");
        expect(askedWindow == window, "and the event it is asked about is for the window of the process");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
