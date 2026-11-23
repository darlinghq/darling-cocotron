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

#import "X11DropSession.h"
#import <AppKit/NSDraggingManager.h>
#import "DarlingFileURIList.h"
#import "NSPasteboardAliases.h"
#import "X11Window.h"
#import "X11Display.h"
#import <AppKit/NSWindow-Drag.h>
#import <AppKit/NSWindow.h>

@implementation X11DropSession

- (id) initWithSource: (Window) source
      selectionName: (NSString *) selection
             target: (X11Window *) target
               types: (NSArray *) types
    sourceOperations: (NSDragOperation) operations
{
    if ((self = [super initWithName: selection])) {
        _xdpy = [(X11Display *) [NSDisplay currentDisplay] display];
        _targetWindow = [target retain];
        _destination = [[target delegate] retain];
        _source = source;
        _types = [NSPasteboardCanonicalTypes(types) copy];
        _sourceOperations = operations;
        static int nextSequence = 0;
        _sequence = ++nextSequence;
        _validItems = -1;
        _animatesToDestination = NO;
    }
    return self;
}

- (void) dealloc {
    [_targetWindow release];
    [_destination release];
    [_receiver release];
    [_types release];
    [_localSource release];
    [super dealloc];
}

- (void) setLocalSource: (id) source {
    [source retain];
    [_localSource release];
    _localSource = source;
}

- (BOOL) matchesSource: (Window) source {
    // XDND requires a target to ignore every message that is not part of the
    // drag it is currently holding.
    return !_invalidated && source != None && source == _source;
}

- (NSDragOperation) updateAtRootX: (int) rootX
                           rootY: (int) rootY
                 requestedActions: (NSDragOperation) actions
{
    if (_invalidated)
        return NSDragOperationNone;

    int windowX = 0, windowY = 0;
    Window child;
    // XDND positions are root-relative device pixels, while the receiver is
    // addressed in window coordinates. A reparenting window manager inserts
    // frames between the root and this window, so translate rather than subtract.
    if (!XTranslateCoordinates(_xdpy, DefaultRootWindow(_xdpy),
                               [_targetWindow windowHandle], rootX, rootY, &windowX,
                               &windowY, &child))
        return NSDragOperationNone;
    _point = [_targetWindow logicalPoint: NSMakePoint(windowX, windowY)];

    // A drop already being performed owns the outcome; the source keeps sending
    // positions while the receiver reads the selection, and those must not
    // renegotiate it.
    if (_dropAnnounced)
        return NSDragOperationNone;

    id receiver = [_targetWindow isMapped] ? [_destination _receiverForDragSession: self]
                                     : nil;
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

    // A source that leaves the action field empty is not refusing, it is just
    // older than the action negotiation, so fall back to everything it offers.
    if (actions == NSDragOperationNone)
        actions = _sourceOperations;

    // The receiver chooses from the mask it was offered (NSDraggingInfo), which is
    // the source's action list narrowed by the modifier keys; the action the source
    // requested is the one taken when the receiver allows several.
    NSDragOperation accepted = operation & [self draggingSourceOperationMask];
    // One operation for the whole drag: the source draws its cursor from
    // XdndStatus and later reports one action in XdndFinished, so narrowing to a
    // single bit keeps the three in step.
    if (accepted & actions & (NSDragOperationCopy | NSDragOperationMove | NSDragOperationLink))
        accepted &= actions;
    if (accepted & NSDragOperationCopy)
        accepted = NSDragOperationCopy;
    else if (accepted & NSDragOperationMove)
        accepted = NSDragOperationMove;
    else if (accepted & NSDragOperationLink)
        accepted = NSDragOperationLink;
    else
        accepted = NSDragOperationNone;
    _acceptedOperations = accepted;
    return accepted;
}

- (NSDragOperation) performDrop {
    _dropAnnounced = YES;

    NSDragOperation performed = NSDragOperationNone;
    if (!_invalidated && _acceptedOperations != NSDragOperationNone &&
        [_targetWindow isMapped] &&
        [_destination _receiverForDragSession: self] == _receiver) {
        // Each step re-checks the receiver: reading the selection pumps the X
        // connection, and a callback can move the drag somewhere else entirely.
        BOOL prepared = ![_receiver respondsToSelector: @selector(prepareForDragOperation:)] ||
                        [_receiver prepareForDragOperation: self];
        if (prepared && [_targetWindow isMapped] &&
            [_destination _receiverForDragSession: self] == _receiver &&
            [_receiver performDragOperation: self] && !_transferFailed)
            performed = _acceptedOperations;
    }
    if (performed != NSDragOperationNone)
        [_receiver concludeDragOperation: self];
    [self invalidate];
    // Whether or not it was performed, the drop ends the drag for its destination
    if ([_receiver respondsToSelector: @selector(draggingEnded:)])
        [_receiver draggingEnded: self];
    return performed;
}

- (void) leave {
    // A source may send XdndLeave as soon as it sees XdndDrop, while the
    // transfer this session owns is still running.
    if (_dropAnnounced)
        return;
    [self invalidate];
    [_receiver draggingExited: self];
}

- (void) invalidate {
    _invalidated = YES;
}

// A drag pasteboard is read-only, so there is nothing to clear. Inheriting the
// pasteboard's own -clearContents would also make -dealloc take ownership of the
// drag selection on an already destroyed helper window.
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
    // A source that never offered a type has not failed to send one, so this
    // must not be counted as a broken transfer.
    if (_invalidated)
        return nil;
    // NSFilenamesPboardType is an AppKit type with no X counterpart; file
    // managers publish their files as text/uri-list.
    NSData *data = [super dataForType: [type isEqual: NSFilenamesPboardType]
                                          ? @"text/uri-list"
                                          : type];
    if (!data) {
        _transferFailed = YES;
        return nil;
    }
    if (![type isEqual: NSFilenamesPboardType])
        return data;
    NSArray *files = DarlingFilenamesFromURIList(data);
    if (!files) {
        _transferFailed = YES;
        return nil;
    }
    return [NSPropertyListSerialization dataFromPropertyList: files
                                                     format: NSPropertyListXMLFormat_v1_0
                                           errorDescription: NULL];
}

#pragma mark NSDraggingInfo

- (NSPasteboard *) draggingPasteboard {
    // A dragging session of this application is read where its source wrote it,
    // the drag pasteboard, item by item, as on macOS. What the older
    // -dragImage:... offers is read as the drag offers it.
    if ([_localSource isKindOfClass: [NSDraggingSession class]])
        return [NSPasteboard pasteboardWithName: NSPasteboardNameDrag];
    return self;
}

- (NSDragOperation) draggingSourceOperationMask {
    // Once dropped, report the operation this target chose; NSDraggingInfo has no
    // separate accessor for the selected operation.
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

- (int) draggingSequenceNumber {
    return _sequence;
}

- (void) slideDraggedImageTo: (NSPoint) point {
}

- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination {
    return nil;
}

@end
