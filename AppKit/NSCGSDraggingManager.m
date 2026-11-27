/* Copyright (c) 2008 Johannes Fortmann

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "NSCGSDraggingManager.h"
#import "NSCGSDropSession.h"
#import "NSPasteboardAliases.h"
#import <AppKit/NSDisplay.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSWindow.h>
#import <CoreGraphics/CGSDrag.h>
#import <Foundation/NSDate.h>

// The events a drag consumes while it holds the pointer: the motion that follows it and the release that ends it.
// Everything else the application receives is left in the queue for when the drag is over.
static const NSEventMask NSCGSDragEventMask = NSLeftMouseUpMask | NSLeftMouseDraggedMask | NSMouseMovedMask;

// What a drag offers other applications: the pasteboard handed to -dragImage:..., read when a destination asks
// for it. Nothing is copied up front, so a payload that does not fit in memory twice still drags.
@interface NSCGSDragSource : NSObject <CGSDragSource> {
    NSPasteboard *_pasteboard;
    id _source;
}
- (id) initWithPasteboard: (NSPasteboard *) pasteboard source: (id) source;
@end

@implementation NSCGSDragSource

- (id) initWithPasteboard: (NSPasteboard *) pasteboard source: (id) source {
    if ((self = [super init])) {
        _pasteboard = [pasteboard retain];
        _source = [source retain];
    }
    return self;
}

- (void) dealloc {
    [_pasteboard release];
    [_source release];
    [super dealloc];
}

// A type the application promised but cannot produce is left unanswered: the destination then gets a refusal for
// that name instead of an empty answer it would have to tell apart from a real value.
- (NSData *) selectionDataForType: (NSString *) type {
    return [_pasteboard dataForType: type];
}

- (void) selectionLost {
}

- (CGSDragOperation) dragOperationsNarrowing: (CGSDragOperation) offered {
    return [NSDraggingSession _operationMask: offered narrowedForSource: _source];
}

@end

// What an AppKit window does with the drags over it.
@interface NSCGSDragDestination : NSObject <CGSDragDestination> {
    NSWindow *_window; // not retained: the destination goes with the window system's window, which the window owns
    NSCGSDropSession *_current;
}
- (id) initWithWindow: (NSWindow *) window;
@end

@implementation NSCGSDragDestination

- (id) initWithWindow: (NSWindow *) window {
    if ((self = [super init]))
        _window = window;
    return self;
}

- (void) dealloc {
    [_current release];
    [super dealloc];
}

// The session of the window system's session that is being reported, made when it first is.
- (NSCGSDropSession *) sessionFor: (id<CGSDropSession>) session {
    if ([_current dropSession] != session) {
        [_current release];
        id local = [session fromThisProcess] ? [[NSDraggingManager draggingManager] localDraggingSource] : nil;
        _current = [[NSCGSDropSession alloc] initWithSession: session window: _window localSource: local];
    }
    return _current;
}

- (CGSDragOperation) dropSession: (id<CGSDropSession>) session enteredAtPoint: (CGPoint) point {
    return [[self sessionFor: session] updateAtPoint: point];
}

- (CGSDragOperation) dropSession: (id<CGSDropSession>) session updatedAtPoint: (CGPoint) point {
    return [[self sessionFor: session] updateAtPoint: point];
}

- (void) dropSessionExited: (id<CGSDropSession>) session {
    [[self sessionFor: session] leave];
    // A session that is over must not keep the window alive, which owns this destination.
    [_current release];
    _current = nil;
}

- (CGSDragOperation) dropSession: (id<CGSDropSession>) session performWithOperation: (CGSDragOperation) operation {
    NSDragOperation performed = [[self sessionFor: session] performDropWithOperation: operation];
    [_current release];
    _current = nil;
    return performed;
}

@end

static NSCGSDraggingManager *sharedManager;

@implementation NSCGSDraggingManager

+ (NSCGSDraggingManager *) sharedManager {
    if (!_CGSDragAvailable())
        return nil;
    if (sharedManager == nil)
        sharedManager = [[NSCGSDraggingManager alloc] init];
    return sharedManager;
}

- (id) localDraggingSource {
    return _dragging ? _localSource : nil;
}

- (void) registerWindow: (NSWindow *) window dragTypes: (NSArray *) types {
    // Every window of the window system is offered to drags: it takes the ones its views and itself registered
    // for, and answers the others with a refusal.
    NSInteger number = [window windowNumber];
    if (number <= 0)
        return;
    NSCGSDragDestination *destination = [[NSCGSDragDestination alloc] initWithWindow: window];
    _CGSDragSetDestination((CGSWindowID) number, destination);
    [destination release];
}

- (void) unregisterWindow: (NSWindow *) window {
    NSInteger number = [window windowNumber];
    if (number > 0)
        _CGSDragSetDestination((CGSWindowID) number, nil);
}

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack
{
    if (_dragging) {
        NSLog(@"A drag is already running, this one never started");
        return;
    }

    // The window system holds the pointer for the window the drag started in, so its motion and button events keep
    // arriving as the normal mouse events.
    NSWindow *originWindow = [event window];
    NSInteger origin = originWindow != nil ? [originWindow windowNumber] : 0;
    if (origin <= 0) {
        NSLog(@"The drag event has no window to hold the pointer for, the drag never started");
        return;
    }

    // What other applications may do with the dragged items, and what this application's own windows may. A source
    // that does not say allows a copy to both.
    NSDragOperation operations = NSDragOperationCopy, localOperations = NSDragOperationCopy;
    if ([source respondsToSelector: @selector(draggingSourceOperationMaskForLocal:)]) {
        operations = [source draggingSourceOperationMaskForLocal: NO];
        localOperations = [source draggingSourceOperationMaskForLocal: YES];
    }

    NSCGSDragSource *dragSource = [[NSCGSDragSource alloc] initWithPasteboard: pasteboard source: source];
    CGSDragDescription description = {
        .window = (CGSWindowID) origin,
        .types = NSPasteboardCanonicalTypes([pasteboard types]),
        .source = dragSource,
        .operations = operations,
        .localOperations = localOperations,
    };
    CGImageRef cgImage = NULL;
    if (image != nil && _CGSDragUsesImage()) {
        NSPoint pointer = [event locationInWindow];
        description.imageOffset = CGPointMake(location.x - pointer.x,
                                              pointer.y - location.y - ceil([image size].height));
        // The image is drawn for the sharpest screen: the window system scales it down to the others.
        CGFloat scale = 1;
        for (NSScreen *screen in [NSScreen screens])
            scale = MAX(scale, [screen backingScaleFactor]);
        NSRect proposed = NSMakeRect(0, 0, [image size].width * scale, [image size].height * scale);
        cgImage = [image CGImageForProposedRect: &proposed context: nil hints: nil];
        description.image = cgImage;
        description.imageScale = scale;
    }

    // The source is told where the image's corner is on the screen: where it started, moved with the mouse
    NSPoint imageOrigin = [originWindow convertRectToScreen: NSMakeRect(location.x, location.y, 0, 0)].origin;
    NSPoint mouseStart = [NSEvent mouseLocation];
    NSPoint imageAt = imageOrigin;

    id<CGSDragSession> session = _CGSDragBegin(&description);
    [dragSource release];
    if (session == nil)
        return;

    NSImage *heldImage = [image retain];
    id heldSource = [source retain];
    NSDragOperation result = NSDragOperationNone;
    BOOL began = NO;
    _dragging = YES;
    _localSource = heldSource;
    @try {
        began = YES;
        if ([heldSource respondsToSelector: @selector(draggedImage:beganAt:)])
            [heldSource draggedImage: heldImage beganAt: imageOrigin];

        while (![session finished]) {
            NSEvent *next = [[NSDisplay currentDisplay]
                    nextEventMatchingMask: NSCGSDragEventMask
                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.01]
                                 inMode: NSDefaultRunLoopMode
                                dequeue: YES];
            // The release is the drag's end. Any other event that reaches here is the pointer the drag is
            // holding; the application's own events are not in the mask and stay queued for when it is over.
            // Events can keep arriving all through a drag, so the pointer is looked at after each.
            if (next != nil && next.type == NSLeftMouseUp)
                break;
            if ([session update]) {
                NSPoint mouse = [NSEvent mouseLocation];
                imageAt = NSMakePoint(imageOrigin.x + mouse.x - mouseStart.x, imageOrigin.y + mouse.y - mouseStart.y);
                if ([heldSource respondsToSelector: @selector(draggedImage:movedTo:)])
                    [heldSource draggedImage: heldImage movedTo: imageAt];
            }
        }

        // The window system waits for the destination's answers while it holds the drag, and they arrive as events
        // that have to be handled meanwhile.
        result = [session concludePumping: ^(NSDate *until) {
            @autoreleasepool {
                [[NSDisplay currentDisplay] nextEventMatchingMask: NSCGSDragEventMask
                                                        untilDate: until
                                                           inMode: NSDefaultRunLoopMode
                                                          dequeue: YES];
            }
        }];
    } @finally {
        _dragging = NO;
        _localSource = nil;
        [session close];
        [session release];
        @try {
            if (began && [heldSource respondsToSelector: @selector(draggedImage:endedAt:operation:)])
                [heldSource draggedImage: heldImage endedAt: imageAt operation: result];
        } @finally {
            [heldSource release];
            [heldImage release];
        }
    }
}

@end
