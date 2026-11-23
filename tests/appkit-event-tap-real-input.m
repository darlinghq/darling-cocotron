// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// Real input of the window system goes through the event taps of the process before AppKit gets
// it, and AppKit's mouse events pass the Carbon handlers before -sendEvent:. An active tap in the
// process turns the key "a" into "b" and counts the key and mouse-down events it sees; a Carbon
// handler on the application target and an NSApplication subclass log the mouse-down. Driven by
// appkit-event-tap-real-input-x11.sh (XTest) and appkit-event-tap-real-input-wayland.sh (virtual
// keyboard and pointer): the program prints READY and the window's content frame, the harness types
// "a" and clicks in the window, and the program reports what arrived.
//
// Usage: appkit-event-tap-real-input (it waits at most 30 seconds for the input; no arguments,
// which -finishLaunching would take for documents to open)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

static int tapKeys, tapMouseDowns;
static NSMutableArray *mouseLog;
static NSString *typed;
static BOOL keyCGEventChanged, keyHasWindow, mouseHasWindow;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        UniChar chars[4];
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 4, &length, chars);
        if (length == 1 && chars[0] == 'a') {
            UniChar b = 'b';
            CGEventKeyboardSetUnicodeString(event, 1, &b);
            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, kVK_ANSI_B);
            if (type == kCGEventKeyDown)
                tapKeys++;
        }
    } else if (type == kCGEventLeftMouseDown) {
        tapMouseDowns++;
    }
    return event;
}

static OSStatus mouseHandler(EventHandlerCallRef call, EventRef event, void *info) {
    [mouseLog addObject: @"carbon"];
    return eventNotHandledErr;
}

@interface TapApplication : NSApplication
@end

@implementation TapApplication
- (void) sendEvent: (NSEvent *) event {
    if ([event type] == NSEventTypeLeftMouseDown) {
        [mouseLog addObject: @"sendEvent"];
        mouseHasWindow = [event window] != nil;
    } else if ([event type] == NSEventTypeKeyDown && typed == nil) {
        typed = [[event characters] copy];
        keyHasWindow = [event window] != nil;
        keyCGEventChanged = [event CGEvent] != NULL &&
                CGEventGetIntegerValueField([event CGEvent], kCGKeyboardEventKeycode) == kVK_ANSI_B;
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

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    double seconds = 30;
    mouseLog = [NSMutableArray new];
    [TapApplication sharedApplication];
    [NSApp finishLaunching];

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventLeftMouseDown);
    CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask,
                                         tapCallback, NULL);
    if (tap == NULL) {
        printf("FAIL no event tap\n");
        return 1;
    }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);

    EventTypeSpec spec = {kEventClassMouse, kEventMouseDown};
    InstallEventHandler(GetApplicationEventTarget(), mouseHandler, 1, &spec, NULL, NULL);

    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: @"tap-real-input"];
    [window center];
    [window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];

    // Where the harness clicks: the middle of the content, in screen coordinates with the origin at
    // the top left (where the window system put the window may differ; the harness also asks it)
    NSRect content = [window contentRectForFrameRect: [window frame]];
    CGFloat top = NSMaxY([[[NSScreen screens] objectAtIndex: 0] frame]);
    printf("CONTENT %d %d %d %d\n", (int) content.origin.x, (int) (top - NSMaxY(content)), (int) content.size.width,
           (int) content.size.height);
    printf("READY\n");
    fflush(stdout);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0 && (typed == nil || [mouseLog count] < 2)) {
        NSAutoreleasePool *inner = [NSAutoreleasePool new];
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.25]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
        [inner release];
    }

    expect(tapKeys >= 1, [NSString stringWithFormat: @"the tap saw the real key press (%d)", tapKeys]);
    expect([typed isEqual: @"b"], [NSString stringWithFormat: @"AppKit got the key as the tap changed it (%@)", typed]);
    expect(keyCGEventChanged, @"  its -CGEvent is the changed one");
    expect(keyHasWindow, @"  and it belongs to the key window");
    expect(tapMouseDowns >= 1, [NSString stringWithFormat: @"the tap saw the real mouse-down (%d)", tapMouseDowns]);
    NSString *order = [mouseLog componentsJoinedByString: @","];
    expect([order hasPrefix: @"carbon,sendEvent"],
          [NSString stringWithFormat: @"the Carbon handler runs before -sendEvent: (%@)", order]);
    expect(mouseHasWindow, @"  the mouse-down belongs to the window");

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    fflush(stdout);
    [pool release];
    return failures ? 1 : 0;
}
