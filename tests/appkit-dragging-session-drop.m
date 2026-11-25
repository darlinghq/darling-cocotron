// Copyright (C) 2026 Lubos Dolezel
//
// A drag begun with -[NSView beginDraggingSessionWithItems:event:source:] and dropped on a window
// of the same application, for the harness appkit-dragging-session-x11.sh, which presses the left
// button in the window "source", moves to the window "target" and releases it there.
// The source starts the drag from its first -mouseDragged: and prints what its session tells it:
//   "mask <context>"           -draggingSession:sourceOperationMaskForDraggingContext:
//   "began"                    -draggingSession:willBeginAtPoint:
//   "ended <operation>"        -draggingSession:endedAtPoint:operation:
//   "legacy"                   any of the pre-10.7 source messages, which a session never sends
// and the target what its dragging info says:
//   "entered <valid items>"    -draggingEntered:, with numberOfValidItemsForDrop
//   "dropped <string>"         -performDragOperation:, for each string its enumeration finds
// The program prints "READY" once the windows are shown and exits after <seconds> (the first
// argument, default 20) or once the source has heard the drag end.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#pragma clang diagnostic ignored "-Wdeprecated-implementations"

@interface SourceView : NSView <NSDraggingSource> {
    BOOL _started;
}
@end

@implementation SourceView
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.3 green: 0.5 blue: 0.8 alpha: 1] setFill];
    NSRectFill(rect);
}
- (void) mouseDown: (NSEvent *) event {
}
- (void) mouseDragged: (NSEvent *) event {
    if (_started)
        return;
    _started = YES;
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter: @"payload"];
    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(20, 20)];
    [item setDraggingFrame: NSMakeRect(point.x - 10, point.y - 10, 20, 20) contents: image];
    [self beginDraggingSessionWithItems: @[ item ] event: event source: self];
}
- (NSDragOperation) draggingSession: (NSDraggingSession *) session
    sourceOperationMaskForDraggingContext: (NSDraggingContext) context
{
    printf("mask %s\n", context == NSDraggingContextWithinApplication ? "within" : "outside");
    fflush(stdout);
    return NSDragOperationCopy;
}
- (void) draggingSession: (NSDraggingSession *) session willBeginAtPoint: (NSPoint) point {
    printf("began\n");
    fflush(stdout);
}
- (void) draggingSession: (NSDraggingSession *) session
            endedAtPoint: (NSPoint) point
               operation: (NSDragOperation) operation
{
    printf("ended %s\n", operation == NSDragOperationCopy ? "copy" : operation == NSDragOperationNone ? "none" : "other");
    fflush(stdout);
    exit(0);
}
- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) local {
    printf("legacy\n");
    return NSDragOperationCopy;
}
- (void) draggedImage: (NSImage *) image beganAt: (NSPoint) point {
    printf("legacy\n");
}
- (void) draggedImage: (NSImage *) image endedAt: (NSPoint) point operation: (NSDragOperation) operation {
    printf("legacy\n");
}
@end

@interface TargetView : NSView
@end

@implementation TargetView
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.8 green: 0.5 blue: 0.3 alpha: 1] setFill];
    NSRectFill(rect);
}
- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) info {
    printf("entered %ld\n", (long) [info numberOfValidItemsForDrop]);
    fflush(stdout);
    return NSDragOperationCopy;
}
- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) info {
    return NSDragOperationCopy;
}
- (BOOL) performDragOperation: (id<NSDraggingInfo>) info {
    [info enumerateDraggingItemsWithOptions: 0
                                    forView: self
                                    classes: @[ [NSString class] ]
                              searchOptions: @{}
                                 usingBlock: ^(NSDraggingItem *item, NSInteger idx, BOOL *stop) {
        printf("dropped %s\n", [[item.item description] UTF8String]);
    }];
    fflush(stdout);
    return YES;
}
@end

static NSWindow *makeWindow(NSString *title, NSRect frame, NSView *view) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    window.title = title;
    view.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    window.contentView = view;
    [window makeKeyAndOrderFront: nil];
    return window;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 20;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        makeWindow(@"source", NSMakeRect(100, 300, 200, 200), [[SourceView alloc] init]);
        TargetView *target = [[TargetView alloc] init];
        makeWindow(@"target", NSMakeRect(400, 300, 200, 200), target);
        [target registerForDraggedTypes: @[ NSPasteboardTypeString ]];
        [NSApp activateIgnoringOtherApps: YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            printf("READY\n");
            fflush(stdout);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t) (seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            printf("timeout\n");
            exit(1);
        });
        [NSApp run];
    }
    return 0;
}
