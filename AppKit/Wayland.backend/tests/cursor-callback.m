/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// An image cursor is rasterised when it is made, and never again: CoreGraphics (CGSCursor.h) takes the cursor as a
// CGImage, so selecting it, selecting another one, hiding and showing the cursor, the pointer entering the window and the window
// changing or going away call nothing in the NSImage the cursor was made of, which may also be gone by then. Each mode
// (CURSOR_CALLBACK_MODE) does one of those things once the pointer is in the window with the first cursor selected:
// switch (selects the second cursor), same (selects the first again), blank (hides the cursor and shows it), hide (orders the
// window out), resize (resizes the window), release (only the cursors hold the images: the images were released
// before the window was made). The images count their drawing and their deallocation.
// Needs DARLING_APPKIT_BACKEND=wayland, the pointer moved into the window by the driver (cursor-callback.sh).
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
@interface NSObject (CursorFixture)
+ (id)currentDisplay;
- (id)cursorWithImage:(NSImage *)image hotSpot:(NSPoint)point;
- (void)setCursor:(id)cursor;
@end
static id display,first,second;
static NSWindow *window;
static const char *mode;
static BOOL armed,fired;
static int firstDraws,secondDraws,firstDeallocs,secondDeallocs,drawsAfterArmed,failures;
static uint32_t serial(void) {
    Ivar iv=class_getInstanceVariable(object_getClass(display),"_pointerEnterSerial");
    return iv?*(uint32_t *)((char *)display+ivar_getOffset(iv)):0;
}
@interface CallbackImage : NSImage { BOOL trigger; } - (id)initTrigger:(BOOL)value; @end
@implementation CallbackImage
- (id)initTrigger:(BOOL)value {if((self=[super initWithSize:NSMakeSize(32,24)]))trigger=value;return self;}
- (void)dealloc {if(trigger)firstDeallocs++;else secondDeallocs++;[super dealloc];}
- (void)drawInRect:(NSRect)rect fromRect:(NSRect)src operation:(NSCompositingOperation)op fraction:(CGFloat)fraction {
    if(trigger)firstDraws++;else secondDraws++;
    if(armed)drawsAfterArmed++;
    [(trigger?[NSColor redColor]:[NSColor cyanColor]) set];NSRectFill(rect);
}
@end
@interface CursorApplication : NSApplication @end
@implementation CursorApplication
- (void)selectWhenEntered:(id)sender {
    if(armed || serial()==0)return;
    armed=YES;[display setCursor:first];printf("SELECTED\n");fflush(stdout);
    fired=YES;
    // Whatever the mode did gets two seconds to draw anything it will.
    [NSApp performSelector:@selector(finish:) withObject:nil afterDelay:2];
    if(!strcmp(mode,"switch"))[display setCursor:second];
    else if(!strcmp(mode,"same"))[display setCursor:first];
    else if(!strcmp(mode,"blank")){CGDisplayHideCursor(CGMainDisplayID());[display setCursor:second];CGDisplayShowCursor(CGMainDisplayID());}
    else if(!strcmp(mode,"hide"))[window orderOut:nil];
    else if(!strcmp(mode,"resize"))[window setContentSize:NSMakeSize(40,40)];
    else if(strcmp(mode,"release"))fired=NO;
    printf("CALLBACK mode=%s serial=%u\n",mode,serial());fflush(stdout);
}
- (void)finish:(id)sender {
    // Each image was drawn once, when its cursor was made, and not for anything that happened since.
    if(!fired||firstDraws!=1||secondDraws!=1||drawsAfterArmed!=0)failures++;
    // Neither cursor keeps its image alive: they were released after the cursors were made.
    if(firstDeallocs!=1||secondDeallocs!=1)failures++;
    printf("LIFETIME deallocs=%d,%d draws=%d,%d\n",firstDeallocs,secondDeallocs,firstDraws,secondDraws);
    printf("RESULT fired=%d drawsAfterArmed=%d failures=%d\n",fired,drawsAfterArmed,failures);fflush(stdout);exit(failures?1:0);
}
@end
int main(void) {@autoreleasepool{
    mode=getenv("CURSOR_CALLBACK_MODE");if(!mode)return 2;
    [CursorApplication sharedApplication];display=[NSClassFromString(@"NSDisplay") currentDisplay];
    // The images are only held by the pool: they are gone once the cursors are made.
    @autoreleasepool {
    first=[[display cursorWithImage:[[[CallbackImage alloc]initTrigger:YES]autorelease] hotSpot:NSMakePoint(3,5)]retain];
    second=[[display cursorWithImage:[[[CallbackImage alloc]initTrigger:NO]autorelease] hotSpot:NSMakePoint(3,5)]retain];
    }
    window=[[NSWindow alloc]initWithContentRect:NSMakeRect(100,100,500,350) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [window center];[window setTitle:@"Cursor callback fixture"];[window setBackgroundColor:[NSColor blackColor]];[window makeKeyAndOrderFront:nil];
    NSWindow *keeper=[[NSWindow alloc]initWithContentRect:NSMakeRect(900,600,50,50) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [keeper setTitle:@"Cursor keeper"];[keeper orderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:.1 target:NSApp selector:@selector(selectWhenEntered:) userInfo:nil repeats:YES];
    [NSApp performSelector:@selector(finish:) withObject:nil afterDelay:30];printf("READY\n");fflush(stdout);[NSApp run];
}}
