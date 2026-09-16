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
static FractionalGLView *leftView, *rightView;
static unsigned oldDraws[2], oldReshapes[2];
@interface IndependentDriver : NSObject @end
@implementation IndependentDriver
- (void)inspect:(NSTimer *)timer {
    static unsigned stage;
    static NSTimeInterval settleUntil;
    static BOOL transition;
    int requested = -1;
    FILE *control = fopen(getenv("FRACTIONAL_CONTROL"), "r");
    if (control) { if (fscanf(control,"%d",&requested)!=1) requested=-1; fclose(control); }
    if (requested != (int)stage) return;
    if (stage == 5) {
        [timer invalidate]; [window close];
        printf("RESULT checks=%u failures=%u\n",checks,failures);fflush(stdout);exit(failures?1:0);
    }
    if (stage == 1) {
        [window orderOut:nil]; stage++; puts("PARENT_HIDDEN");fflush(stdout);return;
    }
    if (stage == 3) {
        [leftView setHidden:YES];stage++;puts("CHILD_HIDDEN");fflush(stdout);return;
    }
    if (!transition) {
        transition=YES;
        if(stage==2)[window makeKeyAndOrderFront:nil];
        if(stage==4)[leftView setHidden:NO];
        settleUntil=[NSDate timeIntervalSinceReferenceDate]+1;
        return;
    }
    if([NSDate timeIntervalSinceReferenceDate]<settleUntil)return;
    unsigned phase=stage/2;
    const double parentScales[]={1.75,1.5,1.75};
    const int sizes[3][2][2]={{{126,64},{177,89}},{{152,77},{126,64}},{{177,89},{126,64}}};
    expectResult(fabs([window backingScaleFactor]-parentScales[phase])<1e-9,"parent maximum scale");
    FractionalGLView *views[]={leftView,rightView};
    for(unsigned i=0;i<2;i++) {
        FractionalGLView *view=views[i];
        expectResult(view->lastPixels.width==sizes[phase][i][0] && view->lastPixels.height==sizes[phase][i][1],"independent child allocation");
        BOOL changed=!(phase==2 && i==1);
        expectResult(!changed || (view->draws>oldDraws[i] && view->reshapes>oldReshapes[i]),"changed child redraw after remap");
        expectResult(view->error==GL_NO_ERROR && view->edge[0]==(i?0:255) && view->edge[1]==(i?255:0) && view->edge[2]==255 && view->edge[3]==255,"independent GL rendered edge");
        printf("INDEPENDENT phase=%u view=%u size=%.0fx%.0f draws=%u reshapes=%u\n",phase,i,view->lastPixels.width,view->lastPixels.height,view->draws,view->reshapes);
        oldDraws[i]=view->draws;oldReshapes[i]=view->reshapes;
    }
    printf("CAPTURE %u\n",phase);fflush(stdout);stage++;transition=NO;
}
@end
int main(void) {@autoreleasepool{
    if(!getenv("FRACTIONAL_CONTROL"))return 2;
    [NSApplication sharedApplication];
    window=[[NSWindow alloc]initWithContentRect:NSMakeRect(500,100,601,401) styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Independent fractional fixture"];
    FlatView *root=[[[FlatView alloc]initWithFrame:NSMakeRect(0,0,601,401)]autorelease];[window setContentView:root];
    leftView=[[[FractionalGLView alloc]initWithFrame:NSMakeRect(20,20,101,51)]autorelease];
    rightView=[[[FractionalGLView alloc]initWithFrame:NSMakeRect(400,20,101,51)]autorelease];rightView->cyan=YES;
    [root addSubview:leftView];[root addSubview:rightView];[window makeKeyAndOrderFront:nil];
    IndependentDriver *driver=[IndependentDriver new];
    [NSTimer scheduledTimerWithTimeInterval:.1 target:driver selector:@selector(inspect:) userInfo:nil repeats:YES];
    [NSApp run];
}}
