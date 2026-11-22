/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSWindow setOpaque:] on the X11 backend. A window that was made translucent has a 32-bit visual, which
// cannot change once it is mapped. Once the window is opaque again the backend sets _NET_WM_OPAQUE_REGION to
// cover it (an occlusion hint for a compositing manager, which may ignore it), keeps it matching the size, and
// removes it when the window stops being opaque. A window on the 24-bit visual has none. Needs an X session
// whose server offers a 32-bit visual; skipped on others. The property is read with the display's own Xlib. Build
// without ARC.
// Documented contract: https://developer.apple.com/documentation/appkit/nswindow/isopaque
// Property: _NET_WM_OPAQUE_REGION in the EWMH specification, https://specifications.freedesktop.org/wm-spec/latest/
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>

// NSDisplay is AppKit's private backend class; only what the test calls is declared.
@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
@end

@interface NSObject (X11Backend)
- (unsigned long) windowHandle;
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static void pump(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

// Xlib, reached through the process so the test needs no X11 headers.
typedef unsigned long (*InternAtomFunction)(void *, const char *, int);
typedef int (*GetPropertyFunction)(void *, unsigned long, unsigned long, long, long, int, unsigned long, unsigned long *,
                                   int *, unsigned long *, unsigned long *, unsigned char **);
typedef int (*FreeFunction)(void *);
typedef int (*GetGeometryFunction)(void *, unsigned long, unsigned long *, int *, int *, unsigned *, unsigned *,
                                   unsigned *, unsigned *);
typedef int (*SyncFunction)(void *, int);

// The number of values in _NET_WM_OPAQUE_REGION (0 when absent); the four of the first rectangle in values.
static unsigned long regionOf(void *xdisplay, unsigned long xwindow, long values[4]) {
    InternAtomFunction intern = dlsym(RTLD_DEFAULT, "XInternAtom");
    GetPropertyFunction getProperty = dlsym(RTLD_DEFAULT, "XGetWindowProperty");
    FreeFunction release = dlsym(RTLD_DEFAULT, "XFree");
    SyncFunction sync = dlsym(RTLD_DEFAULT, "XSync");
    if (!intern || !getProperty || !release || !sync) {
        printf("FAIL: Xlib is not available\n");
        failures++;
        return 0;
    }
    enum { XA_CARDINAL = 6 };
    unsigned long type = 0, count = 0, after = 0;
    int format = 0;
    unsigned char *data = NULL;
    sync(xdisplay, 0);
    getProperty(xdisplay, xwindow, intern(xdisplay, "_NET_WM_OPAQUE_REGION", 0), 0, 16, 0, XA_CARDINAL, &type, &format,
                &count, &after, &data);
    if (data != NULL) {
        for (int i = 0; i < 4 && i < (int) count; i++)
            values[i] = ((long *) data)[i];
        release(data);
    }
    return type == XA_CARDINAL && format == 32 ? count : 0;
}

// The depth of the window: 32 for the visual with an alpha channel, 24 without.
static unsigned depthOf(void *xdisplay, unsigned long xwindow) {
    GetGeometryFunction getGeometry = dlsym(RTLD_DEFAULT, "XGetGeometry");
    unsigned long root = 0;
    int x = 0, y = 0;
    unsigned width = 0, height = 0, border = 0, depth = 0;
    if (getGeometry)
        getGeometry(xdisplay, xwindow, &root, &x, &y, &width, &height, &border, &depth);
    return depth;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        id display = [NSDisplay currentDisplay];
        if (![NSStringFromClass([display class]) hasPrefix: @"X11"] || ![display respondsToSelector: @selector(display)]) {
            printf("SKIP: not the X11 backend\n");
            return 0;
        }
        void *xdisplay = [display performSelector: @selector(display)];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 120)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setOpaque: NO];
        [window setBackgroundColor: [NSColor clearColor]];
        [window orderFront: nil];
        pump(0.5);
        unsigned long xwindow = [[window platformWindow] windowHandle];
        long values[4] = {0};

        expect(regionOf(xdisplay, xwindow, values) == 0, "a translucent window has no opaque region");

        [window setBackgroundColor: [NSColor whiteColor]];
        [window setOpaque: YES];
        pump(0.3);
        unsigned long count = regionOf(xdisplay, xwindow, values);
        if (count == 0 && depthOf(xdisplay, xwindow) != 32)
            printf("SKIP: the window got the 24-bit visual, the server has no 32-bit one\n");
        else {
            expect(count == 4 && values[0] == 0 && values[1] == 0 && values[2] > 0 && values[3] > 0,
                   "an opaque window with an alpha channel covers all of itself");
            long width = values[2];

            [window setContentSize: NSMakeSize(300, 200)];
            pump(0.5);
            regionOf(xdisplay, xwindow, values);
            expect(values[2] > width, "the region follows a resize");

            [window setOpaque: NO];
            pump(0.3);
            expect(regionOf(xdisplay, xwindow, values) == 0, "a window that stops being opaque loses the region");
        }
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures ? 1 : 0;
}
