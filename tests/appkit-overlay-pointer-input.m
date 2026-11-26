// CFLAGS: -framework Foundation -framework AppKit -framework ApplicationServices -framework OpenGL
// Copyright (C) 2026 Lubos Dolezel
//
// A fullscreen CGL context (CGLSetFullScreenOnDisplay) draws to a display with no NSWindow of the application's
// own. The pointer moving over the display still reaches the application: -[NSApplication
// nextEventMatchingMask:...] returns NSMouseMoved events whose window is nil and whose locationInWindow is
// therefore in screen coordinates (origin at the main display's lower-left corner), and CGGetLastMouseDelta()
// reports the motion since its previous call (documented as the change in mouse position since the last mouse
// movement event; here every call takes what has built up, so one call per event or per batch both add up).
//
// The pointer is moved by the window system's input (the driver scripts appkit-overlay-pointer-input-x11.sh
// with XTest and appkit-overlay-pointer-input-wayland.sh with a virtual pointer), not by the program: a warp of
// the cursor with CGWarpMouseCursorPosition() is not mouse motion and posts no mouse event (it only moves the
// cursor), so the program warps once and checks that no event arrives. The program prints READY and the display's
// bounds, then PHASE2 .. PHASE5 when it has seen what the driver did before, and ends with PASS or FAIL lines.
// Skipped (SKIP, exit 0) without a fullscreen-capable pixel format.
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
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

// Collects the mouse-moved events until the pointer is where the predicate says (or 15 seconds pass); all of
// them are returned in order.
static NSMutableArray *collectMotion(NSTimeInterval seconds, BOOL (^done)(NSArray *events)) {
    NSMutableArray *events = [NSMutableArray array];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0 && !(done != nil && done(events))) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if ([event type] == NSMouseMoved)
            [events addObject: event];
    }
    return events;
}

static BOOL at(NSEvent *event, CGFloat x, CGFloat y) {
    return event != nil && fabs(event.locationInWindow.x - x) <= 1.0 && fabs(event.locationInWindow.y - y) <= 1.0;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGALRM, on_alarm);
    alarm(60);

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
        // The program draws, as one that fills a display does (a Wayland toplevel is mapped by its first buffer).
        CGLSetCurrentContext(context);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        CGLFlushDrawable(context);

        CGRect bounds = CGDisplayBounds(display);
        CGFloat height = bounds.size.height;
        printf("READY %d %d %d %d\n", (int) bounds.origin.x, (int) bounds.origin.y, (int) bounds.size.width,
               (int) bounds.size.height);

        // The first position (200, 150) of the display: the event is located at the pointer in screen
        // coordinates and has no window.
        NSArray *moves = collectMotion(20, ^BOOL(NSArray *events) {
            return at([events lastObject], bounds.origin.x + 200, bounds.origin.y + height - 150);
        });
        NSEvent *event = [moves lastObject];
        CHECK(at(event, bounds.origin.x + 200, bounds.origin.y + height - 150));
        if (event != nil) {
            CHECK(event.window == nil);
            NSPoint mouse = [NSEvent mouseLocation];
            CHECK(fabs(mouse.x - event.locationInWindow.x) <= 1.0);
            CHECK(fabs(mouse.y - event.locationInWindow.y) <= 1.0);
        }
        // Whatever built up so far is not what the next move adds.
        CGGetLastMouseDelta(&dx, &dy);
        printf("PHASE2\n");

        // A move by (+30, -20) in the display's y-down space: the event's deltas have y growing downwards, as
        // CGGetLastMouseDelta does.
        moves = collectMotion(20, ^BOOL(NSArray *events) {
            return at([events lastObject], bounds.origin.x + 230, bounds.origin.y + height - 130);
        });
        event = [moves lastObject];
        CHECK(at(event, bounds.origin.x + 230, bounds.origin.y + height - 130));
        if (event != nil) {
            CHECK(event.window == nil);
            CHECK(fabs(event.deltaX - 30.0) <= 1.0);
            CHECK(fabs(event.deltaY - (-20.0)) <= 1.0);
        }
        CGGetLastMouseDelta(&dx, &dy);
        CHECK(abs(dx - 30) <= 1);
        CHECK(abs(dy - (-20)) <= 1);
        // A call takes what was reported: the next one has nothing.
        CGGetLastMouseDelta(&dx, &dy);
        CHECK_EQ(dx, 0);
        CHECK_EQ(dy, 0);
        printf("PHASE3\n");

        // Two moves between two calls add up: (+10, 0), then (0, +30).
        moves = collectMotion(20, ^BOOL(NSArray *events) {
            return at([events lastObject], bounds.origin.x + 240, bounds.origin.y + height - 160);
        });
        CHECK(at([moves lastObject], bounds.origin.x + 240, bounds.origin.y + height - 160));
        CGGetLastMouseDelta(&dx, &dy);
        CHECK(abs(dx - 10) <= 1);
        CHECK(abs(dy - 30) <= 1);
        printf("PHASE4\n");

        // A warp of the cursor is not mouse motion: it posts no mouse event and reports no delta. (The driver
        // does nothing in this phase.) The cursor is where the program put it for the program's own use.
        (void) collectMotion(0.5, nil);
        CGGetLastMouseDelta(&dx, &dy);
        CGWarpMouseCursorPosition(CGPointMake(bounds.origin.x + 300, bounds.origin.y + 300));
        moves = collectMotion(1.5, nil);
        CHECK_EQ([moves count], 0);
        CGGetLastMouseDelta(&dx, &dy);
        CHECK_EQ(dx, 0);
        CHECK_EQ(dy, 0);

        // With the mouse disassociated from the cursor the application still gets events for the display; they
        // have no window either, and carry the motion as deltas.
        CHECK_EQ(CGAssociateMouseAndMouseCursorPosition(false), kCGErrorSuccess);
        printf("PHASE5\n");
        moves = collectMotion(20, ^BOOL(NSArray *events) { return [events count] > 0; });
        double sumX = 0, sumY = 0;
        for (NSEvent *move in moves) {
            CHECK(move.window == nil);
            sumX += move.deltaX;
            sumY += move.deltaY;
        }
        CHECK([moves count] > 0);
        CHECK(fabs(sumX - 12) <= 1.5 && fabs(sumY - 5) <= 1.5);
        CHECK_EQ(CGAssociateMouseAndMouseCursorPosition(true), kCGErrorSuccess);

        CGLClearDrawable(context);
        CGLDestroyContext(context);
        CGLDestroyPixelFormat(format);
    }

    if (g_failures == 0)
        printf("PASS\n");
    return g_failures != 0;
}
