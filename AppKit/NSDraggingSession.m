/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSDraggingSession.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSPasteboardItem.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSValue.h>
#include <stdatomic.h>

@interface NSPasteboard (NSDraggingItemReading)
- (id) _objectForItem: (NSPasteboardItem *) item
              classes: (NSArray<Class> *) classArray
              options: (NSDictionary *) options;
@end

@interface NSView (NSDraggingSession)
- (void) _dragImage: (NSImage *) image
     atWindowLocation: (NSPoint) location
               offset: (NSSize) offset
                event: (NSEvent *) event
           pasteboard: (NSPasteboard *) pasteboard
               source: (id) source
            slideBack: (BOOL) slideBack;
@end

static NSRect screenRectFromView(NSView *view, NSRect rect) {
    rect = [view convertRect: rect toView: nil];
    NSWindow *window = [view window];
    return window != nil ? [window convertRectToScreen: rect] : rect;
}

static NSRect viewRectFromScreen(NSView *view, NSRect rect) {
    NSWindow *window = [view window];
    if (window != nil)
        rect = [window convertRectFromScreen: rect];
    return [view convertRect: rect fromView: nil];
}

static NSPoint screenPointOfEvent(NSEvent *event) {
    NSPoint point = [event locationInWindow];
    NSWindow *window = [event window];
    return window != nil ? [window convertRectToScreen: NSMakeRect(point.x, point.y, 0, 0)].origin : point;
}

static NSInteger nextSequenceNumber(void) {
    static _Atomic NSInteger last;
    return atomic_fetch_add(&last, 1) + 1;
}

// The items of a pasteboard read as the first of the classes each can be read as, with their frames, in order.
// The block may change an item's frame and image; what it sets is written back through `update`.
static void enumerateItems(NSPasteboard *pasteboard, NSArray<NSValue *> *frames, NSArray<NSDraggingItem *> *images,
                           NSView *view, NSArray<Class> *classArray, NSDictionary *searchOptions,
                           void (^block)(NSDraggingItem *, NSInteger, BOOL *),
                           void (^update)(NSInteger index, NSDraggingItem *item)) {
    NSArray *items = [pasteboard pasteboardItems];
    BOOL stop = NO;
    for (NSUInteger index = 0; index < [items count] && !stop; index++) {
        id object = [pasteboard _objectForItem: [items objectAtIndex: index] classes: classArray options: searchOptions];
        if (object == nil)
            continue;
        NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter: object];
        NSRect frame = index < [frames count] ? [[frames objectAtIndex: index] rectValue] : NSZeroRect;
        [item setDraggingFrame: view != nil ? viewRectFromScreen(view, frame) : frame];
        if (index < [images count])
            [item setImageComponentsProvider: [[images objectAtIndex: index] imageComponentsProvider]];
        block(item, (NSInteger) index, &stop);
        if (update != nil)
            update((NSInteger) index, item);
        [item release];
    }
}

@implementation NSDraggingSession

@synthesize draggingFormation = _formation, animatesToStartingPositionsOnCancelOrFail = _animates,
            draggingLeaderIndex = _leaderIndex, draggingPasteboard = _pasteboard,
            draggingSequenceNumber = _sequenceNumber, draggingLocation = _location;

- (instancetype) _initWithItems: (NSArray<NSDraggingItem *> *) items
                           view: (NSView *) view
                          event: (NSEvent *) event
                         source: (id<NSDraggingSource>) source
                     pasteboard: (NSPasteboard *) pasteboard
{
    if ((self = [super init])) {
        _items = [items copy];
        _screenFrames = [[NSMutableArray alloc] init];
        for (NSDraggingItem *item in items)
            [_screenFrames addObject: [NSValue valueWithRect: screenRectFromView(view, [item draggingFrame])]];
        _pasteboard = [pasteboard retain];
        _source = [(id) source retain];
        _view = [view retain];
        _event = [event retain];
        // The documented defaults, which both Macs report for a new session
        _formation = NSDraggingFormationNone;
        _animates = YES;
        _sequenceNumber = nextSequenceNumber();
        _location = screenPointOfEvent(event);
    }
    return self;
}

- (void) dealloc {
    [_items release];
    [_screenFrames release];
    [_pasteboard release];
    [_source release];
    [_view release];
    [_event release];
    [super dealloc];
}

- (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) enumOpts
                                   forView: (NSView *) view
                                   classes: (NSArray<Class> *) classArray
                             searchOptions: (NSDictionary *) searchOptions
                                usingBlock: (void (^)(NSDraggingItem *, NSInteger, BOOL *)) block
{
    enumerateItems(_pasteboard, _screenFrames, _items, view, classArray, searchOptions, block,
                   ^(NSInteger index, NSDraggingItem *item) {
                       // Until the drag starts, what the block sets is what will be dragged
                       NSRect frame = [item draggingFrame];
                       [_screenFrames replaceObjectAtIndex: index
                                                withObject: [NSValue valueWithRect: view != nil
                                                                                         ? screenRectFromView(view, frame)
                                                                                         : frame]];
                       [[_items objectAtIndex: index] setImageComponentsProvider: [item imageComponentsProvider]];
                   });
}

// The items' images drawn into one, which covers all their frames (in screen coordinates)
- (NSImage *) _composedImageInRect: (NSRect *) bounds {
    NSRect all = NSZeroRect;
    for (NSValue *frame in _screenFrames)
        all = NSIsEmptyRect(all) ? [frame rectValue] : NSUnionRect(all, [frame rectValue]);
    *bounds = all;
    if (NSIsEmptyRect(all))
        return nil;
    NSImage *image = [[[NSImage alloc] initWithSize: all.size] autorelease];
    [image lockFocus];
    for (NSUInteger i = 0; i < [_items count]; i++) {
        NSRect frame = [[_screenFrames objectAtIndex: i] rectValue];
        for (NSDraggingImageComponent *component in [[_items objectAtIndex: i] imageComponents]) {
            id contents = [component contents];
            NSImage *picture = nil;
            if ([contents isKindOfClass: [NSImage class]])
                picture = contents;
            else if (contents != nil && CFGetTypeID((CFTypeRef) contents) == CGImageGetTypeID())
                picture = [[[NSImage alloc] initWithCGImage: (CGImageRef) contents size: NSZeroSize] autorelease];
            if (picture == nil)
                continue;
            NSRect place = [component frame];
            place.origin.x += NSMinX(frame) - NSMinX(all);
            place.origin.y += NSMinY(frame) - NSMinY(all);
            [picture drawInRect: place fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1];
        }
    }
    [image unlockFocus];
    return image;
}

// Runs once the event handler that began the session has returned, through the view's drag
- (void) _start {
    NSRect bounds;
    NSImage *image = [self _composedImageInRect: &bounds];
    NSPoint mouse = screenPointOfEvent(_event);
    _mouseInImage = NSMakePoint(mouse.x - NSMinX(bounds), mouse.y - NSMinY(bounds));
    NSPoint origin = bounds.origin;
    NSWindow *window = [_view window];
    if (window != nil)
        origin = [window convertRectFromScreen: NSMakeRect(origin.x, origin.y, 0, 0)].origin;
    [_view _dragImage: image
        atWindowLocation: origin
                  offset: NSZeroSize
                   event: _event
              pasteboard: _pasteboard
                  source: self
               slideBack: _animates];
}

- (void) _scheduleStart {
    [[NSRunLoop currentRunLoop]
        performSelector: @selector(_start)
                 target: self
               argument: nil
                  order: 0
                  modes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSEventTrackingRunLoopMode,
                                                    NSModalPanelRunLoopMode, nil]];
}

- (id) _draggingSource {
    return _source;
}

// The drag reports the dragged image's corner on the screen; the source is told where the mouse is
- (NSPoint) _mousePointForImagePoint: (NSPoint) point {
    return NSMakePoint(point.x + _mouseInImage.x, point.y + _mouseInImage.y);
}

#pragma mark The drag's source

- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) local {
    return [_source draggingSession: self
        sourceOperationMaskForDraggingContext: local ? NSDraggingContextWithinApplication
                                                     : NSDraggingContextOutsideApplication];
}

- (BOOL) ignoreModifierKeysWhileDragging {
    return [_source respondsToSelector: @selector(ignoreModifierKeysForDraggingSession:)] &&
           [_source ignoreModifierKeysForDraggingSession: self];
}

- (void) draggedImage: (NSImage *) image beganAt: (NSPoint) point {
    _location = [self _mousePointForImagePoint: point];
    if ([_source respondsToSelector: @selector(draggingSession:willBeginAtPoint:)])
        [_source draggingSession: self willBeginAtPoint: _location];
}

- (void) draggedImage: (NSImage *) image movedTo: (NSPoint) point {
    _location = [self _mousePointForImagePoint: point];
    if ([_source respondsToSelector: @selector(draggingSession:movedToPoint:)])
        [_source draggingSession: self movedToPoint: _location];
}

- (void) draggedImage: (NSImage *) image endedAt: (NSPoint) point operation: (NSDragOperation) operation {
    _location = [self _mousePointForImagePoint: point];
    if ([_source respondsToSelector: @selector(draggingSession:endedAtPoint:operation:)])
        [_source draggingSession: self endedAtPoint: _location operation: operation];
}

@end

@implementation NSDraggingSession (NSDraggingManager)

+ (id) _sourceForDestination: (id) dragSource {
    return [dragSource isKindOfClass: [NSDraggingSession class]] ? [dragSource _draggingSource] : dragSource;
}

// The NSDraggingInfo documentation: holding Control narrows the mask to link, Option to copy and Command to
// generic, unless the source ignores the modifier keys
+ (NSDragOperation) _operationMask: (NSDragOperation) mask narrowedForSource: (id) dragSource {
    if ([dragSource respondsToSelector: @selector(ignoreModifierKeysWhileDragging)] &&
        [dragSource ignoreModifierKeysWhileDragging])
        return mask;
    NSEventModifierFlags flags = [NSEvent modifierFlags];
    if (flags & NSEventModifierFlagControl)
        return mask & NSDragOperationLink;
    if (flags & NSEventModifierFlagOption)
        return mask & NSDragOperationCopy;
    if (flags & NSEventModifierFlagCommand)
        return mask & NSDragOperationGeneric;
    return mask;
}

+ (void) _enumerateItemsOfDraggingInfo: (id<NSDraggingInfo>) info
                                source: (id) dragSource
                               forView: (NSView *) view
                               classes: (NSArray<Class> *) classArray
                         searchOptions: (NSDictionary *) searchOptions
                            usingBlock: (void (^)(NSDraggingItem *, NSInteger, BOOL *)) block
{
    NSArray *frames = nil, *images = nil;
    if ([dragSource isKindOfClass: [NSDraggingSession class]]) {
        NSDraggingSession *session = dragSource;
        frames = session->_screenFrames;
        images = session->_items;
    } else {
        // A drag from another application brings no frames: each item is where the mouse is
        NSPoint location = [info draggingLocation];
        NSWindow *window = [info draggingDestinationWindow];
        if (window != nil)
            location = [window convertRectToScreen: NSMakeRect(location.x, location.y, 0, 0)].origin;
        NSMutableArray *at = [NSMutableArray array];
        NSUInteger count = [[[info draggingPasteboard] pasteboardItems] count];
        for (NSUInteger i = 0; i < count; i++)
            [at addObject: [NSValue valueWithRect: NSMakeRect(location.x, location.y, 0, 0)]];
        frames = at;
    }
    enumerateItems([info draggingPasteboard], frames, images, view, classArray, searchOptions, block, nil);
}

@end
