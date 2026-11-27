/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A toplevel window of the UI layer (CGSWindow.h) on the Wayland backend, without AppKit (the program links only
// CoreGraphics and Foundation): the window is made, titled, given size limits and hints, shown, drawn into, hidden
// and shown again, and the program records what the window system reports of it. The driver,
// coregraphics-wayland-toplevel-events.sh, checks from the compositor's side that the window is a toplevel with the
// title, that it comes and goes with the program's calls, and asks it to close. The program prints READY, then waits
// for the files go1 to go3 in the directory it is given.
// Usage: coregraphics-wayland-toplevel-events <directory>
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
- (CGError)setToplevelMinimumSize:(CGSize)minimum maximumSize:(CGSize)maximum;
- (CGError)setToplevelDecorated:(BOOL)decorated;
- (CGError)drawImage:(CGImageRef)image atPoint:(CGPoint)origin;
- (CGRect)toplevelFrame;
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

#define MAX_EVENTS 256
static CGSToplevelEvent heard[MAX_EVENTS];
static int heardCount;
static int mainThreadOnly = 1;
static int willShowBeforeConfigure = 1;

static void record(CGSWindow *window, const CGSToplevelEvent *event, void *info) {
    if (![NSThread isMainThread])
        mainThreadOnly = 0;
    if (event->kind == kCGSToplevelEventConfigured && heardCount == 0)
        willShowBeforeConfigure = 0;
    if (heardCount < MAX_EVENTS)
        heard[heardCount++] = *event;
}

static void listen(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static void waitFor(const char *directory, const char *name) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    for (int i = 0; i < 1200 && access(path, F_OK) != 0; i++) {
        listen(0.1);
    }
}

static int count(int kind) {
    int n = 0;
    for (int i = 0; i < heardCount; i++)
        n += heard[i].kind == kind;
    return n;
}

static void draw(id<ToplevelWindow> window, size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 0.2, 0.5, 0.8, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    [window drawImage:image atPoint:CGPointZero];
    CGImageRelease(image);
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
        CGSToplevelAttributes attributes = {CGRectMake(300, 400, 320, 240), false, false};
        id<ToplevelWindow> window = newToplevel(&attributes);
        if (window == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        CHECK([window windowId] != 0, "the window has a number");
        CGRect frame = [window toplevelFrame];
        CHECK(CGRectEqualToRect(frame, attributes.frame), "the window reports the frame it was given");
        [window setToplevelEventProc:record info:NULL];
        [window setProperty:CFSTR("WindowTitle") value:@"tl-events-wl"];
        CGSToplevelHints hints = {kCGSToplevelKindNormal, true, true, false, nil};
        CHECK([window setToplevelHints:&hints] == 0, "hints are accepted");
        CHECK([window setToplevelMinimumSize:CGSizeMake(100, 80) maximumSize:CGSizeMake(0, 0)] == 0,
              "size limits are accepted");
        CHECK([window setToplevelDecorated:YES] == 0, "the decoration mode is accepted");
        CHECK([window orderWindow:1 relativeTo:nil] == 0, "the window is shown");
        listen(1.0);
        CHECK(count(kCGSToplevelEventWillShow) == 1, "the window tells it is about to be shown, once");
        CHECK(willShowBeforeConfigure, "the objects of the window are made before the compositor configures them");
        CHECK(count(kCGSToplevelEventConfigured) >= 1, "the compositor's configure of the role is reported");
        // The first buffer maps a Wayland toplevel.
        draw(window, 320, 240);
        listen(0.5);
        printf("READY\n");
        fflush(stdout);

        // The driver asks the compositor to close the window: a request that is reported once.
        waitFor(argv[1], "go1");
        listen(1.0);
        CHECK(count(kCGSToplevelEventCloseRequested) == 1, "a close request is reported once");
        CHECK(mainThreadOnly, "the events come on the main thread");
        heardCount = 0;
        printf("STAGE 1\n");
        fflush(stdout);

        // The window is hidden: the compositor sees it go.
        waitFor(argv[1], "go2");
        CHECK([window orderWindow:0 relativeTo:nil] == 0, "the window is hidden");
        listen(0.5);
        printf("STAGE 2\n");
        fflush(stdout);

        // And shown again: the objects are made anew, and the contents are drawn again.
        waitFor(argv[1], "go3");
        CHECK([window orderWindow:1 relativeTo:nil] == 0, "the window is shown again");
        listen(1.0);
        CHECK(count(kCGSToplevelEventWillShow) == 1, "a window that is shown again tells so again");
        CHECK(count(kCGSToplevelEventConfigured) >= 1, "the compositor configures the new role");
        draw(window, 320, 240);
        listen(0.5);
        printf("STAGE 3\n");
        fflush(stdout);
        waitFor(argv[1], "go4");
        [window setToplevelEventProc:NULL info:NULL];
    }
    printf("RESULT failures=%d\n", failures);
    fflush(stdout);
    return failures == 0 ? 0 : 1;
}
