// Copyright (C) 2026 Lubos Dolezel
//
// A fullscreen CGL context (CGLSetFullScreenOnDisplay) draws to a display with
// no NSWindow of the application's own. The pointer moving over the display
// still reaches the application: -[NSApplication nextEventMatchingMask:...]
// returns NSMouseMoved events whose window is nil and whose locationInWindow
// is therefore in screen coordinates (origin at the main display's lower-left
// corner), +[NSEvent mouseLocation] agrees, and CGGetLastMouseDelta() reports
// the motion since its previous call (documented as the change in mouse
// position since the last mouse movement event; here every call takes what
// has built up, so one call per event or per batch both add up).
// The pointer is moved with CGWarpMouseCursorPosition, which the window
// system reports to the display like physical motion.
//
// Needs a window system (X11 backend) and a host EGL driver; the display is
// not captured and the cursor is moved. Skipped without a fullscreen-capable
// pixel format.
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <OpenGL/OpenGL.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

extern CGLError CGLSetFullScreenOnDisplay(CGLContextObj ctx, GLuint display_mask);
extern CGOpenGLDisplayMask CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID display);

static int g_failures = 0;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } } while (0)
#define CHECK_EQ(a, b) do { long _a = (long) (a), _b = (long) (b); if (_a != _b) { printf("FAIL %d: %s = %ld, expected %ld\n", __LINE__, #a, _a, _b); g_failures++; } } while (0)

static void on_alarm(int sig) {
    (void) sig;
    printf("FAIL: timed out\n");
    fflush(stdout);
    _exit(1);
}

// The last mouse-moved event in the queue after the pointer has been moved, or
// nil. The window system reports the warp asynchronously.
static NSEvent *lastMotion(void) {
    NSEvent *last = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 3.0];
    int quiet = 0;
    while ([deadline timeIntervalSinceNow] > 0 && quiet < 3) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event == nil) {
            if (last != nil)
                quiet++;
            continue;
        }
        quiet = 0;
        if ([event type] == NSMouseMoved)
            last = event;
    }
    return last;
}

static NSEvent *warpAndWait(CGFloat x, CGFloat y) {
    CGWarpMouseCursorPosition(CGPointMake(x, y));
    return lastMotion();
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGALRM, on_alarm);
    alarm(90);

    @autoreleasepool {
        [NSApplication sharedApplication];

        // No motion has been reported yet.
        int32_t dx = 99, dy = 99;
        CGGetLastMouseDelta(&dx, &dy);
        CHECK_EQ(dx, 0);
        CHECK_EQ(dy, 0);
        // Either output may be NULL.
        CGGetLastMouseDelta(NULL, &dy);
        CGGetLastMouseDelta(&dx, NULL);
        CGGetLastMouseDelta(NULL, NULL);

        CGDirectDisplayID display = CGMainDisplayID();
        CGOpenGLDisplayMask mask = CGDisplayIDToOpenGLDisplayMask(display);
        CGLPixelFormatAttribute attrs[] = {kCGLPFAFullScreen, kCGLPFADoubleBuffer,
                                           kCGLPFADisplayMask, (CGLPixelFormatAttribute) mask, 0};
        CGLPixelFormatObj format = NULL;
        GLint count = 0;
        if (CGLChoosePixelFormat(attrs, &format, &count) != kCGLNoError || format == NULL) {
            printf("SKIP: no fullscreen pixel format\n");
            return 0;
        }
        CGLContextObj context = NULL;
        if (CGLCreateContext(format, NULL, &context) != kCGLNoError ||
            CGLSetFullScreenOnDisplay(context, mask) != kCGLNoError) {
            printf("SKIP: no fullscreen context\n");
            return 0;
        }

        CGRect bounds = CGDisplayBounds(display);
        CGFloat height = bounds.size.height;

        // The first position: the event is located at the pointer in screen
        // coordinates and has no window.
        NSEvent *event = warpAndWait(bounds.origin.x + 200, bounds.origin.y + 150);
        CHECK(event != nil);
        if (event != nil) {
            CHECK(event.window == nil);
            CHECK(fabs(event.locationInWindow.x - (bounds.origin.x + 200)) <= 1.0);
            CHECK(fabs(event.locationInWindow.y - (bounds.origin.y + height - 150)) <= 1.0);
            NSPoint mouse = [NSEvent mouseLocation];
            CHECK(fabs(mouse.x - event.locationInWindow.x) <= 1.0);
            CHECK(fabs(mouse.y - event.locationInWindow.y) <= 1.0);
        }
        // Whatever built up so far is not what the next move adds.
        CGGetLastMouseDelta(&dx, &dy);

        // A move by (+30, -20) in the display's y-down space: the event's
        // deltas have y growing downwards, as CGGetLastMouseDelta does.
        event = warpAndWait(bounds.origin.x + 230, bounds.origin.y + 130);
        CHECK(event != nil);
        if (event != nil) {
            CHECK(event.window == nil);
            CHECK(fabs(event.deltaX - 30.0) <= 1.0);
            CHECK(fabs(event.deltaY - (-20.0)) <= 1.0);
            CHECK(fabs(event.locationInWindow.x - (bounds.origin.x + 230)) <= 1.0);
            CHECK(fabs(event.locationInWindow.y - (bounds.origin.y + height - 130)) <= 1.0);
        }
        CGGetLastMouseDelta(&dx, &dy);
        CHECK(abs(dx - 30) <= 1);
        CHECK(abs(dy - (-20)) <= 1);
        // A call takes what was reported: the next one has nothing.
        CGGetLastMouseDelta(&dx, &dy);
        CHECK_EQ(dx, 0);
        CHECK_EQ(dy, 0);

        // Two moves between two calls add up.
        CGWarpMouseCursorPosition(CGPointMake(bounds.origin.x + 240, bounds.origin.y + 130));
        (void) lastMotion();
        event = warpAndWait(bounds.origin.x + 240, bounds.origin.y + 160);
        CHECK(event != nil);
        CGGetLastMouseDelta(&dx, &dy);
        CHECK(abs(dx - 10) <= 1);
        CHECK(abs(dy - 30) <= 1);

        // With the mouse disassociated from the cursor the application still
        // gets events for the display; they have no window either.
        CHECK_EQ(CGAssociateMouseAndMouseCursorPosition(false), kCGErrorSuccess);
        event = warpAndWait(bounds.origin.x + 300, bounds.origin.y + 300);
        if (event != nil)
            CHECK(event.window == nil);
        CHECK_EQ(CGAssociateMouseAndMouseCursorPosition(true), kCGErrorSuccess);

        CGLClearDrawable(context);
        CGLDestroyContext(context);
        CGLDestroyPixelFormat(format);
    }

    if (g_failures == 0)
        printf("PASS\n");
    return g_failures != 0;
}
