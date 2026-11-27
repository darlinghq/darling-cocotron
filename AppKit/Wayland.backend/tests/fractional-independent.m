/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Real compositor fixture for windows and GL views on outputs of different scales, driven by
// fractional-independent-run.sh (see there for the compositor setup: one output at 1.25, one at 2.25).
// Whole scale factors are what AppKit reports: 2 on the 1.25 output and 3 on the 2.25 one. The window
// holds two GL views that are left static after their first display, so a change of scale must itself
// cause the reshape and the redraw. The script moves the window between the outputs (and across the
// border between them), and swaps the outputs' scales while the window or a view is hidden. Every phase
// the program checks, for the window and for each view, the scale of the output it is on, the drawable
// size (the logical size times that whole scale), the redraw of a view whose scale changed, and the
// pixel in the drawable's last corner; the script checks the buffers and the pixels the compositor shows.
// Usage: fractional-independent (FRACTIONAL_CONTROL names the file the script writes the stage into)
static unsigned checks, failures;
static void expectResult(BOOL pass, const char *label) {
    ++checks; if (!pass) ++failures;
    printf("CHECK %s %s\n", pass ? "PASS" : "FAIL", label); fflush(stdout);
}
@interface FlatView : NSView @end
@implementation FlatView
- (void)drawRect:(NSRect)rect {
    [[NSColor redColor] setFill]; NSRectFill([self bounds]);
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

static NSWindow *window;
static FractionalGLView *leftView, *rightView;
static unsigned oldDraws[2], oldReshapes[2];
static int oldScale[2];

// The whole scale of the output each part is on, per phase (see the script for the moves):
// 0 the window on the 1.25 output, 1 on the 2.25 output, 2 across the border (left view on the
// 1.25 output, right view on the 2.25 one), 3 back on the 1.25 output, 4 mapped again after the
// outputs swapped their scales (so on the 2.25 output), 5 the scales swapped back with the left view
// hidden meanwhile. The window's own scale across the border is the compositor's choice of the two.
static const int leftScales[6] = {2, 3, 2, 2, 3, 2};
static const int rightScales[6] = {2, 3, 3, 2, 3, 2};
static const int windowScales[6] = {2, 3, 0, 2, 3, 2};

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
    if (stage == 8) {
        [timer invalidate]; [window close];
        printf("RESULT checks=%u failures=%u\n",checks,failures);fflush(stdout);exit(failures?1:0);
    }
    if (stage == 4) {
        [window orderOut:nil]; stage++; puts("PARENT_HIDDEN");fflush(stdout);return;
    }
    if (stage == 6) {
        [leftView setHidden:YES];stage++;puts("CHILD_HIDDEN");fflush(stdout);return;
    }
    if (!transition) {
        transition=YES;
        if(stage==5)[window makeKeyAndOrderFront:nil];
        if(stage==7)[leftView setHidden:NO];
        settleUntil=[NSDate timeIntervalSinceReferenceDate]+1;
        return;
    }
    if([NSDate timeIntervalSinceReferenceDate]<settleUntil)return;
    // stages 0-3 are phases 0-3, stage 5 is phase 4, stage 7 is phase 5
    unsigned phase = stage < 4 ? stage : (stage == 5 ? 4 : 5);
    CGFloat parentScale = [window backingScaleFactor];
    expectResult(windowScales[phase] ? parentScale == windowScales[phase] : (parentScale == 2 || parentScale == 3),
                 "window takes the whole scale of its output");
    FractionalGLView *views[]={leftView,rightView};
    const int *scales[2]={leftScales,rightScales};
    for(unsigned i=0;i<2;i++) {
        FractionalGLView *view=views[i];
        int scale=scales[i][phase];
        expectResult(view->lastPixels.width==101*scale && view->lastPixels.height==51*scale,"child drawable is the logical size at the whole scale of its own output");
        BOOL changed=scale!=oldScale[i];
        expectResult(!changed || (view->draws>oldDraws[i] && view->reshapes>oldReshapes[i]),"child whose output scale changed redraws and reshapes");
        expectResult(view->error==GL_NO_ERROR && view->edge[0]==(i?0:255) && view->edge[1]==(i?255:0) && view->edge[2]==255 && view->edge[3]==255,"child GL rendered edge");
        printf("INDEPENDENT phase=%u view=%u size=%.0fx%.0f draws=%u reshapes=%u\n",phase,i,view->lastPixels.width,view->lastPixels.height,view->draws,view->reshapes);
        oldDraws[i]=view->draws;oldReshapes[i]=view->reshapes;oldScale[i]=scale;
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
