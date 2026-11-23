// Copyright (C) 2026 Lubos Dolezel
//
// An OpenGL context attached to a view follows its drawable to the size the
// view gets when the window enters or leaves native full screen, without the
// client calling -update: AppKit sends -update to the contexts attached to
// views of that window itself (observable by overriding -update). A plain
// resize of the window gets no such update.
//
// The drawable size is observed through the default framebuffer: it is cleared
// with a distinct colour and a pixel near the far corner of the area in
// question is read back into a buffer pre-filled with a sentinel; a pixel
// outside the drawable leaves the sentinel (or fails) and counts as missing.
//
// Usage: nsopenglcontext-fullscreen-update <mode>
//   follow    context attached while windowed; enter full screen: updates are
//             received and the drawable covers the full screen; exit: updates
//             are received and the drawable is small again
//             (test_quirk_fullscreen_transition_sends_update)
//   resize    control: -setContentSize: bigger gets no update from the system
//             and the drawable does not follow; an explicit -update does
//   attach    full screen is entered first, the context is attached after it:
//             the drawable has the view's full size from -setView:
//   immediate -setView: right after -toggleFullScreen:, before the window
//             system has resized the window: the drawable ends up full size
// Needs a window manager that does native full screen (X11 with xfwm4, Wayland).
#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

@interface CountingContext : NSOpenGLContext {
@public
	int updates;
}
@end

@implementation CountingContext
- (void) update
{
	updates++;
	[super update];
}
@end

static void spin(double seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static BOOL gotEnter, gotExit;

@interface Watcher : NSObject
@end
@implementation Watcher
- (void) enter: (NSNotification *) n { gotEnter = YES; }
- (void) exit: (NSNotification *) n { gotExit = YES; }
@end

static BOOL waitFlag(BOOL *flag, double seconds)
{
	NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
	while (!*flag && [end timeIntervalSinceNow] > 0)
		spin(0.05);
	return *flag;
}

// YES when the drawable of the current context has the pixel (x, y).
static BOOL drawableHas(int x, int y, int width, int height)
{
	glViewport(0, 0, width, height);
	glClearColor(0, 1, 0, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	unsigned char px[4] = {1, 2, 3, 4};
	glGetError();
	glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	if (glGetError() != GL_NO_ERROR)
		return NO;
	return px[0] == 0 && px[1] == 255 && px[2] == 0;
}

// A frame is drawn and presented, as a rendering application does continuously,
// so that a drawable resize that is waiting for the next swap takes effect.
static void present(NSOpenGLContext *ctx)
{
	[ctx makeCurrentContext];
	glClearColor(0, 0, 1, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	[ctx flushBuffer];
	spin(0.3);
	[ctx makeCurrentContext];
}

static CountingContext *makeContext(void)
{
	NSOpenGLPixelFormatAttribute attrs[] = { NSOpenGLPFADoubleBuffer, NSOpenGLPFAColorSize, 24, 0 };
	NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes: attrs];
	return [[CountingContext alloc] initWithFormat: pf shareContext: nil];
}

int main(int argc, char **argv)
{
	@autoreleasepool {
		const char *mode = argc > 1 ? argv[1] : "follow";
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps: YES];
		NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
		                                          styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
		                                            backing: NSBackingStoreBuffered
		                                              defer: NO];
		[w setCollectionBehavior: NSWindowCollectionBehaviorFullScreenPrimary];
		NSView *v = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
		[w setContentView: v];
		Watcher *watch = [Watcher new];
		[[NSNotificationCenter defaultCenter] addObserver: watch selector: @selector(enter:)
		                                             name: NSWindowDidEnterFullScreenNotification object: w];
		[[NSNotificationCenter defaultCenter] addObserver: watch selector: @selector(exit:)
		                                             name: NSWindowDidExitFullScreenNotification object: w];
		[w makeKeyAndOrderFront: nil];
		spin(1.0);

		CountingContext *ctx = makeContext();
		if (ctx == nil) { printf("SKIP\n"); return 0; }

		if (!strcmp(mode, "follow")) {
			[ctx setView: v];
			[ctx makeCurrentContext];
			NSSize screen = [[w screen] frame].size;
			int sx = (int) screen.width - 8, sy = (int) screen.height - 8;
			expect(drawableHas(392, 292, 400, 300), "windowed drawable has its own corner");
			expect(!drawableHas(sx, sy, (int) screen.width, (int) screen.height),
			      "windowed drawable lacks the far screen corner");
			int before = ctx->updates;

			[w toggleFullScreen: nil];
			expect(waitFlag(&gotEnter, 8), "entered full screen");
			spin(0.5);
			NSSize big = [v frame].size;
			printf("full screen view %dx%d, updates %d\n", (int) big.width, (int) big.height, ctx->updates);
			expect(ctx->updates > before, "AppKit sent -update on entering full screen");
			present(ctx);
			expect(drawableHas((int) big.width - 8, (int) big.height - 8, (int) big.width, (int) big.height),
			      "drawable follows the view into full screen");
			before = ctx->updates;

			[w toggleFullScreen: nil];
			expect(waitFlag(&gotExit, 8), "left full screen");
			spin(0.5);
			NSSize small = [v frame].size;
			printf("windowed view %dx%d, updates %d\n", (int) small.width, (int) small.height, ctx->updates);
			expect(small.width < big.width, "view is smaller again");
			expect(ctx->updates > before, "AppKit sent -update on leaving full screen");
			present(ctx);
			expect(!drawableHas((int) big.width - 8, (int) big.height - 8, (int) big.width, (int) big.height),
			      "drawable follows the view back out of full screen");
		} else if (!strcmp(mode, "resize")) {
			[ctx setView: v];
			[ctx makeCurrentContext];
			expect(drawableHas(392, 292, 400, 300), "windowed drawable has its own corner");
			[w setContentSize: NSMakeSize(700, 500)];
			spin(1.5);
			NSSize now = [v frame].size;
			expect((int) now.width == 700, "window was resized");
			present(ctx);
			expect(ctx->updates == 0, "no -update from the system on a plain resize");
			expect(!drawableHas(692, 492, 700, 500), "drawable does not follow a plain resize");
			[ctx update];
			present(ctx);
			expect(drawableHas(692, 492, 700, 500), "explicit -update makes it follow");
		} else if (!strcmp(mode, "attach") || !strcmp(mode, "immediate")) {
			BOOL immediate = !strcmp(mode, "immediate");
			[w toggleFullScreen: nil];
			if (immediate) {
				[ctx setView: v];
			} else {
				expect(waitFlag(&gotEnter, 8), "entered full screen");
				spin(0.5);
				[ctx setView: v];
			}
			if (immediate) {
				expect(waitFlag(&gotEnter, 8), "entered full screen");
				spin(0.5);
			}
			NSSize big = [v frame].size;
			printf("full screen view %dx%d, updates %d\n", (int) big.width, (int) big.height, ctx->updates);
			expect(big.width > 400, "view has the full screen size");
			present(ctx);
			expect(drawableHas((int) big.width - 8, (int) big.height - 8, (int) big.width, (int) big.height),
			      immediate ? "drawable has the full size after the transition"
			                : "drawable is created at the view's full-screen size");
		} else {
			printf("unknown mode\n");
			return 2;
		}
		printf(failures ? "FAIL\n" : "PASS\n");
		return failures ? 1 : 0;
	}
}
