/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Layering of an AppKit window and its CoreGraphics window, entered from both sides. On macOS an
// NSWindow's windowNumber is its window server id: CGWindowListCopyWindowInfo() lists the window
// under it, and the window server calls (CGSGetWindowBounds, CGSMoveWindow, ...) take it. Here the
// backends of AppKit make their windows through CoreGraphics, so what AppKit does to a window
// (placing, sizing, titling, fading, showing, hiding, closing) must be seen through CoreGraphics, and what
// CoreGraphics does to it (moving it) must be seen by AppKit. A Wayland compositor places the windows itself,
// so on the Wayland backend CoreGraphics cannot move a window: that part is skipped there. Needs an X server (a window manager is only needed for
// the titled window) or a Wayland compositor. Destroying the window is the CoreGraphics side's own test
// (coregraphics-x11-toplevel-window): AppKit keeps its windows alive after they are closed.
#import <AppKit/AppKit.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(cond, what)                                                      \
    do {                                                                       \
        if (cond)                                                              \
            printf("PASS: %s\n", what);                                        \
        else {                                                                 \
            printf("FAIL: %s (line %d)\n", what, __LINE__);                    \
            failures++;                                                        \
        }                                                                      \
    } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

// The entry CGWindowListCopyWindowInfo() has for a window number, or nil.
static NSDictionary *listing(CGWindowID number) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, number);
    NSDictionary *found = nil;
    if (list != NULL) {
        for (NSDictionary *entry in (NSArray *) list) {
            if ([[entry objectForKey: (NSString *) kCGWindowNumber] unsignedIntValue] == number)
                found = [[entry retain] autorelease];
        }
        CFRelease(list);
    }
    return found;
}

static CGRect boundsOf(NSDictionary *entry) {
    CGRect bounds = CGRectNull;
    CGRectMakeWithDictionaryRepresentation((CFDictionaryRef) [entry objectForKey: (NSString *) kCGWindowBounds],
                                           &bounds);
    return bounds;
}

// The frame as CoreGraphics' global space has it: the origin at the top left of the main display.
static CGRect cgRectOfFrame(NSRect frame) {
    CGFloat height = CGDisplayBounds(CGMainDisplayID()).size.height;
    return CGRectMake(frame.origin.x, height - frame.origin.y - frame.size.height, frame.size.width, frame.size.height);
}

// Runs the loop until the condition holds, at most 3 seconds.
#define WAIT_FOR(cond)                                                         \
    for (int i = 0; i < 60 && !(cond); i++)                                    \
        spin(0.05)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Both backends' classes can be loaded; the display in use says which one the windows are made by.
        id display = [NSClassFromString(@"NSDisplay") performSelector: NSSelectorFromString(@"currentDisplay")];
        BOOL wayland = [NSStringFromClass([display class]) isEqualToString: @"WaylandDisplay"];
        if (!wayland && ![NSStringFromClass([display class]) isEqualToString: @"X11Display"]) {
            printf("SKIP: neither the X11 nor the Wayland backend\n");
            return 0;
        }

        typedef int ConnectionID;
        typedef unsigned WindowID;
        ConnectionID (*mainConnection)(void) = dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
        CGError (*getWindowBounds)(ConnectionID, WindowID, CGRect *) = dlsym(RTLD_DEFAULT, "CGSGetWindowBounds");
        CGError (*moveWindow)(ConnectionID, WindowID, const CGPoint *) = dlsym(RTLD_DEFAULT, "CGSMoveWindow");
        CGError (*orderWindow)(ConnectionID, WindowID, int, WindowID) = dlsym(RTLD_DEFAULT, "CGSOrderWindow");
        void *(*nativeWindowForID)(ConnectionID, WindowID) = dlsym(RTLD_DEFAULT, "_CGSNativeWindowForID");
        CGError (*getWindowProperty)(ConnectionID, WindowID, CFStringRef, CFTypeRef *) =
                dlsym(RTLD_DEFAULT, "CGSGetWindowProperty");
        if (!mainConnection || !getWindowBounds || !moveWindow || !orderWindow || !nativeWindowForID) {
            printf("FAIL: window server functions missing\n");
            return 1;
        }
        ConnectionID cid = mainConnection();

        // A borderless window that cannot become key is not managed by the window manager: its
        // geometry is exactly what AppKit asked for.
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 320, 200)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setReleasedWhenClosed: NO];
        [window setTitle: @"cg-window-layering"];
        [window orderFront: nil];
        spin(0.5);

        CGWindowID number = (CGWindowID) [window windowNumber];
        CHECK(number != 0, "the window has a window number");
        NSDictionary *entry = listing(number);
        CHECK(entry != nil, "CGWindowListCopyWindowInfo() lists the window under its window number");
        CHECK([[entry objectForKey: (NSString *) kCGWindowOwnerPID] intValue] == getpid(),
              "the listing names this process as the owner");
        CHECK([[entry objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue], "the listing has the window on screen");
        CHECK([[entry objectForKey: (NSString *) kCGWindowName] isEqual: @"cg-window-layering"],
              "the listing has the title AppKit gave the window");
        CHECK(CGRectEqualToRect(boundsOf(entry), cgRectOfFrame([window frame])),
              "the listed bounds are the window's frame in CoreGraphics' space");
        CGRect bounds = CGRectNull;
        CHECK(getWindowBounds(cid, number, &bounds) == kCGErrorSuccess &&
                      CGRectEqualToRect(bounds, boundsOf(entry)),
              "CGSGetWindowBounds() answers for the window number");
        CHECK(nativeWindowForID(cid, number) != NULL, "the window number names a CoreGraphics window with a native window");
        if (getWindowProperty != NULL) {
            CFTypeRef title = NULL;
            CHECK(getWindowProperty(cid, number, CFSTR("WindowTitle"), &title) == kCGErrorSuccess && title != NULL &&
                          [(NSString *) title isEqual: @"cg-window-layering"],
                  "the title lives in the CoreGraphics window");
            if (title != NULL)
                CFRelease(title);
        }

        // AppKit -> CoreGraphics
        [window setFrame: NSMakeRect(420, 340, 360, 220) display: YES];
        spin(0.3);
        CHECK(CGRectEqualToRect(boundsOf(listing(number)), cgRectOfFrame(NSMakeRect(420, 340, 360, 220))),
              "a frame set through AppKit is the window's bounds in the CoreGraphics listing");
        [window setFrameOrigin: NSMakePoint(500, 380)];
        spin(0.3);
        CHECK(CGRectEqualToRect(boundsOf(listing(number)), cgRectOfFrame(NSMakeRect(500, 380, 360, 220))),
              "a move through AppKit is seen in the listing, the size is kept");
        [window setTitle: @"cg-window-retitled"];
        CHECK([[listing(number) objectForKey: (NSString *) kCGWindowName] isEqual: @"cg-window-retitled"],
              "a title set through AppKit is the listed name");
        [window setAlphaValue: 0.5];
        double alpha = [[listing(number) objectForKey: (NSString *) kCGWindowAlpha] doubleValue];
        CHECK(fabs(alpha - 0.5) < 0.01, "an alpha set through AppKit is the listed alpha");
        [window setAlphaValue: 1.0];
        alpha = [[listing(number) objectForKey: (NSString *) kCGWindowAlpha] doubleValue];
        CHECK(fabs(alpha - 1.0) < 0.01, "full alpha is listed as 1");

        if (!wayland) {
            // CoreGraphics -> AppKit
            CGPoint target = CGPointMake(260, 150);
            CHECK(moveWindow(cid, number, &target) == kCGErrorSuccess, "CGSMoveWindow() accepts the window number");
            NSRect expected = NSMakeRect(260, CGDisplayBounds(CGMainDisplayID()).size.height - 150 - 220, 360, 220);
            WAIT_FOR(NSEqualRects([window frame], expected));
            CHECK(NSEqualRects([window frame], expected), "a move through CoreGraphics is the window's AppKit frame");
            CHECK(CGRectEqualToRect(boundsOf(listing(number)), CGRectMake(260, 150, 360, 220)),
                  "and the listing agrees with it");
        } else {
            printf("SKIP: a Wayland compositor places the windows itself\n");
        }

        // showing and hiding
        [window orderOut: nil];
        WAIT_FOR(![[listing(number) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue]);
        CHECK(listing(number) != nil && ![[listing(number) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue],
              "an ordered out window is listed as off screen");
        [window orderFront: nil];
        WAIT_FOR([[listing(number) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue]);
        CHECK([[listing(number) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue],
              "an ordered in window is listed as on screen again");

        // Another window has another number, and both are listed.
        NSWindow *titled = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 500, 300, 200)
                                                       styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [titled setReleasedWhenClosed: NO];
        [titled setTitle: @"cg-window-titled"];
        [titled orderFront: nil];
        spin(0.7);
        CGWindowID titledNumber = (CGWindowID) [titled windowNumber];
        CHECK(titledNumber != 0 && titledNumber != number, "another window has another window number");
        CHECK([[listing(titledNumber) objectForKey: (NSString *) kCGWindowName] isEqual: @"cg-window-titled"] &&
                      listing(number) != nil,
              "both windows are listed under their numbers");
        CHECK(nativeWindowForID(cid, titledNumber) != NULL && nativeWindowForID(cid, titledNumber) != nativeWindowForID(cid, number),
              "each number names its own native window");
        // A closed window is not on screen.
        [titled close];
        WAIT_FOR(![[listing(titledNumber) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue]);
        CHECK(![[listing(titledNumber) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue],
              "a closed window is not on screen");
        [window close];
        WAIT_FOR(![[listing(number) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue]);
        CHECK(![[listing(number) objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue],
              "the other closed window is not on screen either");
    }
    printf("RESULT failures=%d\n", failures);
    return failures == 0 ? 0 : 1;
}
