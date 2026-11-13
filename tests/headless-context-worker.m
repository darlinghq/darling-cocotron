#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static NSOpenGLContext *context;
static int finished;
static int result;

static void *worker(void *unused) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [context makeCurrentContext];
    if ([NSOpenGLContext currentContext] != context ||
        CGLGetCurrentContext() != [context CGLContextObj] ||
        glGetString(GL_VERSION) == NULL)
        result = 3;
    [NSOpenGLContext clearCurrentContext];
    if ([NSOpenGLContext currentContext] != nil || CGLGetCurrentContext() != NULL)
        result = 4;
    [pool drain];
    __sync_lock_test_and_set(&finished, 1);
    return NULL;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    [NSScreen screens];
    NSOpenGLPixelFormatAttribute attributes[] = {0};
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    [format release];
    if (context == nil || [context CGLContextObj] == NULL) return 1;
    pthread_t thread;
    if (pthread_create(&thread, NULL, worker, NULL) != 0) return 2;
    // Deliberately do not pump the main run loop. A context without a view
    // has no window geometry that needs synchronous work on this thread.
    for (int i = 0; i < 500 && !__sync_add_and_fetch(&finished, 0); i++)
        usleep(10000);
    if (!__sync_add_and_fetch(&finished, 0)) {
        fprintf(stderr, "Viewless worker context blocked waiting for main\n");
        _exit(5);
    }
    pthread_join(thread, NULL);
    if ([NSOpenGLContext currentContext] != nil || CGLGetCurrentContext() != NULL)
        result = 6;
    [context release];
    [pool drain];
    if (!result) puts("Viewless worker context passed without a main run loop");
    return result;
}
