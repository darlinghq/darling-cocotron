// Copyright (C) 2026 Lubos Dolezel
//
// A CGL context wrapped with -initWithCGLContextObj: and attached to a view
// with -setView: draws into that view when it is made current with
// CGLSetCurrentContext() (not only with -makeCurrentContext) and presented
// with CGLFlushDrawable(). The context is made current on a worker thread,
// as threaded renderers do.
// Usage: nsopenglcontext-setview-cgl-current [ns]
//   with "ns" the context is made current through -makeCurrentContext instead
//   (control). The window shows solid red for about 20 s; the harness
//   nsopenglcontext-setview-cgl-current.sh grabs it from the X server and
//   checks the colour.
#import <Cocoa/Cocoa.h>
#import "test-argument-words.h"
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static NSOpenGLContext *g_ctx;
static int g_useNS;

static void *render(void *arg)
{
	usleep(1500000);
	if (g_useNS)
		[g_ctx makeCurrentContext];
	else
		CGLSetCurrentContext([g_ctx CGLContextObj]);
	for (int i = 0; i < 400; i++) {
		glViewport(0, 0, 400, 300);
		glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		CGLFlushDrawable([g_ctx CGLContextObj]);
		usleep(50000);
	}
	dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
	return NULL;
}

int main(int argc, char **argv)
{
	@autoreleasepool {
		g_useNS = argc > 1 && !strcmp(argv[1], "ns");
		[NSApplication sharedApplication];
		NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
		                                          styleMask:NSWindowStyleMaskTitled
		                                            backing:NSBackingStoreBuffered defer:NO];
		NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
		[w setContentView:v];
		[w makeKeyAndOrderFront:nil];

		CGLPixelFormatAttribute attrs[] = { kCGLPFADoubleBuffer, kCGLPFAColorSize, (CGLPixelFormatAttribute) 24, (CGLPixelFormatAttribute) 0 };
		CGLPixelFormatObj pf; GLint n; CGLContextObj c;
		if (CGLChoosePixelFormat(attrs, &pf, &n) || CGLCreateContext(pf, NULL, &c)) { printf("SKIP\n"); return 0; }
		g_ctx = [[NSOpenGLContext alloc] initWithCGLContextObj:c];
		[g_ctx setView:v];
		pthread_t t;
		pthread_create(&t, NULL, render, NULL);
		TestIgnoreArgumentWords();
		[NSApp run];
	}
	return 0;
}
