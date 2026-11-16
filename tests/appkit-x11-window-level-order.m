// Copyright (C) 2026 Lubos Dolezel
//
// Window levels order windows on the X11 backend: a window ordered to the
// front goes in front of the windows of its own or a lower level and stays
// behind those of a higher level (NSWindow level, documented). A borderless
// window that cannot become key is an unmanaged X window, which a window
// manager does not restack, so the order of such a window and a managed one
// has to be made by the backend. Needs a running window manager to fail
// without the fix (xfwm4 on Xvfb was used); without one it passes either way.
// Build: guest-cc.sh -o t appkit-x11-window-level-order.m -framework Cocoa
#import <Cocoa/Cocoa.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void settle(void) {
    // The window manager acts on requests after they are made.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
}

static NSWindow *front(void) {
    for (NSWindow *w in [NSApp orderedWindows])
        if ([w isVisible] && [[w title] length])
            return w;
    return nil;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        // A borderless window answers NO to -canBecomeKeyWindow: unmanaged.
        NSWindow *plain = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        [plain setTitle:@"plain"];
        NSWindow *dialog = [[NSWindow alloc] initWithContentRect:NSMakeRect(150, 150, 300, 200)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered defer:NO];
        [dialog setTitle:@"dialog"];

        // A window of a higher level stays in front of an unmanaged one that is ordered in later.
        [plain orderFront:nil];
        [dialog setLevel:NSModalPanelWindowLevel];
        [dialog makeKeyAndOrderFront:nil];
        settle();
        CHECK(front() == dialog, "dialog of a higher level is in front of the unmanaged window, front is %s", [[front() title] UTF8String]);
        [plain orderFront:nil];
        settle();
        CHECK(front() == dialog, "unmanaged window ordered in later stays behind the higher level, front is %s", [[front() title] UTF8String]);

        // Equal levels: the window ordered in last is in front, whichever kind it is.
        [dialog setLevel:NSNormalWindowLevel];
        settle();
        [plain orderFront:nil];
        settle();
        CHECK(front() == plain, "unmanaged window ordered in last is in front at equal levels, front is %s", [[front() title] UTF8String]);
        [dialog makeKeyAndOrderFront:nil];
        settle();
        CHECK(front() == dialog, "managed window ordered in last is in front of an unmanaged one at equal levels, front is %s", [[front() title] UTF8String]);

        // Raising the level of the managed window puts it above the unmanaged one that was in front.
        [plain orderFront:nil];
        settle();
        [dialog setLevel:NSFloatingWindowLevel];
        settle();
        CHECK(front() == dialog, "raising the level puts the window in front of the unmanaged window, front is %s", [[front() title] UTF8String]);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
