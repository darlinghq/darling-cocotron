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

#import "NSCGSDropSession.h"
#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSWindow-Drag.h>
#import <AppKit/NSWindow.h>
#import "NSPasteboardAliases.h"

@implementation NSCGSDropSession

- (id) initWithSession: (id<CGSDropSession>) session window: (NSWindow *) window localSource: (id) source {
    if ((self = [super init])) {
        _session = [session retain];
        _destination = [window retain];
        _types = [NSPasteboardCanonicalTypes([session types]) copy];
        _sourceOperations = [session sourceOperations];
        static int nextSequence = 0;
        _sequence = ++nextSequence;
        _localSource = [source retain];
        _validItems = -1;
        _animatesToDestination = NO;
    }
    return self;
}

- (void) dealloc {
    [_session release];
    [_destination release];
    [_receiver release];
    [_types release];
    [_localSource release];
    [super dealloc];
}

- (id<CGSDropSession>) dropSession {
    return _session;
}

- (NSDragOperation) updateAtPoint: (CGPoint) point {
    if (_invalidated)
        return NSDragOperationNone;

    // The window system reports positions from the window's top left corner, while the receiver is addressed in
    // window coordinates, y up.
    _point = NSMakePoint(point.x, [_destination frame].size.height - point.y);

    id receiver = [_destination isVisible] ? [_destination _receiverForDragSession: self] : nil;
    NSDragOperation operation = NSDragOperationNone;
    if (receiver != _receiver) {
        _acceptedOperations = NSDragOperationNone;
        id old = _receiver;
        _receiver = [receiver retain];
        @try {
            [old draggingExited: self];
        } @finally {
            [old release];
        }
        operation = [_receiver draggingEntered: self];
    } else {
        operation = [_receiver draggingUpdated: self];
    }
    if (_invalidated)
        return NSDragOperationNone;

    // The receiver chooses from the mask it was offered (NSDraggingInfo), which is the source's action list
    // narrowed by the modifier keys. The window system narrows what is said to the source to one operation.
    return operation & [self draggingSourceOperationMask];
}

- (NSDragOperation) performDropWithOperation: (NSDragOperation) operation {
    _dropAnnounced = YES;
    _acceptedOperations = operation;

    NSDragOperation performed = NSDragOperationNone;
    if (!_invalidated && _acceptedOperations != NSDragOperationNone && [_destination isVisible] &&
        [_destination _receiverForDragSession: self] == _receiver) {
        // Each step re-checks the receiver: reading the selection pumps the window system's connection, and a
        // callback can move the drag somewhere else entirely.
        BOOL prepared = ![_receiver respondsToSelector: @selector(prepareForDragOperation:)] ||
                        [_receiver prepareForDragOperation: self];
        if (prepared && [_destination isVisible] &&
            [_destination _receiverForDragSession: self] == _receiver &&
            [_receiver performDragOperation: self] && !_transferFailed)
            performed = _acceptedOperations;
    }
    if (performed != NSDragOperationNone)
        [_receiver concludeDragOperation: self];
    _invalidated = YES;
    // Whether or not it was performed, the drop ends the drag for its destination
    if ([_receiver respondsToSelector: @selector(draggingEnded:)])
        [_receiver draggingEnded: self];
    return performed;
}

- (void) leave {
    _invalidated = YES;
    [_receiver draggingExited: self];
}

// A drag pasteboard is read-only, so there is nothing to clear.
- (NSInteger) clearContents {
    return _sequence;
}

#pragma mark NSPasteboard

- (NSString *) name {
    return NSDragPboard;
}

- (NSInteger) changeCount {
    return _sequence;
}

- (NSArray *) types {
    return NSPasteboardTypesWithAliases(_types);
}

- (BOOL) _storesFileURLs {
    return [_types containsObject: NSPasteboardTypeFileURL];
}

- (NSData *) dataForType: (NSPasteboardType) type {
    type = NSPasteboardCanonicalType(type);
    if (!_invalidated && ![_types containsObject: type])
        return NSPasteboardDerivedDataForType(self, type);
    // A source that never offered a type has not failed to send one, so this must not be counted as a broken
    // transfer.
    if (_invalidated)
        return nil;
    // The session reads NSFilenamesPboardType from the file lists that file managers publish.
    NSData *data = [_session dataForType: type];
    if (data == nil && ![type isEqual: NSFilenamesPboardType])
        data = NSPasteboardDerivedDataForType(self, type);
    if (data == nil) {
        _transferFailed = YES;
        return nil;
    }
    return data;
}

#pragma mark NSDraggingInfo

- (NSPasteboard *) draggingPasteboard {
    // A dragging session of this application is read where its source wrote it, the drag pasteboard, item by item,
    // as on macOS. What the older -dragImage:... offers is read as the drag offers it.
    if ([_localSource isKindOfClass: [NSDraggingSession class]])
        return [NSPasteboard pasteboardWithName: NSPasteboardNameDrag];
    return self;
}

- (NSDragOperation) draggingSourceOperationMask {
    // Once dropped, report the operation this target chose; NSDraggingInfo has no separate accessor for the
    // selected operation.
    if (_dropAnnounced)
        return _acceptedOperations;
    return [NSDraggingSession _operationMask: _sourceOperations narrowedForSource: _localSource];
}

- (NSPoint) draggingLocation {
    return _point;
}

- (NSWindow *) draggingDestinationWindow {
    return _destination;
}

- (NSImage *) draggedImage {
    return nil;
}

- (NSPoint) draggedImageLocation {
    return _point;
}

- (id) draggingSource {
    // Nil for a drag from another application, as documented
    return [NSDraggingSession _sourceForDestination: _localSource];
}

- (NSDraggingFormation) draggingFormation {
    return _formation;
}

- (void) setDraggingFormation: (NSDraggingFormation) formation {
    _formation = formation;
}

- (BOOL) animatesToDestination {
    return _animatesToDestination;
}

- (void) setAnimatesToDestination: (BOOL) animates {
    _animatesToDestination = animates;
}

- (NSInteger) numberOfValidItemsForDrop {
    return _validItems >= 0 ? _validItems : (NSInteger) [[[self draggingPasteboard] pasteboardItems] count];
}

- (void) setNumberOfValidItemsForDrop: (NSInteger) count {
    _validItems = count;
}

- (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) enumOpts
                                   forView: (NSView *) view
                                   classes: (NSArray<Class> *) classArray
                             searchOptions: (NSDictionary *) searchOptions
                                usingBlock: (void (^)(NSDraggingItem *, NSInteger, BOOL *)) block
{
    [NSDraggingSession _enumerateItemsOfDraggingInfo: self
                                              source: _localSource
                                             forView: view
                                             classes: classArray
                                       searchOptions: searchOptions
                                          usingBlock: block];
}

- (NSSpringLoadingHighlight) springLoadingHighlight {
    return NSSpringLoadingHighlightNone;
}

- (void) resetSpringLoading {
}

- (NSInteger) draggingSequenceNumber {
    return _sequence;
}

- (void) slideDraggedImageTo: (NSPoint) point {
}

- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination {
    return nil;
}

@end
