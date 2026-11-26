// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// A dragging session between two windows, for the harnesses
// appkit-dragging-session-x11.sh and appkit-dragging-session-wayland.sh, which
// press the left button in "drag-source", move to "drag-target" and release:
//   drag-source  starts a session with two file URLs from its first
//                -mouseDragged: after a press, offering copy and move, and
//                prints its NSDraggingSource callbacks:
//                  SOURCE willBegin / SOURCE moved / SOURCE ended op=<n>
//                It also has the pre-10.7 source methods, which a session never
//                sends; each prints SOURCE legacy.
//   drag-target  takes file URLs, choosing move when the mask has it and copy
//                otherwise, and prints
//                  TARGET mask=<n> (whenever the mask it is offered changes)
//                  TARGET drop source=<yes|no> valid=<n> enumerated=<n> urls=<path>,<path>
//                (source: whether -draggingSource is the source view, as it is for
//                a drag within the application)
// The documented contract: the session callbacks come in that order, ended
// carries the operation the target took, and the mask a destination sees is
// narrowed by the modifier keys held (NSDraggingInfo).
// Prints "READY" once the windows are shown, and exits after <seconds> (the
// first argument, default 20).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#pragma clang diagnostic ignored "-Wdeprecated-implementations"

static void say(NSString *line)
{
    printf("%s\n", [line UTF8String]);
    fflush(stdout);
}

@interface SourceView : NSView <NSDraggingSource> {
    BOOL _started;
}
@end
@implementation SourceView
- (BOOL) isOpaque {
    return YES;
}
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.3 green: 0.5 blue: 0.8 alpha: 1] setFill];
    NSRectFill(rect);
}
- (void) mouseDown: (NSEvent *) event {
    _started = NO;
}
- (void) mouseDragged: (NSEvent *) event {
    if (_started)
        return;
    _started = YES;
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(32, 32)] autorelease];
    [image lockFocus];
    [[NSColor orangeColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 32, 32));
    [image unlockFocus];
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    NSMutableArray *items = [NSMutableArray array];
    NSArray *paths = [NSArray arrayWithObjects: @"/private/var/tmp/drag-a", @"/private/var/tmp/drag-b", nil];
    for (NSUInteger i = 0; i < [paths count]; i++) {
        NSDraggingItem *item =
            [[[NSDraggingItem alloc] initWithPasteboardWriter: [NSURL fileURLWithPath: [paths objectAtIndex: i]]]
                autorelease];
        [item setDraggingFrame: NSMakeRect(point.x - 16 + 8 * i, point.y - 16 - 8 * i, 32, 32) contents: image];
        [items addObject: item];
    }
    [self beginDraggingSessionWithItems: items event: event source: self];
}
- (NSDragOperation) draggingSession: (NSDraggingSession *) session
    sourceOperationMaskForDraggingContext: (NSDraggingContext) context
{
    return NSDragOperationCopy | NSDragOperationMove;
}
- (void) draggingSession: (NSDraggingSession *) session willBeginAtPoint: (NSPoint) screenPoint {
    say(@"SOURCE willBegin");
}
- (void) draggingSession: (NSDraggingSession *) session movedToPoint: (NSPoint) screenPoint {
    say(@"SOURCE moved");
}
- (void) draggingSession: (NSDraggingSession *) session
            endedAtPoint: (NSPoint) screenPoint
               operation: (NSDragOperation) operation
{
    say([NSString stringWithFormat: @"SOURCE ended op=%lu", (unsigned long) operation]);
}
- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) local {
    say(@"SOURCE legacy");
    return NSDragOperationCopy;
}
- (void) draggedImage: (NSImage *) image beganAt: (NSPoint) point {
    say(@"SOURCE legacy");
}
- (void) draggedImage: (NSImage *) image movedTo: (NSPoint) point {
    say(@"SOURCE legacy");
}
- (void) draggedImage: (NSImage *) image endedAt: (NSPoint) point operation: (NSDragOperation) operation {
    say(@"SOURCE legacy");
}
@end

@interface TargetView : NSView {
    NSDragOperation _lastMask;
}
@end
@implementation TargetView
- (instancetype) initWithFrame: (NSRect) frame {
    if ((self = [super initWithFrame: frame]))
        [self registerForDraggedTypes: [NSArray arrayWithObject: NSPasteboardTypeFileURL]];
    return self;
}
- (BOOL) isOpaque {
    return YES;
}
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.4 green: 0.7 blue: 0.4 alpha: 1] setFill];
    NSRectFill(rect);
}
- (NSDragOperation) choose: (id<NSDraggingInfo>) info {
    NSDragOperation mask = [info draggingSourceOperationMask];
    if (mask != _lastMask) {
        _lastMask = mask;
        say([NSString stringWithFormat: @"TARGET mask=%lu", (unsigned long) mask]);
    }
    if (mask & NSDragOperationMove)
        return NSDragOperationMove;
    if (mask & NSDragOperationCopy)
        return NSDragOperationCopy;
    return NSDragOperationNone;
}
- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) info {
    _lastMask = 0;
    return [self choose: info];
}
- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) info {
    return [self choose: info];
}
- (BOOL) performDragOperation: (id<NSDraggingInfo>) info {
    NSDictionary *options = [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES]
                                                        forKey: NSPasteboardURLReadingFileURLsOnlyKey];
    NSArray *urls = [[info draggingPasteboard] readObjectsForClasses: [NSArray arrayWithObject: [NSURL class]]
                                                             options: options];
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *url in urls)
        [paths addObject: [url path]];
    __block NSInteger enumerated = 0;
    [info enumerateDraggingItemsWithOptions: 0
                                    forView: self
                                    classes: [NSArray arrayWithObject: [NSURL class]]
                              searchOptions: options
                                 usingBlock: ^(NSDraggingItem *item, NSInteger index, BOOL *stop) {
                                     if ([[item item] isKindOfClass: [NSURL class]])
                                         enumerated++;
                                 }];
    say([NSString stringWithFormat: @"TARGET drop source=%@ valid=%ld enumerated=%ld urls=%@",
                                    [[info draggingSource] isKindOfClass: [SourceView class]] ? @"yes" : @"no",
                                    (long) [info numberOfValidItemsForDrop], (long) enumerated,
                                    [paths componentsJoinedByString: @","]]);
    return YES;
}
@end

static NSWindow *makeWindow(NSString *title, NSRect frame, NSView *content)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: title];
    [window setContentView: content];
    [window orderFront: nil];
    return window;
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    makeWindow(@"drag-source", NSMakeRect(100, 500, 200, 150), [[[SourceView alloc] init] autorelease]);
    makeWindow(@"drag-target", NSMakeRect(500, 500, 200, 150), [[[TargetView alloc] init] autorelease]);
    [NSApp activateIgnoringOtherApps: YES];
    say(@"READY");

    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: argc > 1 ? atof(argv[1]) : 20];
    while ([until timeIntervalSinceNow] > 0) {
        NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
        [inner release];
    }
    [pool release];
    return 0;
}
