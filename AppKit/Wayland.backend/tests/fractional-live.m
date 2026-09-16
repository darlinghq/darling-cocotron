#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Real compositor fixture: leave views static after their first display so a
// later output scale change must itself cause reshape and presentation.
static unsigned checks, failures;
static void expectResult(BOOL pass, const char *label) {
    ++checks; if (!pass) ++failures;
    printf("CHECK %s %s\n", pass ? "PASS" : "FAIL", label); fflush(stdout);
}
@interface FlatView : NSView { @public BOOL blue; } @end
@implementation FlatView
- (void)drawRect:(NSRect)rect {
    [(blue ? [NSColor blueColor] : [NSColor redColor]) setFill]; NSRectFill([self bounds]);
}
@end
@interface FractionalGLView : NSOpenGLView {
@public BOOL cyan; unsigned draws, reshapes; NSSize lastPixels; unsigned char edge[4]; GLenum error;
} @end
@implementation FractionalGLView
- (void)reshape {
    ++reshapes; lastPixels = [self convertRectToBacking:[self bounds]].size;
    glViewport(0, 0, (GLsizei)lastPixels.width, (GLsizei)lastPixels.height);
}
- (void)drawRect:(NSRect)rect {
    ++draws;
    glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION); glLoadIdentity();
    glMatrixMode(GL_MODELVIEW); glLoadIdentity();
    glColor4f(cyan ? 0 : 1, cyan ? 1 : 0, 1, 1);
    glBegin(GL_QUADS);
    glVertex2f(-1,-1); glVertex2f(1,-1); glVertex2f(1,1); glVertex2f(-1,1);
    glEnd();
    memset(edge, 0x5a, sizeof(edge));
    if (lastPixels.width > 0 && lastPixels.height > 0)
        glReadPixels((GLint)lastPixels.width - 1, (GLint)lastPixels.height - 1,
                     1, 1, GL_RGBA, GL_UNSIGNED_BYTE, edge);
    error = glGetError(); [[self openGLContext] flushBuffer];
}
@end
@interface ContextSwitchGLView : FractionalGLView { BOOL observedMissingContext; } @end
@implementation ContextSwitchGLView
- (void)prepareOpenGL { CGLSetCurrentContext(NULL); }
- (void)drawRect:(NSRect)rect {
    if (!observedMissingContext) {
        observedMissingContext = YES;
        expectResult(CGLGetCurrentContext() == NULL && reshapes == 0,
                     "prepareOpenGL raw context change defers reshape");
        [self performSelector:@selector(redisplay:) withObject:nil afterDelay:.1];
        return;
    }
    [super drawRect:rect];
}
- (void)redisplay:(id)sender { [self display]; }
@end
static NSWindow *window;
static FractionalGLView *fullView, *clipped;
static unsigned oldDraws[2], oldReshapes[2];
@interface FractionalDriver : NSObject @end
@implementation FractionalDriver
- (void)inspect:(NSTimer *)timer {
    static unsigned stage;
    static NSTimeInterval settleUntil;
    int requested = -1;
    FILE *control = fopen(getenv("FRACTIONAL_CONTROL"), "r");
    if (control) { if (fscanf(control, "%d", &requested) != 1) requested = -1; fclose(control); }
    if (requested != (int)stage) return;
    if (stage == 3) { [timer invalidate]; [self finish:nil]; return; }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!settleUntil) { settleUntil = now + 1; return; }
    if (now < settleUntil) return;
    const double scales[] = {1.25, 1.5, 1.75};
    double scale = scales[stage];
    expectResult(fabs([window backingScaleFactor] - scale) < 1e-9, "window fractional scale");
    FractionalGLView *views[] = {fullView, clipped};
    for (unsigned i = 0; i < 2; ++i) {
        FractionalGLView *view = views[i];
        int width = (int)floor(101 * scale + .5), height = (int)floor(51 * scale + .5);
        expectResult(view->lastPixels.width == width && view->lastPixels.height == height,
              "GL rounded full drawable extent");
        expectResult(view->draws > oldDraws[i] && view->reshapes > oldReshapes[i],
              "static GL redraw and reshape after scale");
        expectResult(view->error == GL_NO_ERROR && view->edge[0] == (view->cyan ? 0 : 255) &&
              view->edge[1] == (view->cyan ? 255 : 0) &&
              view->edge[2] == 255 && view->edge[3] == 255, "GL last physical pixel");
        printf("DRAWABLE stage=%u view=%u pixels=%.0fx%.0f draws=%u reshapes=%u\n",
               stage, i, view->lastPixels.width, view->lastPixels.height, view->draws, view->reshapes);
        oldDraws[i] = view->draws; oldReshapes[i] = view->reshapes;
    }
    printf("CAPTURE %u\n", stage); fflush(stdout);
    settleUntil = 0;
    if (++stage < 3) {
        printf("SCALE_READY %.2f\n", scales[stage]); fflush(stdout);
    }
}
- (void)finish:(id)sender {
    [window close]; printf("RESULT checks=%u failures=%u\n", checks, failures); fflush(stdout);
    exit(failures ? 1 : 0);
}
@end
int main(void) { @autoreleasepool {
    if (!getenv("FRACTIONAL_CONTROL")) return 2;
    [NSApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,601,401)
        styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Fractional live fixture"];
    FlatView *root = [[[FlatView alloc] initWithFrame:NSMakeRect(0,0,601,401)] autorelease];
    [window setContentView:root];
    fullView = [[[ContextSwitchGLView alloc] initWithFrame:NSMakeRect(20,20,101,51)] autorelease];
    clipped = [[[FractionalGLView alloc] initWithFrame:NSMakeRect(550,120,101,51)] autorelease];
    clipped->cyan = YES; [root addSubview:fullView]; [root addSubview:clipped];
    FlatView *layer = [[[FlatView alloc] initWithFrame:NSMakeRect(200,20,103,53)] autorelease];
    layer->blue = YES; [root addSubview:layer]; [layer setWantsLayer:YES];
    [window makeKeyAndOrderFront:nil];
    FractionalDriver *driver = [FractionalDriver new];
    [NSTimer scheduledTimerWithTimeInterval:.1 target:driver selector:@selector(inspect:) userInfo:nil repeats:YES];
    [NSApp run];
} }
