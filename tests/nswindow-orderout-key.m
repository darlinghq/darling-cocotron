#import <AppKit/AppKit.h>
#include <stdlib.h>

// Needs a window server (e.g. DARLING_APPKIT_BACKEND=x11 on Xvfb, with or
// without a window manager).
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
        NSWindow *document = makeWindow(@"orderout-document", 100);
        NSWindow *transient = makeWindow(@"orderout-transient", 400);
        [document makeKeyAndOrderFront: nil];
        spin(1);
        [transient makeKeyAndOrderFront: nil];
        spin(1);
        expect([transient isKeyWindow], @"transient window is key once ordered front");

        [transient orderOut: nil];
        expect([document isKeyWindow], @"ordering out the key window makes the remaining window key");
        spin(2);
        expect([document isKeyWindow], @"the remaining window stays key");
        expect(![transient isKeyWindow], @"the ordered-out window is not key");

        [document orderOut: nil];
        expect([NSApp keyWindow] == nil, @"no key window once every window is ordered out");
        NSLog(@"PASS: nswindow-orderout-key");
    }
    return 0;
}
