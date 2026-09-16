#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
union CursorArgument {int32_t i;uint32_t u;void *o;};
@interface NSObject (CursorFixture)
+ (id)currentDisplay;
- (id)cursorWithImage:(NSImage *)image hotSpot:(NSPoint)point;
- (void)setCursor:(id)cursor;
- (void)hideCursor;
- (void)pointerEvent:(uint32_t)opcode arguments:(union CursorArgument *)args;
- (void)seatCapabilities:(uint32_t)capabilities;
@end
static id display,first,second;
static NSWindow *window;
static const char *mode;
static BOOL armed,fired;
static int drawsAfterArmed,failures,oldImageDeallocs,earlyDeallocs;
static BOOL drawingImage;
static uint32_t serial(void) {
    Ivar iv=class_getInstanceVariable(object_getClass(display),"_pointerEnterSerial");
    return *(uint32_t *)((char *)display+ivar_getOffset(iv));
}
@interface CallbackImage : NSImage { BOOL trigger; } - (id)initTrigger:(BOOL)value; @end
@implementation CallbackImage
- (id)initTrigger:(BOOL)value {if((self=[super initWithSize:NSMakeSize(32,24)]))trigger=value;return self;}
- (void)dealloc {if(trigger){oldImageDeallocs++;if(drawingImage)earlyDeallocs++;}[super dealloc];}
- (void)drawInRect:(NSRect)rect fromRect:(NSRect)src operation:(NSCompositingOperation)op fraction:(CGFloat)fraction {
    if(trigger)drawingImage=YES;
    if(trigger && armed) {
        drawsAfterArmed++;
        if(!fired) {
            fired=YES;
            if(!strcmp(mode,"release")){id old=first;first=nil;[old release];[display setCursor:second];}
            else if(!strcmp(mode,"switch"))[display setCursor:second];
            else if(!strcmp(mode,"same"))[display setCursor:first];
            else if(!strcmp(mode,"blank"))[display hideCursor];
            else if(!strcmp(mode,"hide"))[window orderOut:nil];
            else if(!strcmp(mode,"leave")){union CursorArgument a[2]={{.u=1},{.o=NULL}};[display pointerEvent:1 arguments:a];}
            else if(!strcmp(mode,"capability"))[display seatCapabilities:0];
            else if(!strcmp(mode,"resize"))[window setContentSize:NSMakeSize(40,40)];
            printf("CALLBACK mode=%s serial=%u\n",mode,serial());fflush(stdout);
        }
    }
    [(trigger?[NSColor redColor]:[NSColor cyanColor]) set];NSRectFill(rect);
    if(trigger)drawingImage=NO;
}
@end
@interface CursorApplication : NSApplication @end
@implementation CursorApplication
- (void)selectWhenEntered:(id)sender {
    if(!armed && serial()!=0){armed=YES;[display setCursor:first];printf("SELECTED\n");fflush(stdout);}
}
- (void)finish:(id)sender {
    if(!fired || drawsAfterArmed!=1)failures++;
    if(!strcmp(mode,"release") && (oldImageDeallocs!=1 || earlyDeallocs!=0))failures++;
    printf("LIFETIME deallocs=%d early=%d\n",oldImageDeallocs,earlyDeallocs);
    if((!strcmp(mode,"hide")||!strcmp(mode,"leave")||!strcmp(mode,"capability")) && serial()!=0)failures++;
    printf("RESULT fired=%d rasterizations=%d serial=%u failures=%d\n",fired,drawsAfterArmed,serial(),failures);fflush(stdout);exit(failures?1:0);
}
@end
int main(void) {@autoreleasepool{
    mode=getenv("CURSOR_CALLBACK_MODE");if(!mode)return 2;
    [CursorApplication sharedApplication];display=[NSClassFromString(@"NSDisplay") currentDisplay];
    // Drain construction autoreleases so release mode really drops the last
    // external reference during rendering. Other cases retain both cursors.
    @autoreleasepool {
    first=[[display cursorWithImage:[[[CallbackImage alloc]initTrigger:YES]autorelease] hotSpot:NSMakePoint(3,5)]retain];
    second=[[display cursorWithImage:[[[CallbackImage alloc]initTrigger:NO]autorelease] hotSpot:NSMakePoint(3,5)]retain];
    }
    window=[[NSWindow alloc]initWithContentRect:NSMakeRect(100,100,500,350) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Cursor callback fixture"];[window setBackgroundColor:[NSColor blackColor]];[window makeKeyAndOrderFront:nil];
    NSWindow *keeper=[[NSWindow alloc]initWithContentRect:NSMakeRect(900,600,50,50) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [keeper setTitle:@"Cursor keeper"];[keeper orderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:.1 target:NSApp selector:@selector(selectWhenEntered:) userInfo:nil repeats:YES];
    [NSApp performSelector:@selector(finish:) withObject:nil afterDelay:7];printf("READY\n");fflush(stdout);[NSApp run];
}}
