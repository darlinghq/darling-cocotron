#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSObject (FractionalCursorFixture)
+ (id)currentDisplay;
- (id)cursorWithImage:(NSImage *)image hotSpot:(NSPoint)point;
- (id)cursorWithName:(NSString *)name;
- (void)setCursor:(id)cursor;
- (void)hideCursor;
- (uint32_t)cursorRenderScale120;
@end
static id display, imageCursor;
static unsigned draws, checks, failures;
static uint32_t field(const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(display), name);
    return ivar ? *(uint32_t *)((char *)display + ivar_getOffset(ivar)) : 0;
}
static void expectResult(BOOL ok, const char *label) {
    ++checks; if (!ok) ++failures;
    printf("CHECK %s %s\n",ok?"PASS":"FAIL",label);fflush(stdout);
}
@interface FlatCursorImage : NSImage @end
@implementation FlatCursorImage
- (void)drawInRect:(NSRect)rect fromRect:(NSRect)source operation:(NSCompositingOperation)operation fraction:(CGFloat)fraction {
    ++draws; [[NSColor cyanColor] setFill]; NSRectFill(rect);
}
@end
@interface CursorDriver : NSObject @end
@implementation CursorDriver
- (void)step:(NSTimer *)timer {
    static unsigned stage, previousDraws;
    static NSTimeInterval settleUntil;
    int requested=-1; FILE *file=fopen(getenv("FRACTIONAL_CONTROL"),"r");
    if(file){if(fscanf(file,"%d",&requested)!=1)requested=-1;fclose(file);}
    if(requested!=(int)stage)return;
    if(stage==7){printf("RESULT checks=%u failures=%u\n",checks,failures);fflush(stdout);exit(failures?1:0);}
    if(!field("_pointerEnterSerial"))return;
    if(!settleUntil){
        if(stage==0)previousDraws=draws;
        if(stage==0 || stage==6)[display setCursor:imageCursor];
        if(stage==3)[display setCursor:[display cursorWithName:@"arrowCursor"]];
        if(stage==5)[display hideCursor];
        settleUntil=[NSDate timeIntervalSinceReferenceDate]+1;return;
    }
    if([NSDate timeIntervalSinceReferenceDate]<settleUntil)return;
    const uint32_t scales[]={150,180,210,210,150,150,180};
    expectResult(field("_pointerEnterSerial")!=0,"native pointer entered");
    expectResult([display cursorRenderScale120]==scales[stage],"cursor effective preferred scale");
    if(stage<3 || stage==6){expectResult(draws>previousDraws,"image rerasterized for fractional target");previousDraws=draws;}
    if(stage==3 || stage==4)expectResult(field("_cursorThemeScale120")==scales[stage],"theme reloaded for fractional target");
    printf("CURSOR stage=%u scale=%u preferred=%u draws=%u\n",stage,[display cursorRenderScale120],field("_cursorPreferredScale120"),draws);
    printf("CAPTURE %u\n",stage);fflush(stdout);stage++;settleUntil=0;
}
@end
int main(void){@autoreleasepool{
    if(!getenv("FRACTIONAL_CONTROL"))return 2;
    [NSApplication sharedApplication];display=[NSClassFromString(@"NSDisplay") currentDisplay];
    FlatCursorImage *image=[[[FlatCursorImage alloc]initWithSize:NSMakeSize(31,17)]autorelease];
    imageCursor=[[display cursorWithImage:image hotSpot:NSMakePoint(3,5)]retain];
    NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(100,100,500,350) styleMask:0 backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Fractional cursor fixture"];[window setBackgroundColor:[NSColor blackColor]];[window makeKeyAndOrderFront:nil];
    CursorDriver *driver=[CursorDriver new];
    [NSTimer scheduledTimerWithTimeInterval:.1 target:driver selector:@selector(step:) userInfo:nil repeats:YES];
    puts("READY");fflush(stdout);[NSApp run];
}}
