/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSOpenGLContext update] and wantsBestResolutionOpenGLSurface.
//
// Documented: update must be called when the view is resized; a view's
// wantsBestResolutionOpenGLSurface defaults to YES for programs linked against
// macOS 10.15 or later and to NO otherwise; NSOpenGLView.h says that with the
// property YES, glViewport is called automatically before update and reshape.
//
// test_quirk_update_resets_viewport: observed (macOS 26.7.3 x86_64, and Mac
// OS X 10.14.4 x86_64 and i386 with the property set to YES) and not documented:
// -[NSOpenGLContext update] sets the current viewport to (0, 0, w, h) of the new
// drawable when the view's property is YES, also over a viewport the
// application set with glViewport, and leaves it alone when it is NO; the
// scissor box is not touched; calling CGLUpdateContext alone does not reset.
// It holds for a plain NSView and for an NSOpenGLView, and the property is read
// when update is called. A context another thread holds gets the reset when
// a thread makes it current again.
// Needs a display and an OpenGL driver. Prints FAIL lines; exit status 0 on PASS.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

extern uint32_t dyld_get_program_sdk_version(void);
#define SDK_10_15 0x000a0f00

static int g_failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } } while (0)

static void spin(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]];
}

static int viewportIs(const char *step, int x, int y, int w, int h) {
    GLint vp[4];
    glGetIntegerv(GL_VIEWPORT, vp);
    int ok = vp[0] == x && vp[1] == y && vp[2] == w && vp[3] == h;
    if (!ok)
        printf("FAIL %s: viewport %d,%d,%d,%d expected %d,%d,%d,%d\n", step, vp[0], vp[1], vp[2], vp[3], x, y, w, h);
    return ok;
}

// The drawable's size in pixels.
static void pixelSize(NSView *view, int *w, int *h) {
    NSSize s = [view convertSizeToBacking: [view bounds].size];
    *w = (int) s.width;
    *h = (int) s.height;
}

typedef struct {
    NSWindow *win;
    NSView *view;
    NSOpenGLContext *ctx;
} Rig;

static Rig makeRig(BOOL glView, NSOpenGLPixelFormat *pf) {
    Rig r;
    r.win = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                        styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                          backing: NSBackingStoreBuffered
                                            defer: NO];
    if (glView) {
        r.view = [[NSOpenGLView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300) pixelFormat: pf];
        r.ctx = [(NSOpenGLView *) r.view openGLContext];
    } else {
        r.view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        r.ctx = [[NSOpenGLContext alloc] initWithFormat: pf shareContext: nil];
    }
    return r;
}

static void showRig(Rig *r, BOOL glView) {
    [r->win setContentView: r->view];
    [r->win makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    spin(0.5);
    if (!glView)
        [r->ctx setView: r->view];
    [r->ctx makeCurrentContext];
}

// Resizes the window, lets the view callbacks run, and updates the context
// explicitly (an NSOpenGLView has already done so itself).
static void resizeAndUpdate(Rig *r, int w, int h) {
    [r->win setContentSize: NSMakeSize(w, h)];
    spin(0.5);
    [r->ctx makeCurrentContext];
}

static void scenario(const char *name, BOOL glView, int property /* -1 default, 0 no, 1 yes */,
                     NSOpenGLPixelFormat *pf) {
    Rig r = makeRig(glView, pf);
    if (property >= 0)
        [r.view setWantsBestResolutionOpenGLSurface: property];
    BOOL expectDefault = dyld_get_program_sdk_version() >= SDK_10_15;
    BOOL expectReset = property >= 0 ? property == 1 : expectDefault;
    showRig(&r, glView);
    if (property < 0)
        CHECK([r.view wantsBestResolutionOpenGLSurface] == expectDefault);
    else
        CHECK([r.view wantsBestResolutionOpenGLSurface] == (property == 1));

    glViewport(10, 10, 200, 100);
    GLint scissorBefore[4], scissorAfter[4];
    glGetIntegerv(GL_SCISSOR_BOX, scissorBefore);
    resizeAndUpdate(&r, 800, 600);
    [r.ctx update];
    int w, h;
    pixelSize(r.view, &w, &h);
    printf("%s: drawable %dx%d expect reset %d\n", name, w, h, expectReset);
    CHECK(w >= 800 && h >= 600);
    CHECK(expectReset ? viewportIs(name, 0, 0, w, h) : viewportIs(name, 10, 10, 200, 100));
    glGetIntegerv(GL_SCISSOR_BOX, scissorAfter);
    CHECK(scissorBefore[2] == scissorAfter[2] && scissorBefore[3] == scissorAfter[3]);

    // The property is read when update is called.
    if (property >= 0) {
        [r.view setWantsBestResolutionOpenGLSurface: !property];
        glViewport(5, 5, 50, 50);
        resizeAndUpdate(&r, 640, 480);
        [r.ctx update];
        pixelSize(r.view, &w, &h);
        CHECK(property == 1 ? viewportIs(name, 5, 5, 50, 50) : viewportIs(name, 0, 0, w, h));
    }
    [r.win orderOut: nil];
}

static NSOpenGLContext *g_ctx;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_cond = PTHREAD_COND_INITIALIZER;
static int g_step;
static GLint g_threadViewport[4];

static void waitStep(int step) {
    pthread_mutex_lock(&g_lock);
    while (g_step < step)
        pthread_cond_wait(&g_cond, &g_lock);
    pthread_mutex_unlock(&g_lock);
}
static void setStep(int step) {
    pthread_mutex_lock(&g_lock);
    g_step = step;
    pthread_cond_broadcast(&g_cond);
    pthread_mutex_unlock(&g_lock);
}

// Takes the context and sets an explicit viewport; after the main thread
// resized and updated, takes it again and reads the viewport.
static void *renderThread(void *arg) {
    @autoreleasepool {
        [g_ctx makeCurrentContext];
        glViewport(10, 10, 200, 100);
        [NSOpenGLContext clearCurrentContext];
        setStep(1);
        waitStep(2);
        [g_ctx makeCurrentContext];
        glGetIntegerv(GL_VIEWPORT, g_threadViewport);
        [NSOpenGLContext clearCurrentContext];
        setStep(3);
    }
    return NULL;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSOpenGLPixelFormatAttribute attrs[] = {NSOpenGLPFADoubleBuffer, NSOpenGLPFAColorSize, 24, 0};
        NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes: attrs];
        if (pf == nil) {
            printf("SKIP: no OpenGL pixel format\n");
            return 0;
        }

        printf("linked SDK version 0x%x\n", dyld_get_program_sdk_version());
        // test_quirk_update_resets_viewport
        scenario("plain view, property YES", NO, 1, pf);
        scenario("plain view, property NO", NO, 0, pf);
        scenario("plain view, default for the linked SDK", NO, -1, pf);
        scenario("NSOpenGLView, property YES", YES, 1, pf);
        scenario("NSOpenGLView, property NO", YES, 0, pf);
        scenario("NSOpenGLView, default for the linked SDK", YES, -1, pf);

        // CGLUpdateContext alone does not reset the viewport.
        {
            Rig r = makeRig(NO, pf);
            [r.view setWantsBestResolutionOpenGLSurface: YES];
            showRig(&r, NO);
            glViewport(10, 10, 200, 100);
            resizeAndUpdate(&r, 640, 480);
            CHECK(CGLUpdateContext([r.ctx CGLContextObj]) == kCGLNoError);
            CHECK(viewportIs("CGLUpdateContext only", 10, 10, 200, 100));
            [r.win orderOut: nil];
        }

        // A context another thread holds, updated from this one.
        {
            Rig r = makeRig(NO, pf);
            [r.view setWantsBestResolutionOpenGLSurface: YES];
            showRig(&r, NO);
            g_ctx = r.ctx;
            [NSOpenGLContext clearCurrentContext];
            pthread_t thread;
            pthread_create(&thread, NULL, renderThread, NULL);
            waitStep(1);
            [r.win setContentSize: NSMakeSize(500, 350)];
            spin(0.5);
            [r.ctx update];
            setStep(2);
            waitStep(3);
            pthread_join(thread, NULL);
            int w, h;
            pixelSize(r.view, &w, &h);
            CHECK(g_threadViewport[0] == 0 && g_threadViewport[1] == 0 && g_threadViewport[2] == w &&
                  g_threadViewport[3] == h);
            if (g_threadViewport[2] != w)
                printf("FAIL other thread: viewport %d,%d,%d,%d expected 0,0,%d,%d\n", g_threadViewport[0],
                       g_threadViewport[1], g_threadViewport[2], g_threadViewport[3], w, h);
            [r.win orderOut: nil];
        }
    }
    printf(g_failures ? "FAIL\n" : "PASS\n");
    return g_failures ? 1 : 0;
}
