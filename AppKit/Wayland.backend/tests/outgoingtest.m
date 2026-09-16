#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
static int ended, failures, ticks;
static id sourceView;
@interface TargetView : NSView
@end
@implementation TargetView
- (void)drawRect:(NSRect)rect { [[NSColor blueColor] set];NSRectFill([self bounds]); }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info { return NSDragOperationCopy; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
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
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local { return (local && getenv("LOCAL_REJECT")) ? NSDragOperationNone : NSDragOperationCopy; }
- (void)mouseDown:(NSEvent *)event {
    NSPasteboard *pb=[NSPasteboard pasteboardWithName:NSDragPboard];
    [pb declareTypes:@[NSStringPboardType] owner:getenv("INVALID_PROVIDER") ? self : nil];
    if (!getenv("INVALID_PROVIDER"))
        [pb setString:@"Darling outgoing — café" forType:NSStringPboardType];
    puts("STARTING");fflush(stdout);
    [self dragImage:nil at:NSMakePoint(10,10) offset:NSZeroSize event:event
        pasteboard:pb source:self slideBack:NO];
    printf("RETURN ended=%d failures=%d\n",ended,failures);fflush(stdout);
    exit(ended==(getenv("INVALID_PROVIDER") ? 0 : 1) && failures==0 ? 0:1);
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
    if(operation!=(cancel?NSDragOperationNone:NSDragOperationCopy))failures++;
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
