#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int entered, updated, exited, prepared, performed, concluded, failures;
static const char *mode;
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
    entered++; printf("ENTER types=%s x=%.1f y=%.1f\n", [[[[info draggingPasteboard] types] description] UTF8String], [info draggingLocation].x, [info draggingLocation].y); fflush(stdout);
    dropCheck(([info draggingSourceOperationMask] & NSDragOperationMove) == 0, "copy-only destination mask");
    return NSDragOperationCopy;
}
- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) info { updated++; return NSDragOperationCopy; }
- (void) draggingExited: (id<NSDraggingInfo>) info { exited++; printf("EXIT\n"); fflush(stdout); }
- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) info {
    prepared++; return strcmp(mode, "prepare-reject") != 0;
}
- (BOOL) performDragOperation: (id<NSDraggingInfo>) info {
    performed++;
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
    if (!strcmp(mode, "accept")) {
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
        [view registerForDraggedTypes: @[NSStringPboardType]];
        [window setContentView: view]; [window makeKeyAndOrderFront: nil];
        Driver *driver = [Driver new];
        [NSTimer scheduledTimerWithTimeInterval: 18 target: driver selector: @selector(done:) userInfo: nil repeats: NO];
        printf("READY mode=%s\n",mode); fflush(stdout);
        [NSApp run];
    }
    return 2;
}
