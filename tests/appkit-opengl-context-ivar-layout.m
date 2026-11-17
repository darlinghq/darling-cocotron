// Copyright (C) 2026 Lubos Dolezel
//
// On the legacy (32-bit) Objective-C ABI code compiled against the system
// headers reads NSOpenGLContext's CGL context straight from its instance
// variable (the header's _contextAuxiliary, the third word of the object, as
// libSDL 1.2's Quartz driver does for CGLSetFullScreen). The word has to hold
// the context -CGLContextObj returns. Only meaningful on i386; elsewhere the
// instance variable is accessed through its own offset and the test passes.
#import <AppKit/AppKit.h>
#include <OpenGL/OpenGL.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSOpenGLPixelFormatAttribute attrs[] = {NSOpenGLPFAColorSize, 24, 0};
        NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes: attrs];
        NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat: format shareContext: nil];
        if (context == nil) {
            printf("SKIP: no OpenGL context\n");
            return 0;
        }
        void *cgl = [context CGLContextObj];
        if (cgl == NULL) {
            printf("FAIL: CGLContextObj is NULL\n");
            return 1;
        }
#if !__LP64__
        void *slot = *(void **) ((char *) context + 8);
        if (slot != cgl) {
            printf("FAIL: word at offset 8 is %p, CGLContextObj is %p\n", slot, cgl);
            return 1;
        }
        if (class_getInstanceSize([NSOpenGLContext class]) != 12) {
            printf("FAIL: instance size %zu, expected 12\n", class_getInstanceSize([NSOpenGLContext class]));
            return 1;
        }
#endif
        [context release];
        [format release];
    }
    printf("OK\n");
    return 0;
}
