/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// What the window system reports of a toplevel window of the UI layer (CGSWindow.h, -setToplevelEventProc:info:),
// without AppKit (the program links only CoreGraphics and Foundation): the window is made, shown and given a
// handler, and the program records what it is told while the driver, coregraphics-x11-toplevel-events.sh, moves
// and sizes the window, makes the X server ask for a repaint of part of it, and asks it to close. The program
// prints READY, then waits for the files go1 to go4 in the directory it is given, listens for a second and
// checks what it heard. Usage: coregraphics-x11-toplevel-events <directory>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

// CGSToplevelEvent of CGSWindow.h
enum {
    EventCloseRequested = 1,
    EventFrameChanged = 6,
    EventExposed = 7,
};
typedef struct {
    int kind;
    CGRect rect;
    bool resized;
    CGFloat oldScale;
} ToplevelEvent;
typedef void (*ToplevelEventProc)(id window, const ToplevelEvent *event, void *info);

typedef struct {
    CGRect frame;
    bool unmanaged;
    bool translucent;
} ToplevelAttributes;

@protocol ToplevelWindow
- (void)setToplevelEventProc:(ToplevelEventProc)proc info:(void *)info;
- (CGError)setProperty:(CFStringRef)key value:(CFTypeRef)value;
- (CGError)orderWindow:(int)place relativeTo:(id)other;
- (CGError)setToplevelFrame:(CGRect)frame;
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
static ToplevelEvent heard[MAX_EVENTS];
static int heardCount;
static int mainThreadOnly = 1;

static void record(id window, const ToplevelEvent *event, void *info) {
    if (![NSThread isMainThread])
        mainThreadOnly = 0;
    if (heardCount < MAX_EVENTS)
        heard[heardCount++] = *event;
}

static void listen(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static void waitFor(const char *directory, const char *name) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", directory, name);
    for (int i = 0; i < 1200 && access(path, F_OK) != 0; i++)
        usleep(100000);
}

static int count(int kind) {
    int n = 0;
    for (int i = 0; i < heardCount; i++)
        n += heard[i].kind == kind;
    return n;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2)
            return 2;
        id<ToplevelWindow> (*newToplevel)(const ToplevelAttributes *) = dlsym(RTLD_DEFAULT, "_CGSNewToplevelWindow");
        if (!newToplevel) {
            printf("FAIL: the toplevel window functions are missing\n");
            return 1;
        }
        ToplevelAttributes attributes = {CGRectMake(300, 400, 320, 240), false, false};
        id<ToplevelWindow> window = newToplevel(&attributes);
        if (window == nil) {
            printf("SKIP: this window system makes no toplevel windows\n");
            return 0;
        }
        if (![window respondsToSelector:@selector(setToplevelEventProc:info:)]) {
            printf("FAIL: the window has no event handler\n");
            printf("RESULT failures=1\n");
            return 1;
        }
        [window setToplevelEventProc:record info:NULL];
        [window setProperty:CFSTR("WindowTitle") value:@"tl-events"];
        [window orderWindow:1 relativeTo:nil];
        listen(1.0);
        heardCount = 0;
        CGRect first = [window toplevelFrame];
        CHECK(CGSizeEqualToSize(first.size, attributes.frame.size), "the window reports the size it was given");
        printf("READY\n");
        fflush(stdout);

        // The user moves the window: its frame is reported, not as a resize.
        waitFor(argv[1], "go1");
        listen(1.0);
        CGRect moved = [window toplevelFrame];
        CHECK(count(EventFrameChanged) > 0, "a move is reported");
        CHECK(!CGPointEqualToPoint(moved.origin, first.origin) && CGSizeEqualToSize(moved.size, first.size),
              "the window has moved without changing its size");
        BOOL anyResize = NO, reportsFrame = NO;
        for (int i = 0; i < heardCount; i++) {
            if (heard[i].kind != EventFrameChanged)
                continue;
            anyResize |= heard[i].resized;
            reportsFrame |= CGRectEqualToRect(heard[i].rect, moved);
        }
        CHECK(!anyResize, "a move is not reported as a resize");
        CHECK(reportsFrame, "the report carries the new frame");
        heardCount = 0;
        printf("STAGE 1\n");
        fflush(stdout);

        // The window is resized.
        waitFor(argv[1], "go2");
        listen(1.0);
        CGRect sized = [window toplevelFrame];
        anyResize = NO;
        for (int i = 0; i < heardCount; i++)
            anyResize |= heard[i].kind == EventFrameChanged && heard[i].resized &&
                         CGSizeEqualToSize(heard[i].rect.size, sized.size);
        CHECK(sized.size.width == 400 && sized.size.height == 300, "the window has the new size");
        CHECK(anyResize, "a resize is reported as one, with the new size");
        heardCount = 0;
        printf("STAGE 2\n");
        fflush(stdout);

        // The window system asks for the part (10, 20) 50 by 40 to be painted again.
        waitFor(argv[1], "go3");
        listen(1.0);
        BOOL exposed = NO;
        for (int i = 0; i < heardCount; i++)
            exposed |= heard[i].kind == EventExposed &&
                       CGRectEqualToRect(heard[i].rect, CGRectMake(10, 20, 50, 40));
        CHECK(exposed, "the repaint of an area is reported with the area, in points from the top left");
        heardCount = 0;
        printf("STAGE 3\n");
        fflush(stdout);

        // The user closes the window: asked once, and the window stays.
        waitFor(argv[1], "go4");
        listen(1.0);
        CHECK(count(EventCloseRequested) == 1, "a close request is reported once");
        CHECK(mainThreadOnly, "the events come on the main thread");
        [window setToplevelEventProc:NULL info:NULL];
        heardCount = 0;
        printf("STAGE 4\n");
        fflush(stdout);

        // Without a handler nothing is delivered (the driver asks to close the window again).
        waitFor(argv[1], "go5");
        listen(0.7);
        CHECK(heardCount == 0, "a window without a handler reports nothing");
        printf("STAGE 5\n");
    }
    printf("RESULT failures=%d\n", failures);
    fflush(stdout);
    return failures == 0 ? 0 : 1;
}
