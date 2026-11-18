/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// An NSOpenGLContext attached to a window's view is made current, cleared and
// flushed from a CVDisplayLink callback thread, under CGLLockContext. On Mac OS X
// this works on every display backend; the context has to be current on that
// thread, the drawn pixel has to read back, and the flush has to succeed.
#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>
#import <OpenGL/gl.h>
#include <OpenGL/OpenGL.h>
#include <stdio.h>
#include <stdlib.h>

static NSOpenGLContext *context;
static volatile int frames, currentOnThread, redPixels, flushed;

static CVReturn callback(CVDisplayLinkRef link, const CVTimeStamp *now, const CVTimeStamp *out,
                         CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *info) {
    @autoreleasepool {
        CGLContextObj cgl = [context CGLContextObj];
        CGLLockContext(cgl);
        [context makeCurrentContext];
        if (CGLGetCurrentContext() == cgl) {
            currentOnThread++;
            glClearColor(1, 0, 0, 1);
            glClear(GL_COLOR_BUFFER_BIT);
            GLubyte pixel[4] = {0};
            glReadPixels(2, 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
            if (pixel[0] > 250 && pixel[1] < 5 && pixel[2] < 5)
                redPixels++;
            [context flushBuffer];
            flushed++;
        }
        CGLUnlockContext(cgl);
        frames++;
    }
    return kCVReturnSuccess;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSOpenGLPixelFormatAttribute attributes[] = {NSOpenGLPFADoubleBuffer, NSOpenGLPFAColorSize, 24, 0};
        NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes: attributes];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSOpenGLView *view = [[NSOpenGLView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200) pixelFormat: format];
        [window setContentView: view];
        [window makeKeyAndOrderFront: nil];
        context = [view openGLContext];
        // The application draws from the link's thread only; the main thread merely runs.
        for (int i = 0; i < 20; i++)
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];

        CVDisplayLinkRef link;
        CVDisplayLinkCreateWithActiveCGDisplays(&link);
        CVDisplayLinkSetOutputCallback(link, callback, NULL);
        CVDisplayLinkStart(link);
        for (int i = 0; i < 60 && frames < 15; i++)
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
        // Let the main thread present what was swapped before it is looked at.
        const char *hold = getenv("RENDER_THREAD_HOLD");
        if (hold != NULL)
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: atof(hold)]];
        CVDisplayLinkStop(link);
        CVDisplayLinkRelease(link);

        int failures = 0;
        printf("frames=%d current=%d red=%d flushed=%d\n", frames, currentOnThread, redPixels, flushed);
        if (frames < 5) { fprintf(stderr, "FAIL: display link produced %d frames\n", frames); failures++; }
        if (currentOnThread != frames) { fprintf(stderr, "FAIL: context current on the link thread in %d of %d frames\n", currentOnThread, frames); failures++; }
        if (redPixels != currentOnThread) { fprintf(stderr, "FAIL: cleared pixel read back red in %d of %d frames\n", redPixels, currentOnThread); failures++; }
        if (flushed != currentOnThread) { fprintf(stderr, "FAIL: flushed %d of %d frames\n", flushed, currentOnThread); failures++; }
        puts(failures ? "FAIL" : "PASS");
        return failures ? 1 : 0;
    }
}
