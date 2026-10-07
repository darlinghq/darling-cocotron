#import <AppKit/AppKit.h>
#import <CoreGraphics/CGSubWindow.h>
#import <OpenGL/CGLInternal.h>
#import <OpenGL/gl.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSWindow (ResizeFixture)
- (CGSubWindow *)_createSubWindowWithFrame:(CGRect)frame;
@end
static NSWindow *window;
static CGSubWindow *child;
static CGLContextObj context;
static CGLWindowRef drawable;
static unsigned failures;
static void expectResult(BOOL pass, const char *label) {
    printf("%s %s\n", pass ? "PASS" : "FAIL", label); fflush(stdout);
    if (!pass) ++failures;
}
@interface ResizeDriver : NSObject @end
@implementation ResizeDriver
- (void)step:(NSTimer *)timer {
    static unsigned stage;
    if (getenv("RESIZE_CONTROL")) {
        unsigned requested = 99;
        FILE *control = fopen(getenv("RESIZE_CONTROL"), "r");
        if (control) { if (fscanf(control, "%u", &requested) != 1) requested = 99; fclose(control); }
        if (requested != stage) return;
    }
    if (stage == 0) {
        child = [[window _createSubWindowWithFrame:NSMakeRect(20,20,120,80)] retain];
        expectResult(child != nil, "native child");
        expectResult(CGLCreateContext(NULL,NULL,&context) == kCGLNoError, "context");
        drawable = CGLGetWindow([child nativeWindow]);
        expectResult(drawable != NULL, "drawable");
        if (!child || !context || !drawable) exit(1);
    }
    expectResult(CGLContextMakeCurrentAndAttachToWindow(context,drawable) == kCGLNoError,
                 "make current");
    glClearColor(stage == 0 || stage == 5, stage == 1 || stage == 2, stage == 3 || stage == 4, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    // Allocate/render the backbuffer before geometry changes, as a configure
    // dispatched during EGL presentation can do in a real application.
    if (stage == 1) [child setFrame:NSMakeRect(20,20,320,180)];
    if (stage == 3) [child setFrame:NSMakeRect(20,20,90,60)];
    expectResult(CGLFlushDrawable(context) == kCGLNoError, "swap after resize");
    [child flush];
    printf("PRESENTED stage=%u\n", stage); fflush(stdout);
    if (++stage == 6) {
        [timer invalidate];
        CGLSetCurrentContext(NULL); CGLReleaseContext(context); CGLDestroyWindow(drawable);
        [child release]; [window close];
        printf("RESULT failures=%u\n", failures); fflush(stdout); exit(failures ? 1 : 0);
    }
}
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,400)
        styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Resize before EGL swap"];
    [window orderFront:nil];
    ResizeDriver *driver = [ResizeDriver new];
    [NSTimer scheduledTimerWithTimeInterval:.3 target:driver selector:@selector(step:)
        userInfo:nil repeats:YES];
    [NSApp run];
} }
