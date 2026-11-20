// Copyright (C) 2026 Lubos Dolezel
//
// -[NSOpenGLContext initWithCGLContextObj:] wraps a context created with the
// CGL API: the wrapper reports the same CGLContextObj, holds one reference of
// it, can be made current, and a NULL context gives nil.
// Behaviour observed on macOS 26.7.3 (x86_64).
#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#include <stdio.h>

static int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } } while (0)

int main(void)
{
	@autoreleasepool {
		CGLPixelFormatAttribute attrs[] = { kCGLPFADoubleBuffer, (CGLPixelFormatAttribute) 0 };
		CGLPixelFormatObj pf = NULL;
		GLint npix = 0;
		CGLContextObj ctx = NULL;
		if (CGLChoosePixelFormat(attrs, &pf, &npix) != kCGLNoError || CGLCreateContext(pf, NULL, &ctx) != kCGLNoError) {
			printf("SKIP: cannot create a CGL context\n");
			return 0;
		}
		UInt32 before = CGLGetContextRetainCount(ctx);

		NSOpenGLContext *wrapper = [[NSOpenGLContext alloc] initWithCGLContextObj:ctx];
		CHECK(wrapper != nil);
		CHECK([wrapper CGLContextObj] == ctx);
		CHECK(CGLGetContextRetainCount(ctx) == before + 1);
		CHECK([wrapper view] == nil);

		[wrapper makeCurrentContext];
		CHECK(CGLGetCurrentContext() == ctx);
		CHECK([NSOpenGLContext currentContext] == wrapper);
		[NSOpenGLContext clearCurrentContext];

		[wrapper release];

		NSOpenGLContext *none = [[NSOpenGLContext alloc] initWithCGLContextObj:NULL];
		CHECK(none == nil);
		CGLReleaseContext(ctx);
	}
	printf(g_failures ? "FAILED\n" : "ALL PASSED\n");
	return g_failures ? 1 : 0;
}
