/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// What a toplevel window of the UI layer (CGSWindow.h) shows of a title bar, who draws its frame, and who answers the
// pointer on the frame, on the Wayland backend and without AppKit (the program links only CoreGraphics and Foundation).
// Windows are made with each CGSToplevelTitlebarKind; one of them draws a frame of its own (a 6 point border and a 28 point
// title bar around a 300x200 content) and gives its layout to the window system, which then answers the pointer over the
// frame: the title bar moves the window, an edge resizes it, the close button reports a close request, and the content
// gets its mouse events as before. The program prints READY once the windows are shown, then, as the driver
// (coregraphics-wayland-toplevel-decorations.sh, or coregraphics-wayland-toplevel-decorations.py for KWin) presses the
// pointer, prints "CLOSE n" for each close request and "MOUSE down x y" for each left button press the content gets, and
// RESULT at the end. The driver reads the compositor's view of the windows.
// Usage: coregraphics-wayland-toplevel-decorations <directory>   (the program waits for the files go1 and go2 in it)
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSWindow.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

@protocol ToplevelWindow
- (void)setToplevelEventProc:(CGSToplevelEventProc)proc info:(void *)info;
- (CGError)setProperty:(CFStringRef)key value:(CFTypeRef)value;
- (CGError)orderWindow:(int)place relativeTo:(id)other;
- (CGError)setToplevelHints:(const CGSToplevelHints *)hints;
- (CGError)setToplevelTitlebarKind:(CGSToplevelTitlebarKind)kind;
- (CGSToplevelTitlebarKind)toplevelTitlebarKind;
- (CGError)setToplevelPrefersClientDecoration:(BOOL)prefers;
- (CGError)setToplevelClientDecorationLayout:(const CGSToplevelDecorationLayout *)layout;
- (BOOL)toplevelClientDecorationContainsPoint:(CGPoint)point;
- (CGError)beginToplevelMoveByWindowSystem;
- (CGError)drawImage:(CGImageRef)image atPoint:(CGPoint)origin;
- (unsigned)windowId;
@end

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

static int closeRequests;
static int configured, reportedClientDecorated;
static void *clientWindow;
static void draw(id<ToplevelWindow> window, size_t width, size_t height, double red);

static void record(CGSWindow *window, const CGSToplevelEvent *event, void *info) {
    // The window is drawn at the size the compositor chooses (a resize that the user makes is only shown once the
    // window has a buffer of that size).
    if (event->kind == kCGSToplevelEventConfigured && (void *) window == clientWindow) {
        printf("CONFIGURE %d %d\n", event->configure.width, event->configure.height);
        fflush(stdout);
    }
    if (event->kind == kCGSToplevelEventConfigured && (void *) window == clientWindow && event->configure.width > 0 &&
        event->configure.height > 0)
    {
        // After the window system has taken the size (this is called while it applies the configure).
        id<ToplevelWindow> target = (id<ToplevelWindow>) window;
        size_t width = event->configure.width, height = event->configure.height;
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{ draw(target, width, height, 0.8); });
    }
    if (event->kind == kCGSToplevelEventCloseRequested) {
        closeRequests++;
        printf("CLOSE %d\n", closeRequests);
        fflush(stdout);
    } else if (event->kind == kCGSToplevelEventConfigured) {
        configured++;
        if (event->configure.decorationReported)
            reportedClientDecorated = event->configure.clientDecorated;
    }
}

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    CGPoint location = CGEventGetLocation(event);
    printf("MOUSE %s %d %d\n", type == kCGEventLeftMouseDown ? "down" : "up", (int) location.x, (int) location.y);
    fflush(stdout);
    return event;
}

static void listen(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static void waitFor(const char *directory, const char *name) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    for (int i = 0; i < 3000 && access(path, F_OK) != 0; i++)
        listen(0.1);
}

static void draw(id<ToplevelWindow> window, size_t width, size_t height, double red) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, red, 0.5, 0.8, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    [window drawImage:image atPoint:CGPointZero];
    CGImageRelease(image);
}

static id<ToplevelWindow> make(id<ToplevelWindow> (*newToplevel)(const CGSToplevelAttributes *), const char *title,
                               CGSToplevelTitlebarKind kind, BOOL prefersClient, CGSize size) {
    CGSToplevelAttributes attributes = {CGRectMake(100, 100, size.width, size.height), false, false};
    id<ToplevelWindow> window = newToplevel(&attributes);
    if (window == nil)
        return nil;
    [window setToplevelEventProc:record info:NULL];
    [window setProperty:CFSTR("WindowTitle") value:[NSString stringWithUTF8String:title]];
    CGSToplevelHints hints = {kCGSToplevelKindNormal, true, true, false, nil};
    [window setToplevelHints:&hints];
    CHECK([window setToplevelTitlebarKind:kind] == 0, "the title bar kind is accepted");
    CHECK([window toplevelTitlebarKind] == kind, "the window tells the kind it was given");
    CHECK([window setToplevelPrefersClientDecoration:prefersClient] == 0, "the decoration preference is accepted");
    return window;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2)
            return 2;
        id<ToplevelWindow> (*newToplevel)(const CGSToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
        if (!newToplevel) {
            printf("FAIL: the toplevel window functions are missing\n");
            return 1;
        }
        id<ToplevelWindow> server = make(newToplevel, "wdeco-server", kCGSToplevelTitlebarStandard, NO, CGSizeMake(300, 200));
        if (server == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        id<ToplevelWindow> hidden = make(newToplevel, "wdeco-hidden", kCGSToplevelTitlebarHidden, NO, CGSizeMake(300, 200));
        // The frame of this window is the program's: 6 points of border around the content, a 28 point title bar above it,
        // and the buttons at 4, 24 and 44 points from the border, 18 points wide.
        CGSize full = CGSizeMake(300 + 12, 200 + 12 + 28);
        id<ToplevelWindow> client = make(newToplevel, "wdeco-client", kCGSToplevelTitlebarStandard, YES, full);
        clientWindow = client;
        CGSToplevelDecorationLayout layout = {
            .border = 6, .titleHeight = 28, .size = full, .resizable = true,
            .closeButton = CGRectMake(10, 6, 18, 28), .miniaturizeButton = CGRectMake(30, 6, 18, 28),
            .zoomButton = CGRectNull,
        };
        CHECK([client setToplevelClientDecorationLayout:&layout] == 0, "the frame layout is accepted");
        CHECK([client toplevelClientDecorationContainsPoint:CGPointMake(2, 100)], "a point on the left border is on the frame");
        CHECK([client toplevelClientDecorationContainsPoint:CGPointMake(150, 10)], "a point in the title bar is on the frame");
        CHECK([client toplevelClientDecorationContainsPoint:CGPointMake(150, full.height - 2)],
              "a point on the bottom border is on the frame");
        CHECK(![client toplevelClientDecorationContainsPoint:CGPointMake(150, 100)], "a point in the content is not");
        CHECK(![client toplevelClientDecorationContainsPoint:CGPointMake(6, 34)], "the content's corner is not");
        CHECK(![server toplevelClientDecorationContainsPoint:CGPointMake(2, 2)], "a window with no layout has no frame to hit");
        CHECK([server beginToplevelMoveByWindowSystem] != 0, "a move is refused while no button is down");

        CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask,
                                             tapCallback, NULL);
        CHECK(tap != NULL, "the event tap is made");
        if (tap != NULL) {
            CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
            CGEventTapEnable(tap, true);
        }
        for (id<ToplevelWindow> window in @[ (id) server, (id) hidden, (id) client ])
            [window orderWindow:1 relativeTo:nil];
        listen(1.0);
        // The first buffer maps a Wayland toplevel.
        draw(server, 300, 200, 0.2);
        draw(hidden, 300, 200, 0.4);
        draw(client, full.width, full.height, 0.8);
        listen(1.0);
        CHECK(configured >= 3, "the compositor configured the windows");
        printf("READY\n");
        fflush(stdout);

        // The driver presses the pointer on the frame and the content of the client's window.
        waitFor(argv[1], "go1");
        listen(0.5);
        printf("STAGE 1 close=%d\n", closeRequests);
        fflush(stdout);
        waitFor(argv[1], "go2");
        printf("RESULT failures=%d\n", failures);
        fflush(stdout);
    }
    return failures != 0;
}
