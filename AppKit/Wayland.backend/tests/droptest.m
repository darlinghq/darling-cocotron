#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int entered, updated, exited, prepared, performed, concluded, failures;
static const char *mode;
static NSString *fileEnv(const char *key) { return [NSString stringWithUTF8String:getenv(key)]; }
static void dropCheck(BOOL value, const char *what) {
    printf("CHECK %s %s\n", value ? "PASS" : "FAIL", what); fflush(stdout);
    if (!value) failures++;
}
@interface DropView : NSView
@end
@implementation DropView
- (void) drawRect: (NSRect) rect {
    [[NSColor greenColor] setFill]; NSRectFill([self bounds]);
}
- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) info {
    dropCheck(![[[info draggingPasteboard] types] containsObject:@"DELETE"] && [[info draggingPasteboard] dataForType:@"DELETE"] == nil, "DELETE control target hidden");
    entered++; printf("ENTER types=%s x=%.1f y=%.1f\n", [[[[info draggingPasteboard] types] description] UTF8String], [info draggingLocation].x, [info draggingLocation].y); fflush(stdout);
    dropCheck([info draggingSourceOperationMask] == ((!strcmp(mode,"move-only") || !strcmp(mode,"move-accept")) ? NSDragOperationMove : NSDragOperationCopy), "source action mask");
    return !strcmp(mode,"move-accept") ? NSDragOperationMove : NSDragOperationCopy;
}
- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) info { updated++; return !strcmp(mode,"move-accept") ? NSDragOperationMove : NSDragOperationCopy; }
- (void) draggingExited: (id<NSDraggingInfo>) info { exited++; printf("EXIT\n"); fflush(stdout); }
- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) info {
    prepared++;
    dropCheck([info draggingSourceOperationMask] == (!strcmp(mode,"move-accept") ? NSDragOperationMove : NSDragOperationCopy), "negotiated operation in prepare");
    return strcmp(mode, "prepare-reject") != 0;
}
- (BOOL) performDragOperation: (id<NSDraggingInfo>) info {
    performed++;
    if(getenv("FILE_DRAG")) {
        NSPasteboard *pb=[info draggingPasteboard];
        NSArray *files=[pb propertyListForType:NSFilenamesPboardType];
        dropCheck([[[pb types] description] length]>0 && [[pb types] containsObject:@"text/uri-list"] && [[pb types] containsObject:NSFilenamesPboardType],"raw and converted types exposed");
        dropCheck(getenv("FILE_BAD") ? files==nil : [files isEqual:@[fileEnv("FILE_ONE"),fileEnv("FILE_TWO")]],"atomic filename conversion");
        NSData *raw=[pb dataForType:@"text/uri-list"];
        dropCheck([raw isEqual:[fileEnv("FILE_WIRE") dataUsingEncoding:NSUTF8StringEncoding]],"raw URI preserved after conversion");
        if(!getenv("FILE_BAD"))dropCheck([[pb propertyListForType:NSFilenamesPboardType] isEqual:files],"converted cache stable");
        return YES; // Deliberately accepts even failed conversion; backend must refuse finish.
    }
    NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
    NSString *value = [[info draggingPasteboard] stringForType: NSStringPboardType];
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - started;
    if (!strcmp(mode, "timeout")) {
        printf("TIMEOUT seconds=%.3f\n", elapsed);
        dropCheck(elapsed >= 4.8 && elapsed < 7, "actual five-second transfer timeout");
    }
    if (!strcmp(mode, "oversize") || !strcmp(mode, "timeout")) {
        dropCheck(value == nil, "bounded transfer rejected"); return NO;
    }
    dropCheck([value isEqual: @"Native drop: ăîșț 日本語"], "Unicode payload exact");
    dropCheck([[info draggingPasteboard] dataForType: NSStringPboardType] != nil, "cached repeat read");
    return value != nil;
}
- (void) concludeDragOperation: (id<NSDraggingInfo>) info { concluded++; printf("CONCLUDE\n"); fflush(stdout); }
@end
@interface Driver : NSObject
@end
@implementation Driver
- (void) done: (NSTimer *) timer {
    if(getenv("FILE_BAD")) {
        dropCheck(prepared==1 && performed==1 && concluded==0,"conversion failure blocks completion");
    } else if (!strcmp(mode, "accept") || !strcmp(mode,"move-accept")) {
        dropCheck(entered > 0 && updated > 0 && prepared == 1 && performed == 1 && concluded == 1, "accepted callback lifecycle");
    } else if (!strcmp(mode, "leave")) {
        dropCheck(entered > 0 && exited > 0 && prepared == 0 && performed == 0 && concluded == 0, "leave without drop");
    } else if (!strcmp(mode, "unsupported") || !strcmp(mode, "move-only")) {
        dropCheck(prepared == 0 && performed == 0 && concluded == 0, "unsupported drop rejected");
    } else if (!strcmp(mode, "prepare-reject")) {
        dropCheck(prepared == 1 && performed == 0 && concluded == 0, "prepare refusal respected");
    } else if (!strcmp(mode, "oversize") || !strcmp(mode, "timeout")) {
        dropCheck(performed == 1 && concluded == 0, "failed transfer not concluded");
    }
    dropCheck([[[NSPasteboard generalPasteboard] stringForType: NSStringPboardType] isEqual: @"clipboard untouched"], "clipboard independent");
    printf("RESULT mode=%s entered=%d updated=%d exited=%d prepared=%d performed=%d concluded=%d failures=%d\n", mode,entered,updated,exited,prepared,performed,concluded,failures); fflush(stdout);
    exit(failures ? 1 : 0);
}
@end
int main(void) {
    @autoreleasepool {
        mode = getenv("DROP_MODE") ?: "accept";
        [NSApplication sharedApplication];
        NSPasteboard *board = [NSPasteboard generalPasteboard];
        [board declareTypes: @[NSStringPboardType] owner: nil];
        [board setString: @"clipboard untouched" forType: NSStringPboardType];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0,0,400,300) styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
        [window setTitle: @"Wayland drop target"];
        DropView *view = [[DropView alloc] initWithFrame: NSMakeRect(0,0,400,300)];
        [view registerForDraggedTypes: getenv("FILE_DRAG") ? @[NSFilenamesPboardType] : @[NSStringPboardType]];
        [window setContentView: view]; [window makeKeyAndOrderFront: nil];
        Driver *driver = [Driver new];
        [NSTimer scheduledTimerWithTimeInterval: 18 target: driver selector: @selector(done:) userInfo: nil repeats: NO];
        printf("READY mode=%s\n",mode); fflush(stdout);
        [NSApp run];
    }
    return 2;
}
