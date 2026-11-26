// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// Carbon hot keys delivered by the xdg-desktop-portal GlobalShortcuts interface. The host-side
// fake portal binds only the first of the two registrations, sends a stray Deactivated before any
// press, then sends Activated twice and Deactivated twice. The documented Carbon contract still
// applies:
//   - one kEventHotKeyPressed and one kEventHotKeyReleased per activation;
//   - the EventHotKeyID is the one given at registration;
//   - duplicate and unmatched deactivations are ignored.
// The program prints READY once the registrations are in place, then the tokens it saw and
// ALL PASSED or FAILED n. It needs no keyboard focus: run.py drives the portal from the bus.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <stdio.h>

static NSMutableArray<NSString *> *events;
static EventHotKeyRef hotKey1, hotKey2;
static BOOL quit;
static int failures;

static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

static OSStatus hotKeyHandler(EventHandlerCallRef next, EventRef event, void *userData) {
    EventHotKeyID identifier;
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(identifier), NULL,
                          &identifier) != noErr)
        return eventNotHandledErr;
    if (identifier.signature != 'hkpg') {
        [events addObject: @"badsignature"];
        return eventNotHandledErr;
    }
    [events addObject: [NSString stringWithFormat: @"%c%u", GetEventKind(event) == kEventHotKeyPressed ? 'P' : 'R',
                                               (unsigned) identifier.id]];
    if ([events count] == 2)
        quit = YES;
    return noErr;
}

int main(void) {
    @autoreleasepool {
        events = [NSMutableArray new];
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        EventTypeSpec specs[2] = {{kEventClassKeyboard, kEventHotKeyPressed},
                                  {kEventClassKeyboard, kEventHotKeyReleased}};
        EventHandlerRef handler = NULL;
        expect(InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 2, specs, NULL, &handler) == noErr,
               @"the hot key handler is installed");

        EventTargetRef target = GetApplicationEventTarget();
        expect(RegisterEventHotKey(kVK_ANSI_A, controlKey, (EventHotKeyID){'hkpg', 1}, target, 0, &hotKey1) == noErr,
               @"Control+A registers");
        expect(RegisterEventHotKey(kVK_ANSI_A, controlKey | shiftKey, (EventHotKeyID){'hkpg', 2}, target, 0, &hotKey2) == noErr,
               @"Control+Shift+A registers");
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

        NSString *seen = [events componentsJoinedByString: @" "];
        printf("seen: %s\n", [seen UTF8String]);
        printf("expected: P1 R1\n");
        expect([seen isEqualToString: @"P1 R1"],
               @"the portal's activation produces one Carbon press and one release");

        expect(UnregisterEventHotKey(hotKey1) == noErr && UnregisterEventHotKey(hotKey2) == noErr,
               @"the hot keys unregister");
        RemoveEventHandler(handler);
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures != 0;
}
