#import <AppKit/AppKit.h>
#import <CoreGraphics/CGSubWindow.h>
#import <CoreGraphics/CGWindow.h>
#import <OpenGL/CGLInternal.h>
#import <OpenGL/gl.h>
#import <QuartzCore/CALayer.h>
#include <stdio.h>
#include <unistd.h>
#include <dlfcn.h>
#include <math.h>

@interface NSWindow (WaylandEGLFixture)
- (CGWindow *) platformWindow;
- (CGSubWindow *) _createSubWindowWithFrame: (CGRect) frame;
@end
@interface PaintView : NSView
@end
@implementation PaintView
- (void) drawRect: (NSRect) rect { [[NSColor redColor] setFill]; NSRectFill([self bounds]); }
@end
@interface LayerPaintView : NSView
@end
@implementation LayerPaintView
- (void) drawRect:(NSRect)rect { [[NSColor blueColor] setFill]; NSRectFill([self bounds]); }
@end
@interface GLPaintView : NSOpenGLView
@end
@implementation GLPaintView
- (void) drawRect:(NSRect)rect {
    [[self openGLContext] makeCurrentContext];
    glClearColor(1,0,1,1); glClear(GL_COLOR_BUFFER_BIT);
    [[self openGLContext] flushBuffer];
}
@end
static GLPaintView *glView;
static NSWindow *window, *anchor;
static CGSubWindow *child;
static CGLContextObj context;
static CGLWindowRef drawable;
static unsigned failures;
static CGSubWindow *upper;
static CGLContextObj upperContext;
static CGLWindowRef upperDrawable;
static int workerDone, deep;
static void assertResult(BOOL pass, const char *label) {
    printf("CHECK %s %s\n", pass ? "PASS" : "FAIL", label); fflush(stdout);
    if (!pass) __sync_fetch_and_add(&failures, 1);
}
static void draw(void) {
    assertResult(CGLContextMakeCurrentAndAttachToWindow(context, drawable) == kCGLNoError, "make-current");
    glViewport(0,0,120,80);
    glClearColor(0,1,0,1); glClear(GL_COLOR_BUFFER_BIT);
    unsigned char pixel[4] = {0};
    glReadPixels(5,5,1,1,GL_RGBA,GL_UNSIGNED_BYTE,pixel);
    assertResult(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255,"EGL green pixel");
    assertResult(CGLFlushDrawable(context) == kCGLNoError,"swap");
    [child flush];
}
static void drawUpper(void) {
    assertResult(CGLContextMakeCurrentAndAttachToWindow(upperContext,upperDrawable)==kCGLNoError,"upper current");
    glClearColor(1,1,0,1); glClear(GL_COLOR_BUFFER_BIT);
    assertResult(CGLFlushDrawable(upperContext)==kCGLNoError,"upper swap"); [upper flush];
}
static void invalidatedParent(void) {
    NSWindow *ghost=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,40,40)
        styleMask:0 backing:NSBackingStoreBuffered defer:YES];
    [ghost setReleasedWhenClosed:NO];
    CGSubWindow *sub=[[ghost _createSubWindowWithFrame:NSMakeRect(0,0,20,20)] retain];
    CGLContextObj ctx=NULL; CGLCreateContext(NULL,NULL,&ctx);
    CGLWindowRef win=CGLGetWindow([sub nativeWindow]);
    assertResult(sub && ctx && win,"unmapped parent resources");
    [[ghost platformWindow] invalidate];
    assertResult(CGLContextMakeCurrentAndAttachToWindow(ctx,win)==kCGLNoError,"invalidated parent drawable current");
    glClearColor(0,0,0,1); glClear(GL_COLOR_BUFFER_BIT);
    assertResult(CGLFlushDrawable(ctx)==kCGLNoError,"invalidated parent drawable swap");
    [sub flush]; // Must not create a role with a NULL/invalidated parent.
    CGLSetCurrentContext(NULL); CGLReleaseContext(ctx); CGLDestroyWindow(win);
    [sub release]; [ghost release];
    assertResult(YES,"invalidated unmapped parent cleanup");
}
@interface Driver : NSObject
@end
@implementation Driver
- (void) backgroundPresentation:(id)unused {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    NSOpenGLContext *ctx=[glView openGLContext];
    [ctx makeCurrentContext]; [ctx flushBuffer];
    assertResult([NSOpenGLContext currentContext]==nil && CGLGetCurrentContext()==NULL,
                 "background presentation rejected before binding/swap");
    __atomic_store_n(&workerDone,1,__ATOMIC_RELEASE); [pool release];
}
- (void) step: (NSTimer *) timer {
    static int step;
    ++step;
    if (step == 1) {
        child = [[window _createSubWindowWithFrame:NSMakeRect(30,40,120,80)] retain];
        assertResult(child != nil,"native subwindow");
        assertResult(CGLCreateContext(NULL,NULL,&context) == kCGLNoError && context,"CGL context");
        drawable = CGLGetWindow([child nativeWindow]);
        assertResult(drawable != NULL,"EGL drawable");
        if (!child || !context || !drawable) { printf("RESULT failures=%u\n",failures); fflush(stdout); exit(1); }
        GLint interval = -1;
        assertResult(CGLGetParameter(context,kCGLCPSwapInterval,&interval)==kCGLNoError && interval==0,"default nonblocking swap");
        CGLError (*registerPlatform)(void *,unsigned int)=dlsym(RTLD_DEFAULT,"CGLRegisterNativeDisplayForPlatform");
        assertResult(registerPlatform && registerPlatform(NULL,0x31D8)==kCGLBadConnection,"reject NULL platform display");
        CGLContextObj previous = CGLGetCurrentContext();
        assertResult(CGLContextMakeCurrentAndAttachToWindow(context,NULL)==kCGLBadDrawable &&
                     CGLGetCurrentContext()==previous,"reject missing drawable without rebinding");
        draw();
        if (deep) {
            upper=[[window _createSubWindowWithFrame:NSMakeRect(50,60,60,40)] retain];
            CGLCreateContext(NULL,NULL,&upperContext); upperDrawable=CGLGetWindow([upper nativeWindow]);
            assertResult(upper && upperContext && upperDrawable,"overlap upper resources"); drawUpper();
        }
    } else if (step == 2) {
        [child setFrame:NSMakeRect(100,100,120,80)]; draw();
    } else if (step == 3) {
        [child hide]; [glView setHidden:YES]; draw(); // Swapping a hidden child must not remap it.
    } else if (step == 4) {
        if (deep) [child setFrame:NSMakeRect(30,40,120,80)];
        [child show]; [glView setHidden:NO]; [glView display]; draw();
    } else if (step == 5) {
        [window orderOut:nil]; draw(); // Must not wait forever for a frame callback.
    } else if (step == 6) {
        [window makeKeyAndOrderFront:nil]; draw();
    } else if (step == 7) {
        [window setFrame:NSMakeRect(0,0,440,340) display:YES]; draw();
        if (deep) drawUpper();
    } else if (step == 8) {
        if (glView) {
            [[glView openGLContext] makeCurrentContext];
            [glView retain]; [glView removeFromSuperview];
            [glView setFrame:NSMakeRect(0,0,80,50)];
            [[anchor contentView] addSubview:glView]; [glView release]; [glView display];
        }
        [child setFrame:NSMakeRect(-30,100,120,80)]; draw();
    } else if (step == 9) {
        if (glView) {
            [[glView openGLContext] makeCurrentContext];
            [glView retain]; [glView removeFromSuperview];
            [glView setFrame:NSMakeRect(250,150,80,50)];
            [[window contentView] addSubview:glView]; [glView release]; [glView display];
        }
        [child setFrame:NSMakeRect(-200,100,120,80)]; draw();
    } else if (step == 10) {
        [child setFrame:NSMakeRect(100,100,120,80)];
        [child setFrame:NSMakeRect(NAN,100,120,80)];
        [child setFrame:NSMakeRect(100,100,-1e100,80)]; draw();
    } else if (step == 11) {
        [child setFrame:NSMakeRect(100,100,13.5,11.5)]; draw();
    } else if (step == 12) {
        [window setFrame:NSMakeRect(0,0,80,340) display:YES]; // No raw child redraw.
    } else if (step == 13) {
        [window setFrame:NSMakeRect(0,0,440,340) display:YES]; draw();
        if (deep) drawUpper();
    } else if (step == 14) {
        CGLSetCurrentContext(NULL); CGLReleaseContext(context);
        CGLDestroyWindow(drawable); [child release]; child=nil;
    } else if (step == 15) {
        invalidatedParent();
    } else if (step == 16) {
        if (glView) [NSThread detachNewThreadSelector:@selector(backgroundPresentation:) toTarget:self withObject:nil];
        else workerDone=1;
    } else if (step == 17) {
        assertResult(__atomic_load_n(&workerDone,__ATOMIC_ACQUIRE),"background guard bounded completion");
        if (upper) { CGLReleaseContext(upperContext); CGLDestroyWindow(upperDrawable); [upper release]; }
        [window close];
        printf("RESULT failures=%u\n",failures); fflush(stdout); exit(failures ? 1 : 0);
    }
    printf("STAGE %d\n",step); fflush(stdout);
}
@end
int main(void) {
    NSAutoreleasePool *pool=[NSAutoreleasePool new];
    [NSApplication sharedApplication];
    deep=getenv("DEEP_TEST") && *getenv("DEEP_TEST");
    window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,300)
             styleMask:NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask
             backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Wayland EGL fixture"];
    PaintView *paint=[[[PaintView alloc] initWithFrame:NSMakeRect(0,0,400,300)] autorelease];
    [window setContentView:paint];
    if (getenv("LAYER_TEST")) {
        LayerPaintView *layerView=[[[LayerPaintView alloc] initWithFrame:NSMakeRect(250,30,100,60)] autorelease];
        [paint addSubview:layerView]; [layerView setWantsLayer:YES];
    }
    if (getenv("OPENGL_VIEW_TEST") && *getenv("OPENGL_VIEW_TEST")) {
        glView=[[[GLPaintView alloc] initWithFrame:NSMakeRect(250,150,80,50)] autorelease];
        [paint addSubview:glView];
    }
    [window makeKeyAndOrderFront:nil];
    anchor=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,50,50)
             styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    [anchor setTitle:@"EGL test anchor"]; [anchor orderFront:nil];
    Driver *driver=[Driver new];
    [NSTimer scheduledTimerWithTimeInterval:2 target:driver selector:@selector(step:) userInfo:nil repeats:YES];
    [NSApp run]; [pool release]; return 1;
}
