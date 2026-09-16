#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
@interface NSObject (IconRasterProbe)
- (NSData *)pixelsForScale:(int32_t)scale;
@end
static int ended, failures, ticks;
static id sourceView;
@interface TargetView : NSView
@end
@implementation TargetView
- (void)drawRect:(NSRect)rect { [[NSColor blueColor] set];NSRectFill([self bounds]); }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return getenv("TARGET_MOVE") ? NSDragOperationMove : NSDragOperationCopy; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
    if(getenv("NESTED_DROP")) {
        puts("NEGOTIATING");fflush(stdout);
        NSDate *until=[NSDate dateWithTimeIntervalSinceNow:1.5];
        while([until timeIntervalSinceNow]>0) {
            [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate date]
                                 inMode:NSDefaultRunLoopMode dequeue:YES];
            usleep(1000);
        }
        return NSDragOperationNone;
    }
    return [self draggingEntered:info];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info {
    NSDragOperation expected=getenv("TARGET_MOVE")?NSDragOperationMove:NSDragOperationCopy;
    if([info draggingSourceOperationMask]!=expected)failures++;
    printf("PREPARE mask=%lu\n",(unsigned long)[info draggingSourceOperationMask]);fflush(stdout);
    if(getenv("PREPARE_UNMAP"))[[self window]orderOut:nil];
    return YES;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    if(getenv("PREPARE_UNMAP"))failures++;
    BOOL ok=[[[info draggingPasteboard]stringForType:NSStringPboardType]isEqual:@"Darling outgoing — café"];
    BOOL local=[info draggingSource]==sourceView;
    if(!ok || !local)failures++;
    printf("LOCAL data=%d source=%d\n",ok,local);fflush(stdout);return ok;
}
@end

@interface SourceView : NSView
@end
@implementation SourceView
- (void)drawRect:(NSRect)rect { [[NSColor greenColor] set]; NSRectFill([self bounds]); }
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local { if(local && getenv("LOCAL_REJECT"))return NSDragOperationNone;
    if(getenv("SOURCE_LINK"))return NSDragOperationLink;
    if(getenv("SOURCE_BOTH"))return NSDragOperationCopy|NSDragOperationMove;
    return getenv("SOURCE_MOVE") ? NSDragOperationMove : NSDragOperationCopy; }
- (void)mouseDown:(NSEvent *)event {
    NSPasteboard *pb=[NSPasteboard pasteboardWithName:NSDragPboard];
    [pb declareTypes:@[NSStringPboardType] owner:getenv("INVALID_PROVIDER") ? self : nil];
    if (!getenv("INVALID_PROVIDER"))
        [pb setString:@"Darling outgoing — café" forType:NSStringPboardType];
    puts("STARTING");fflush(stdout);
    NSImage *image=nil;
    NSPoint imageLocation=NSMakePoint(10,10);
    if(getenv("DRAG_ICON")) {
        NSBitmapImageRep *rep=[[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:32 pixelsHigh:24 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
            isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:0
            bytesPerRow:128 bitsPerPixel:32] autorelease];
        unsigned char *bytes=[rep bitmapData];
        for(int y=0;y<24;y++)for(int x=0;x<32;x++) {
            unsigned char *p=bytes+y*128+x*4;
            BOOL transparent=x>=16 && y>=12;
            p[0]=(x<16)?255:0; p[1]=(y>=12 || x>=16)?255:0;
            p[2]=(y<12)?255:0; p[3]=transparent?0:255;
            if(transparent)p[0]=p[1]=p[2]=0;
        }
        image=[[[NSImage alloc]initWithSize:NSMakeSize(32,24)]autorelease];[image addRepresentation:rep];
        if(getenv("ICON_RASTER_OUT")) {
            id raster=[[NSClassFromString(@"WaylandCursor") alloc]initWithImage:image hotSpot:NSZeroPoint];
            NSData *pixels=[raster pixelsForScale:atoi(getenv("ICON_SCALE"))];
            BOOL wrote=[pixels writeToFile:[NSString stringWithUTF8String:getenv("ICON_RASTER_OUT")] atomically:NO];
            printf("RASTER_DUMP bytes=%lu wrote=%d\n",(unsigned long)[pixels length],wrote);fflush(stdout);
            [raster release];
        }
        NSPoint pointer=[event locationInWindow];imageLocation=NSMakePoint(pointer.x+20,pointer.y-34);
    }
    [self dragImage:image at:imageLocation offset:NSZeroSize event:event
        pasteboard:pb source:self slideBack:NO];
    printf("RETURN ended=%d failures=%d\n",ended,failures);fflush(stdout);
    exit(ended==((getenv("INVALID_PROVIDER") || getenv("SOURCE_LINK")) ? 0 : 1) && failures==0 ? 0:1);
}
- (void)pasteboard:(NSPasteboard *)pasteboard provideDataForType:(NSString *)type {
    [pasteboard setString:@"Darling outgoing — café" forType:type];
    [[self window] orderOut:nil];
    puts("PROVIDER_UNMAPPED");fflush(stdout);
}
- (void)tick:(id)sender { ticks++;puts("TIMER_FIRED");fflush(stdout); }
- (void)draggedImage:(NSImage *)image beganAt:(NSPoint)point {
    puts("BEGAN");fflush(stdout);
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(tick:)
                                  userInfo:nil repeats:NO];
}
- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)point operation:(NSDragOperation)operation {
    ended++;
    if(ticks!=1)failures++;
    BOOL cancel=getenv("EXPECT_CANCEL")!=NULL;
    if(operation!=(cancel?NSDragOperationNone:(getenv("EXPECT_MOVE")?NSDragOperationMove:NSDragOperationCopy)))failures++;
    printf("ENDED op=%lu\n",(unsigned long)operation);fflush(stdout);
}
@end
int main(void) {
    [NSAutoreleasePool new];[NSApplication sharedApplication];
    NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,300,220)
        styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    [w setTitle:@"Darling outgoing source"];
    sourceView=[[[SourceView alloc]initWithFrame:NSMakeRect(0,0,300,220)]autorelease];
    [w setContentView:sourceView];
    if(getenv("LOCAL_DROP")) {
        NSWindow *target=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,300,220)
            styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
        [target setTitle:@"Darling local target"];
        TargetView *view=[[[TargetView alloc]initWithFrame:NSMakeRect(0,0,300,220)]autorelease];
        [view registerForDraggedTypes:@[NSStringPboardType]];
        [target setContentView:view];[target orderFront:nil];
    }
    [w makeKeyAndOrderFront:nil];puts("READY");fflush(stdout);[NSApp run];return 2;
}
