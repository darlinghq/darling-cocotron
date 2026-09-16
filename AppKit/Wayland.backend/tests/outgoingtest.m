#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
@interface NSObject (IconRasterProbe)
- (NSData *)pixelsForScale:(int32_t)scale;
+ (id)currentDisplay;
- (id)draggingManager;
- (void)invalidate;
@end
static int ended, failures, ticks, attempts;
static NSPasteboard *retainedBoard;
static NSData *expectedLocalBytes;
static NSString *expectedLocalType;
static id teardownDisplay;
static Ivar managerIvar;
static id sourceView;
static NSString *fileEnv(const char *key) { return [NSString stringWithUTF8String:getenv(key)]; }
static NSArray *filePaths(void) { return getenv("LOCAL_FILES") ? @[@"/guest-only-not-exportable",@"/tmp/private-selection"] : @[fileEnv("FILE_ONE"),fileEnv("FILE_TWO")]; }
static BOOL noStartExpected(void) { return getenv("INVALID_PROVIDER") || getenv("SOURCE_LINK") || getenv("FILE_BAD") || getenv("FILE_NIL"); }
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
- (void)draggingExited:(id<NSDraggingInfo>)info {
    if(getenv("OLD_READ")) {
        [retainedBoard release];retainedBoard=[[info draggingPasteboard]retain];
        BOOL denied=[retainedBoard dataForType:NSStringPboardType]==nil;
        if(!denied)failures++;printf("STALE leaveDenied=%d\n",denied);fflush(stdout);
    }
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info {
    NSDragOperation expected=getenv("TARGET_MOVE")?NSDragOperationMove:NSDragOperationCopy;
    if([info draggingSourceOperationMask]!=expected)failures++;
    printf("PREPARE mask=%lu\n",(unsigned long)[info draggingSourceOperationMask]);fflush(stdout);
    if(getenv("PREPARE_UNMAP"))[[self window]orderOut:nil];
    if(getenv("LIVE_TEARDOWN")) {
        retainedBoard=[[info draggingPasteboard]retain];
        teardownDisplay=[NSClassFromString(@"NSDisplay")currentDisplay];
        managerIvar=class_getInstanceVariable([teardownDisplay class],"_draggingManager");
        id manager=object_getIvar(teardownDisplay,managerIvar);
        [manager invalidate];[manager release]; // Model display's release-before-pasteboards order.
        puts("MANAGER_OWNER_RELEASED");fflush(stdout);
    }
    return YES;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
    if(getenv("PREPARE_UNMAP"))failures++;
    BOOL ok=(getenv("FILE_DRAG") || getenv("LOCAL_FILES"))
        ? [[[info draggingPasteboard] propertyListForType:NSFilenamesPboardType] isEqual:filePaths()]
        : [[ [info draggingPasteboard] stringForType:NSStringPboardType] isEqual:@"Darling outgoing — café"];
    if(getenv("LOCAL_OPAQUE")) ok = [[ [info draggingPasteboard] dataForType:@"DarlingPrivateType"]
        isEqual:[@"opaque local value" dataUsingEncoding:NSUTF8StringEncoding]];
    if(getenv("OLD_READ")) {
        BOOL denied=retainedBoard && [retainedBoard dataForType:NSStringPboardType]==nil;
        if(!denied)failures++;printf("STALE replacementDenied=%d\n",denied);fflush(stdout);
    }
    if(getenv("TWO_DRAGS") && attempts==1)retainedBoard=[[info draggingPasteboard]retain];
    if(getenv("LOCAL_ONLY")) {
        BOOL exact=[[[info draggingPasteboard] dataForType:expectedLocalType]isEqual:expectedLocalBytes]
            && ![[[info draggingPasteboard]types]containsObject:@"DELETE"];
        if(!exact)failures++;printf("PRIVATE_DATA exact=%d\n",exact);fflush(stdout);
    }
    BOOL local=[info draggingSource]==sourceView;
    if(!ok || !local)failures++;
    printf("LOCAL data=%d source=%d\n",ok,local);fflush(stdout);return ok;
}
@end

@interface SourceView : NSView
@end
@implementation SourceView
- (void)drawRect:(NSRect)rect { [[NSColor greenColor] set]; NSRectFill([self bounds]); }
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local { if(!local && getenv("LOCAL_ONLY"))return NSDragOperationNone;
    if(local && getenv("LOCAL_REJECT"))return NSDragOperationNone;
    if(getenv("SOURCE_LINK"))return NSDragOperationLink;
    if(getenv("SOURCE_BOTH"))return NSDragOperationCopy|NSDragOperationMove;
    return getenv("SOURCE_MOVE") ? NSDragOperationMove : NSDragOperationCopy; }
- (void)mouseDown:(NSEvent *)event {
    attempts++;
    NSPasteboard *pb=[NSPasteboard pasteboardWithName:NSDragPboard];
    if((getenv("FILE_DRAG") || getenv("LOCAL_FILES"))) {
        NSArray *types=getenv("FILE_RAW") ? (getenv("REVERSE_RAW")
            ? @[@"text/uri-list",NSFilenamesPboardType] : @[NSFilenamesPboardType,@"text/uri-list"])
            : @[NSStringPboardType,NSFilenamesPboardType];
        [pb declareTypes:types owner:getenv("FILE_NIL") ? self : nil];
        [pb setString:@"fallback must not authorize lost files" forType:NSStringPboardType];
        if(!getenv("FILE_NIL")) [pb setPropertyList:getenv("FILE_BAD")
            ? @[fileEnv("FILE_ONE"),@"/guest-only-not-exportable"] : filePaths() forType:NSFilenamesPboardType];
        if(getenv("FILE_RAW")) [pb setData:[fileEnv("FILE_WIRE") dataUsingEncoding:NSUTF8StringEncoding] forType:@"text/uri-list"];
    } else {
        [pb declareTypes:@[NSStringPboardType] owner:getenv("INVALID_PROVIDER") ? self : nil];
        if (!getenv("INVALID_PROVIDER")) [pb setString:@"Darling outgoing — café" forType:NSStringPboardType];
    }
    if(getenv("LOCAL_OPAQUE")) {
        [pb declareTypes:@[@"DarlingPrivateType"] owner:nil];
        [pb setData:[@"opaque local value" dataUsingEncoding:NSUTF8StringEncoding] forType:@"DarlingPrivateType"];
    }
    if(getenv("LOCAL_ONLY")) {
        [pb addTypes:@[@"DELETE"] owner:nil];[pb setData:[NSData data] forType:@"DELETE"];
        expectedLocalType=getenv("LOCAL_OPAQUE")?@"DarlingPrivateType":(getenv("LOCAL_FILES")?NSFilenamesPboardType:NSStringPboardType);
        [expectedLocalBytes release];expectedLocalBytes=[[pb dataForType:expectedLocalType]copy];
    }
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
    if(getenv("LIVE_TEARDOWN")) {
        [retainedBoard invalidate];
        object_setIvar(teardownDisplay,managerIvar,nil);
        [retainedBoard release];retainedBoard=nil;
        puts("RETAINED_SESSION_CLEANED");fflush(stdout);
    }
    if(getenv("TWO_DRAGS") && attempts==1) {
        if(ended!=1 || failures)exit(1);
        puts("NEXT_READY");fflush(stdout);return;
    }
    printf("RETURN ended=%d failures=%d\n",ended,failures);fflush(stdout);
    exit(ended==(noStartExpected() ? 0 : (getenv("TWO_DRAGS")?2:1)) && failures==0 ? 0:1);
}
- (void)pasteboard:(NSPasteboard *)pasteboard provideDataForType:(NSString *)type {
    if(getenv("FILE_NIL")) { puts("FILE_PROVIDER_NIL");fflush(stdout);return; }
    [pasteboard setString:@"Darling outgoing — café" forType:type];
    [[self window] orderOut:nil];
    puts("PROVIDER_UNMAPPED");fflush(stdout);
}
- (void)tick:(id)sender { ticks++;puts("TIMER_FIRED");fflush(stdout); }
- (void)draggedImage:(NSImage *)image beganAt:(NSPoint)point {
    puts("BEGAN");fflush(stdout);
    if(getenv("TWO_DRAGS") && attempts==2) {
        BOOL denied=[retainedBoard dataForType:NSStringPboardType]==nil;
        if(!denied)failures++;printf("STALE generationDenied=%d\n",denied);fflush(stdout);
    }
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(tick:)
                                  userInfo:nil repeats:NO];
}
- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)point operation:(NSDragOperation)operation {
    ended++;
    if(ticks!=attempts)failures++;
    BOOL cancel=getenv("EXPECT_CANCEL")!=NULL || (getenv("TWO_DRAGS") && attempts==2);
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
        [view registerForDraggedTypes:(getenv("FILE_DRAG") || getenv("LOCAL_FILES")) ? @[NSFilenamesPboardType] : @[NSStringPboardType]];
        if(getenv("LOCAL_OPAQUE")) [view registerForDraggedTypes:@[@"DarlingPrivateType"]];
        [target setContentView:view];[target orderFront:nil];
    }
    [w makeKeyAndOrderFront:nil];puts("READY");fflush(stdout);[NSApp run];return 2;
}
