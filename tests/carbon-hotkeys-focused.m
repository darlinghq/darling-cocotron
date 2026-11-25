// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// Carbon hot keys (RegisterEventHotKey) while the application is active, with keys typed into its window by
// a harness (carbon-hotkeys-wayland.sh on Wayland, carbon-hotkeys-x11.sh on X11). The documented contract:
//   - a registered key code with modifiers sends kEventHotKeyPressed, then kEventHotKeyReleased, with the
//     EventHotKeyID given at registration, to the target given at registration;
//   - the key does not also reach the application as a key event (neither the key down nor the key up);
//   - the modifiers must match exactly, and Caps Lock does not count;
//   - holding the key sends one press, not one per autorepeat;
//   - registering a combination the application holds already fails with eventHotKeyExistsErr, and after
//     UnregisterEventHotKey the key is an ordinary key again.
// The program records what it sees as tokens, P<id> and R<id> for hot key events and kd<code> and ku<code> for
// key events (key codes: A 0, B 11, F5 96, Q 12), and compares the list with the keys the harness typed:
//   Control+A                        P1 R1
//   Control+Shift+A                  P2 R2
//   F5                               P3 R3
//   A                                kd0 ku0
//   Caps Lock on, Control+A, off     P1 R1   (only with HOTKEY_CAPS=1)
//   Control+A held for 1.3 s         P1 R1
//   B                                kd11 ku11, and the program unregisters hot key 1
//   Control+A                        kd0 ku0
//   Control+Shift+A                  P2 R2
//   Q                                kd12 (the end)
// Prints READY when the window is up, then PASS lines and ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NSMutableArray<NSString *> *events;
static EventHotKeyRef hotKey1, hotKey2, hotKey3;
static BOOL quit;
static int failures;

static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

@interface HotKeyApplication : NSApplication
@end

@implementation HotKeyApplication
- (void) sendEvent: (NSEvent *) event {
    NSEventType type = [event type];
    if (type == NSEventTypeKeyDown || type == NSEventTypeKeyUp) {
        [events addObject: [NSString stringWithFormat: @"%s%d", type == NSEventTypeKeyDown ? "kd" : "ku", (int) [event keyCode]]];
        if (type == NSEventTypeKeyDown && [event keyCode] == kVK_ANSI_B && hotKey1 != NULL) {
            expect(UnregisterEventHotKey(hotKey1) == noErr, @"UnregisterEventHotKey succeeds");
            hotKey1 = NULL;
        }
        if (type == NSEventTypeKeyDown && [event keyCode] == kVK_ANSI_Q)
            quit = YES;
    }
    [super sendEvent: event];
}
@end

static OSStatus hotKeyHandler(EventHandlerCallRef next, EventRef event, void *userData) {
    EventHotKeyID identifier;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(identifier), NULL,
                          &identifier) != noErr)
        return eventNotHandledErr;
    if (identifier.signature != 'hkfc') {
        [events addObject: @"badsignature"];
        return eventNotHandledErr;
    }
    [events addObject: [NSString stringWithFormat: @"%c%u", GetEventKind(event) == kEventHotKeyPressed ? 'P' : 'R',
                                               (unsigned) identifier.id]];
    return noErr;
}

int main(void) {
    @autoreleasepool {
        events = [NSMutableArray new];
        HotKeyApplication *app = (HotKeyApplication *) [HotKeyApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        EventTypeSpec specs[2] = {{kEventClassKeyboard, kEventHotKeyPressed}, {kEventClassKeyboard, kEventHotKeyReleased}};
        EventHandlerRef handler = NULL;
        expect(InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 2, specs, NULL, &handler) == noErr,
               @"the handler is installed");
        EventTargetRef target = GetApplicationEventTarget();
        expect(RegisterEventHotKey(kVK_ANSI_A, controlKey, (EventHotKeyID){'hkfc', 1}, target, 0, &hotKey1) == noErr,
               @"Control+A registers");
        expect(RegisterEventHotKey(kVK_ANSI_A, controlKey | shiftKey, (EventHotKeyID){'hkfc', 2}, target, 0, &hotKey2) == noErr,
               @"Control+Shift+A registers: the same key with other modifiers is another hot key");
        expect(RegisterEventHotKey(kVK_F5, 0, (EventHotKeyID){'hkfc', 3}, target, 0, &hotKey3) == noErr,
               @"F5 with no modifier registers");
        EventHotKeyRef duplicate = NULL;
        OSStatus status = RegisterEventHotKey(kVK_ANSI_A, controlKey, (EventHotKeyID){'hkfc', 9}, target, 0, &duplicate);
        expect(status == eventHotKeyExistsErr, @"registering Control+A again fails with eventHotKeyExistsErr");
        expect(duplicate == NULL, @"and returns no reference");

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"carbon-hotkeys-focused"];
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

        NSString *seen = [events componentsJoinedByString: @" "];
        printf("seen: %s\n", [seen UTF8String]);
        BOOL caps = getenv("HOTKEY_CAPS") != NULL;
        NSString *expected = [NSString stringWithFormat: @"P1 R1 P2 R2 P3 R3 kd0 ku0 %@P1 R1 kd11 ku11 kd0 ku0 P2 R2 kd12",
                                                        caps ? @"P1 R1 " : @""];
        printf("expected: %s\n", [expected UTF8String]);
        expect([seen isEqualToString: expected], @"hot key and key events came in the typed order, hot keys consumed their keys");

        expect(hotKey1 == NULL && UnregisterEventHotKey(hotKey2) == noErr && UnregisterEventHotKey(hotKey3) == noErr,
               @"the other hot keys unregister");
        EventHotKeyRef again = NULL;
        expect(RegisterEventHotKey(kVK_ANSI_A, controlKey, (EventHotKeyID){'hkfc', 1}, target, 0, &again) == noErr,
               @"the unregistered combination registers again");
        UnregisterEventHotKey(again);
        RemoveEventHandler(handler);
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures != 0;
}
