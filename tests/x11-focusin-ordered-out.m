#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

// Run with DARLING_APPKIT_BACKEND=x11 while x11-send-focusin (host side)
// waits for the "focus-probe" window to be unmapped and sends it a FocusIn.
static void expect(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static NSWindow *makeWindow(NSString *title, CGFloat x) {
    NSWindow *window = [[NSWindow alloc]
            initWithContentRect: NSMakeRect(x, 200, 240, 160)
                      styleMask: NSWindowStyleMaskTitled
                        backing: NSBackingStoreBuffered
                          defer: NO];
    [window setTitle: title];
    return window;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *other = makeWindow(@"focus-other", 100);
        NSWindow *probe = makeWindow(@"focus-probe", 400);
        [other makeKeyAndOrderFront: nil];
        [probe makeKeyAndOrderFront: nil];
        spin(2);

        [probe orderOut: nil];
        [other makeKeyAndOrderFront: nil];
        printf("READY\n");
        fflush(stdout);
        spin(6);

        expect(![probe isVisible], @"ordered-out window stays out after a FocusIn");
        expect(![probe isKeyWindow], @"ordered-out window does not become key");
        NSLog(@"PASS: x11-focusin-ordered-out");
    }
    return 0;
}
